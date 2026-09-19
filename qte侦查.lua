--[[
    方块故事(Block Tales) QTE 侦查 + 自动按工具【手机版 · v4】
    ------------------------------------------------------------------
    面板标题显示版本号（当前：v4 · 09-19 11:45）——
    没看到 "v4" 就是执行了旧版，请重新导入本文件。

    v4 修复：
      - 面板拆成「一步一个 pcall」，任何一步失败都不会让后面的按钮消失
      - 创建失败会直接在屏幕上显示红色报错（不用翻控制台）
      - 砍掉易出问题的 API：ScrollingFrame / AutomaticSize / UIListLayout / 字体枚举
      - 面板尺寸严格限制在屏幕内，按钮用格子手工排版，绝不跑到屏幕外
      - 拖动改用全局 UIS.InputChanged，手指移出标题栏也继续跟手

    全部操作都在屏幕上的小面板里点，不需要键盘。
    面板日志可以直接「复制日志」发给我。

    ⚠ 性能说明（这一版专门优化过，上一版会卡）：
      - 改用 DescendantAdded 事件监听新增元素（不再 0.1 秒全量遍历 GUI 树）
      - 慢速轮询降到 1.2 秒一次，只扫非系统 ScreenGui，并让出主线程
      - 日志限流（每秒最多 6 行）+ 面板只显示最近 60 行、过长截断
      - 面板文字关闭自动换行（换行排版是手机上的卡顿来源）
      - 剪贴板复制的是完整日志（不受面板显示限制）

    面板按钮：
      打印GUI / Remote 开关 / 清空 / 自动按开关 / 复制日志 / Press 按法 / 隐藏
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

-- ==================== 开关 ====================
local HookRemoteLog = false      -- Remote 记录（默认关，很刷屏）
local HeuristicPress = false     -- 启发式自动按
local IncludeSystemUI = false    -- 是否连 Roblox 自身 UI(CoreGui) 一起抓
local PressMethod = "auto"       -- "auto" / "firesignal" / "vim" / "mouse"
local GUI_NAME = "QTE_Recon_Panel"
local VERSION = "v4"                         -- ★ 面板标题会显示这个，用来确认你跑的是哪一版
local BUILD = "09-19 11:45"
local dead = false                           -- 点「停止」后置 true，所有循环退出
local POLL_INTERVAL = 1.2        -- 慢速轮询间隔（秒）
local LOG_RATE_PER_SEC = 6       -- 日志每秒最多几行

-- 前置声明（面板按钮回调要用）
local seen = setmetatable({}, { __mode = "k" })   -- 弱键：实例销毁后自动回收，不泄漏
local remoteFilter = {}
local remoteCount = {}
local remoteCallCount = 0
local heuristicTry
local ourGui

-- 永远跳过：我们自己的界面 + 其他脚本界面
local ALWAYS_SKIP = {
    [GUI_NAME] = true,
    WindUI = true,
    CoordTP = true,
}

-- Roblox 自身 UI（在 CoreGui 里）：默认跳过（树很大、会卡）
-- IncludeSystemUI = true 时连它们一起抓（面板上「系统UI」按钮切换）
local SYSTEM_SKIP = {
    RobloxGui = true,
    RobloxLoadingGui = true,
    BubbleChat = true,
    Chat = true,
    PlayerList = true,
    TopBar = true,
    Topbar = true,
    Notification = true,
}

local function shouldSkipRoot(name)
    if ALWAYS_SKIP[name] then return true end
    if SYSTEM_SKIP[name] and not IncludeSystemUI then return true end
    return false
end

-- ==================== 日志 ====================
local MAX_SHOW = 60              -- 面板最多显示多少行
local SHOW_WIDTH = 54            -- 面板每行截断宽度
local showLines = {}
local allLines = {}              -- 剪贴板用（完整）
local logDirty = false
local logLabel
local rateCount, rateStart = 0, os.clock()

local function addLine(s, force)
    s = tostring(s)
    table.insert(allLines, s)
    if #allLines > 4000 then table.remove(allLines, 1) end

    -- 限流：超了就只统计，不刷屏（force=true 时不受限，用于自检等关键信息）
    local now = os.clock()
    if now - rateStart >= 1 then
        rateStart, rateCount = now, 0
    end
    rateCount = rateCount + 1
    if not force and rateCount > LOG_RATE_PER_SEC then
        if rateCount == LOG_RATE_PER_SEC + 1 then
            table.insert(showLines, "...（日志太多，已限流）")
            logDirty = true
        end
        return
    end

    table.insert(showLines, #s > SHOW_WIDTH and (s:sub(1, SHOW_WIDTH) .. "…") or s)
    if #showLines > MAX_SHOW then table.remove(showLines, 1) end
    logDirty = true
    print("[QTE侦查] " .. s)
end

-- ==================== 小工具 ====================
local function pathOf(o, depth)
    local parts, cur, d = {}, o, 0
    while cur and d < (depth or 4) do
        table.insert(parts, 1, cur.Name .. "<" .. cur.ClassName .. ">")
        cur = cur.Parent
        d = d + 1
    end
    return table.concat(parts, " / ")
end

local function desc(o)
    local pos, sz = "?", "?"
    pcall(function()
        pos = string.format("(%.0f,%.0f)", o.AbsolutePosition.X, o.AbsolutePosition.Y)
        sz = string.format("%.0fx%.0f", o.AbsoluteSize.X, o.AbsoluteSize.Y)
    end)
    local extra = {}
    if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
        local t = tostring(o.Text or "")
        if t ~= "" then table.insert(extra, "文字=" .. t:sub(1, 24)) end
    end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then
        table.insert(extra, "图片=" .. tostring(o.Image))
    end
    if o:IsA("GuiButton") then table.insert(extra, "★可点按钮") end
    return string.format("%s | 位置%s 大小%s%s", pathOf(o), pos, sz,
        #extra > 0 and (" | " .. table.concat(extra, " ")) or "")
end

-- 只在「新增元素」时用（只比父链名字，不拼字符串）
local function inSkipTree(o)
    local cur, d = o, 0
    while cur and d < 6 do
        if shouldSkipRoot(cur.Name) then return true end
        cur = cur.Parent
        d = d + 1
    end
    return false
end

-- 按钮绑定：Activated + MouseButton1Click 双保险（手机执行器有时只触发其中一个）
local function bindTap(btn, fn)
    local last = 0
    local function fire()
        local now = os.clock()
        if now - last < 0.25 then return end
        last = now
        task.spawn(fn)
    end
    pcall(function() btn.Activated:Connect(fire) end)
    pcall(function() btn.MouseButton1Click:Connect(fire) end)
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title), Text = tostring(text), Duration = 3,
        })
    end)
end

-- ==================== 清理上次执行残留的旧面板 ====================
local function purgeOld()
    local parents = { pg }
    pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
    pcall(function() if gethui then table.insert(parents, gethui()) end end)
    local n = 0
    for _, p in ipairs(parents) do
        local ok, kids = pcall(function() return p:GetChildren() end)
        if ok then
            for _, c in ipairs(kids) do
                if c.Name == GUI_NAME then
                    pcall(function() c:Destroy() end)
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- ==================== 面板 GUI ====================
local main, bubble, logBtnRemote, logBtnAuto, dumpAll

local function buildGui()
    local parent = pg
    pcall(function()
        if gethui then parent = gethui() end
    end)

    -- 屏幕尺寸：面板必须完整放进屏幕内，否则按钮会被挤到屏幕外（上一版的坑）
    local vp = Vector2.new(800, 400)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then vp = cam.ViewportSize end
    end)

    local panelW = math.floor(math.min(400, vp.X * 0.55))
    local panelH = math.floor(math.min(380, vp.Y * 0.72))
    panelW = math.floor(math.max(250, math.min(panelW, vp.X - 24)))
    panelH = math.floor(math.max(190, math.min(panelH, vp.Y - 56)))

    local titleH = 30
    local COLS, ROWS, BTN_H, GAP = 4, 3, 32, 6
    local btnAreaH = ROWS * BTN_H + (ROWS - 1) * GAP
    local logTop = titleH + 6
    local logH = math.max(36, panelH - logTop - btnAreaH - 10)
    local btnW = math.floor((panelW - 12 - (COLS - 1) * GAP) / COLS)

    -- 每一步单独 pcall：任何一步失败都不影响其他部分，并且错误会显示在屏幕上
    local errs = {}
    local function step(what, fn)
        local ok, err = pcall(fn)
        if not ok then
            table.insert(errs, what .. ": " .. tostring(err))
            print("[QTE侦查] 创建失败 " .. what .. " -> " .. tostring(err))
        end
        return ok
    end

    local gui
    step("ScreenGui", function()
        gui = Instance.new("ScreenGui")
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9999
        gui.Parent = parent
    end)
    if not gui then                       -- 兜底：直接挂 PlayerGui
        gui = Instance.new("ScreenGui")
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.Parent = pg
    end
    ourGui = gui

    -- 主面板
    main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, panelW, 0, panelH)
    main.Position = UDim2.new(0, 10, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui

    -- 标题栏（拖这里移动面板）
    local title = Instance.new("Frame")
    title.Name = "TitleBar"
    title.Size = UDim2.new(1, 0, 0, titleH)
    title.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
    title.BorderSizePixel = 0
    title.Active = true                    -- ★ 必须，否则收不到触摸
    title.Parent = main

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -10, 1, 0)
    titleText.Position = UDim2.new(0, 6, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "QTE侦查 " .. VERSION .. " · " .. BUILD .. "   拖这里移动"
    titleText.TextColor3 = Color3.fromRGB(235, 235, 245)
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextWrapped = false
    titleText.Active = true                -- ★ 必须
    titleText.Parent = title

    -- 日志区：纯 Frame + TextLabel（不用 ScrollingFrame / AutomaticSize，这两个最容易被旧客户端坑）
    local logBox = Instance.new("Frame")
    logBox.Name = "LogBox"
    logBox.Size = UDim2.new(1, -12, 0, logH)
    logBox.Position = UDim2.new(0, 6, 0, logTop)
    logBox.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    logBox.BorderSizePixel = 0
    logBox.Parent = main

    local linesFit = math.max(3, math.floor((logH - 6) / 14))

    logLabel = Instance.new("TextLabel")
    logLabel.Name = "LogText"
    logLabel.Size = UDim2.new(1, -8, 0, 0)
    logLabel.Position = UDim2.new(0, 4, 0, 3)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = ""
    logLabel.TextColor3 = Color3.fromRGB(190, 220, 190)
    logLabel.TextSize = 11
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextWrapped = false
    logLabel.Parent = logBox

    -- 按钮区：手工排格子（不用 UIListLayout / Wrap，避免布局 API 差异）
    local btnRow = Instance.new("Frame")
    btnRow.Name = "Buttons"
    btnRow.Size = UDim2.new(1, -12, 0, btnAreaH)
    btnRow.Position = UDim2.new(0, 6, 1, -(btnAreaH + 6))
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = main

    local index = 0
    local function mkBtn(text, color, onClick)
        local col = index % COLS
        local row = math.floor(index / COLS)
        index = index + 1
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, btnW, 0, BTN_H)
        b.Position = UDim2.new(0, col * (btnW + GAP), 0, row * (BTN_H + GAP))
        b.BackgroundColor3 = color or Color3.fromRGB(56, 56, 72)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 250)
        b.TextSize = 13
        b.TextScaled = true                -- 窄屏也放得下
        b.Parent = btnRow
        bindTap(b, function()
            local ok, err = pcall(onClick)
            if not ok then addLine("按钮出错: " .. tostring(err), true) end
        end)
        return b
    end

    mkBtn("打印GUI", Color3.fromRGB(52, 84, 120), function()
        dumpAll()
        notify("QTE侦查", "已打印当前可见 GUI")
    end)

    logBtnRemote = mkBtn("Remote:关", Color3.fromRGB(60, 60, 78), function()
        HookRemoteLog = not HookRemoteLog
        remoteFilter, remoteCount, remoteCallCount = {}, {}, 0
        logBtnRemote.Text = HookRemoteLog and "Remote:开" or "Remote:关"
        logBtnRemote.BackgroundColor3 = HookRemoteLog
            and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(60, 60, 78)
        addLine(HookRemoteLog and "=== 开始记录 Remote（现在去做 QTE）==="
            or "=== 停止记录 Remote ===", true)
        notify("QTE侦查", HookRemoteLog and "开始记录 Remote" or "已停止记录")
    end)

    logBtnAuto = mkBtn("自动按:关", Color3.fromRGB(60, 60, 78), function()
        HeuristicPress = not HeuristicPress
        logBtnAuto.Text = HeuristicPress and "自动按:开" or "自动按:关"
        logBtnAuto.BackgroundColor3 = HeuristicPress
            and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(60, 60, 78)
        addLine(HeuristicPress and "=== 启发式自动按：开启 ===" or "=== 启发式自动按：关闭 ===", true)
        notify("QTE侦查", HeuristicPress and "自动按已开启" or "自动按已关闭")
    end)

    local sysBtn = mkBtn("系统UI:关", Color3.fromRGB(60, 60, 78), function()
        IncludeSystemUI = not IncludeSystemUI
        sysBtn.Text = IncludeSystemUI and "系统UI:开" or "系统UI:关"
        sysBtn.BackgroundColor3 = IncludeSystemUI
            and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(60, 60, 78)
        addLine(IncludeSystemUI
            and "=== 连 Roblox 自身UI一起抓（可能变卡，抓完建议关掉）==="
            or "=== 只抓游戏UI ===", true)
        notify("QTE侦查", IncludeSystemUI and "含系统UI（可能卡）" or "只抓游戏UI")
    end)

    mkBtn("清空", Color3.fromRGB(90, 70, 50), function()
        showLines, allLines = {}, {}
        seen = setmetatable({}, { __mode = "k" })
        remoteFilter, remoteCount, remoteCallCount = {}, {}, 0
        logDirty = true
        addLine("=== 已清空（现在去做一次 QTE）===", true)
        notify("QTE侦查", "日志已清空")
    end)

    mkBtn("复制日志", Color3.fromRGB(46, 96, 130), function()
        local text = table.concat(allLines, "\n")
        local fn = setclipboard or toclipboard or (syn and syn.setclipboard)
        if fn then
            pcall(fn, text)
            addLine("已复制 " .. #allLines .. " 行日志到剪贴板", true)
            notify("QTE侦查", "日志已复制，粘贴给我即可")
        else
            notify("QTE侦查", "这个执行器没有 setclipboard")
        end
    end)

    local pressBtn = mkBtn("Press:auto", Color3.fromRGB(70, 70, 92), function()
        if PressMethod == "auto" then
            PressMethod = "firesignal"
        elseif PressMethod == "firesignal" then
            PressMethod = "vim"
        elseif PressMethod == "vim" then
            PressMethod = "mouse"
        else
            PressMethod = "auto"
        end
        pressBtn.Text = "Press:" .. PressMethod
        addLine("按法切换为：" .. PressMethod, true)
    end)

    local hideBtn = mkBtn("隐藏", Color3.fromRGB(60, 60, 78), function()
        main.Visible = false
        bubble.Visible = true
    end)

    local stopBtn = mkBtn("停止", Color3.fromRGB(130, 62, 62), function()
        addLine("=== 已停止侦查（重新执行脚本可再启动）===", true)
        dead = true
        task.wait(0.2)
        pcall(function() ourGui:Destroy() end)
        notify("QTE侦查", "已停止，脚本已卸载")
    end)

    -- 收起后的小圆点
    bubble = Instance.new("TextButton")
    bubble.Name = "Bubble"
    bubble.Size = UDim2.new(0, 48, 0, 48)
    bubble.Position = UDim2.new(1, -62, 0, 120)
    bubble.BackgroundColor3 = Color3.fromRGB(46, 96, 130)
    bubble.BorderSizePixel = 0
    bubble.Text = "QTE"
    bubble.TextColor3 = Color3.fromRGB(240, 240, 250)
    bubble.TextSize = 14
    bubble.Visible = false
    bubble.Parent = gui
    bindTap(bubble, function()
        main.Visible = true
        bubble.Visible = false
    end)

    -- ★ 拖动：用全局 UIS.InputChanged，手指移出标题栏也继续跟手（面板上任何非按钮处都能拖）
    local dragging, dragStart, startPos = false, nil, nil
    local function beginDrag(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
    pcall(function() title.InputBegan:Connect(beginDrag) end)
    pcall(function() titleText.InputBegan:Connect(beginDrag) end)
    pcall(function() main.InputBegan:Connect(beginDrag) end)

    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
            and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- 日志刷新：0.5 秒一次，只显示能放下的行数（不需要滚动条）
    task.spawn(function()
        while not dead do
            task.wait(0.5)
            if logDirty and logLabel then
                logDirty = false
                pcall(function()
                    local from = math.max(1, #showLines - linesFit + 1)
                    local out = {}
                    for i = from, #showLines do
                        table.insert(out, showLines[i])
                    end
                    logLabel.Text = table.concat(out, "\n")
                end)
            end
        end
    end)

    -- 任何一步失败都直接显示在屏幕上（手机上也能看到，不用翻控制台）
    if #errs > 0 then
        local banner = Instance.new("TextLabel")
        banner.Name = "ErrBanner"
        banner.Size = UDim2.new(1, -12, 0, 40)
        banner.Position = UDim2.new(0, 6, 0, logTop)
        banner.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
        banner.BackgroundTransparency = 0.1
        banner.Text = "⚠ 创建出错：" .. tostring(errs[1])
        banner.TextColor3 = Color3.fromRGB(255, 235, 235)
        banner.TextSize = 11
        banner.TextWrapped = true
        banner.ZIndex = 5
        banner.Parent = main
        for _, e in ipairs(errs) do
            addLine("创建失败 > " .. e, true)
        end
    end

    addLine(string.format("面板 %dx%d / 屏幕 %dx%d / 每屏 %d 行",
        panelW, panelH, vp.X, vp.Y, linesFit), true)
end

-- ==================== 判定一个元素值不值得报告 ====================
local function consider(o, silent)
    if dead then return end
    if not o:IsA("GuiObject") then return end
    if not o.Visible then return end
    if seen[o] then return end
    seen[o] = true
    if silent then return end                       -- 首次静默建档，不刷日志
    if ourGui and o:IsDescendantOf(ourGui) then return end
    addLine("发现 > " .. desc(o))
    if HeuristicPress and heuristicTry then
        task.spawn(function()
            pcall(heuristicTry, o)
        end)
    end
end

-- ==================== 侦查1：事件监听新增元素 ====================
local function getRoots()
    local t = { pg }
    pcall(function() table.insert(t, game:GetService("CoreGui")) end)
    return t
end

for _, r in ipairs(getRoots()) do
    pcall(function()
        r.DescendantAdded:Connect(function(o)
            if dead then return end
            task.spawn(function()
                pcall(function()
                    if dead or inSkipTree(o) then return end
                    consider(o)
                end)
            end)
        end)
    end)
end

-- ==================== 侦查2：慢速轮询（抓「由隐藏变显示」的元素） ====================
local firstPass = true

local function slowScan()
    for _, r in ipairs(getRoots()) do
        local ok, screens = pcall(function() return r:GetChildren() end)
        if ok then
            for _, sg in ipairs(screens) do
                if sg:IsA("ScreenGui") and not shouldSkipRoot(sg.Name) then
                    local enabled = true
                    pcall(function() enabled = sg.Enabled end)
                    if enabled then
                        local ok2, list = pcall(function() return sg:GetDescendants() end)
                        if ok2 then
                            for _, o in ipairs(list) do
                                pcall(consider, o, firstPass)
                            end
                        end
                    end
                end
            end
        end
        task.wait()                                  -- 让出主线程，避免卡帧
    end
    firstPass = false
end

-- ==================== 侦查3：记录「你点到了哪个 GUI」 ====================
UIS.InputBegan:Connect(function(input)
    if dead then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local pos = input.Position
    for _, r in ipairs(getRoots()) do
        pcall(function()
            local objs = r:GetGuiObjectsAtPosition(pos.X, pos.Y)
            for _, o in ipairs(objs) do
                if not (ourGui and o:IsDescendantOf(ourGui)) and not inSkipTree(o) then
                    addLine(string.format("你点到了 (%.0f,%.0f) > %s", pos.X, pos.Y, desc(o)))
                end
            end
        end)
    end

    -- 3D 世界里的目标：有些 QTE 不在屏幕上，而是 3D 里的 BillboardGui/SurfaceGui/ClickDetector
    pcall(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local ray = cam:ViewportPointToRay(pos.X, pos.Y)
        local params = RaycastParams.new()
        pcall(function() params.FilterType = Enum.RaycastFilterType.Exclude end)
        pcall(function() params.FilterType = Enum.RaycastFilterType.Blacklist end)
        params.FilterDescendantsInstances = { lp.Character }
        local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
        if not (hit and hit.Instance) then return end
        local inst = hit.Instance
        for _, cls in ipairs({ "BillboardGui", "SurfaceGui", "ClickDetector", "ProximityPrompt" }) do
            local found = inst:FindFirstChildOfClass(cls)
            if not found and inst.Parent then
                found = inst.Parent:FindFirstChildOfClass(cls)
            end
            if found then
                addLine(string.format("你点到了3D > %s 上有 %s", inst:GetFullName(), found:GetFullName()))
            end
        end
    end)
end)

-- ==================== 侦查4：Remote 调用（默认关） ====================
pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
            remoteCallCount = remoteCallCount + 1
            if HookRemoteLog and remoteCallCount < 3000 then
                local key = self:GetFullName()
                remoteCount[key] = (remoteCount[key] or 0) + 1
                if remoteCount[key] <= 2 and not remoteFilter[key] then
                    remoteFilter[key] = true
                    local args = { ... }
                    local shown = {}
                    for i = 1, math.min(#args, 4) do
                        local v = args[i]
                        local ty = typeof(v)
                        if ty == "Instance" then
                            table.insert(shown, v:GetFullName())
                        elseif ty == "Vector3" or ty == "CFrame" then
                            table.insert(shown, tostring(v))
                        else
                            table.insert(shown, tostring(v):sub(1, 24))
                        end
                    end
                    addLine("Remote > " .. method .. " " .. key
                        .. (#shown > 0 and (" | 参数: " .. table.concat(shown, ", ")) or ""))
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)

-- ==================== 侦查5：3D 世界里的 UI（BillboardGui/SurfaceGui） ====================
pcall(function()
    workspace.DescendantAdded:Connect(function(o)
        if dead then return end
        local cls = o.ClassName
        if cls == "BillboardGui" or cls == "SurfaceGui" then
            addLine("世界UI > " .. o:GetFullName())
        end
    end)
end)

-- ==================== 侦查6：全量打印 ====================
dumpAll = function()
    addLine("====== 当前可见 GUI ======")
    local list = {}
    for _, r in ipairs(getRoots()) do
        pcall(function()
            for _, sg in ipairs(r:GetChildren()) do
                if sg:IsA("ScreenGui") and not shouldSkipRoot(sg.Name) then
                    for _, o in ipairs(sg:GetDescendants()) do
                        if o:IsA("GuiObject") and o.Visible then
                            local sz = o.AbsoluteSize
                            if sz.X * sz.Y > 150 then
                                table.insert(list, o)
                            end
                        end
                    end
                end
            end
        end)
    end
    table.sort(list, function(a, b)
        return (a.AbsolutePosition.Y * 10000 + a.AbsolutePosition.X)
            < (b.AbsolutePosition.Y * 10000 + b.AbsolutePosition.X)
    end)
    for _, o in ipairs(list) do
        addLine("  " .. desc(o))
    end
    addLine("====== 共 " .. #list .. " 个 ======")
end

-- ==================== 按下去 ====================
local function pressAt(x, y, obj)
    x, y = math.floor(x), math.floor(y)

    local function byFireSignal()
        if not obj then return false end
        if firesignal then
            pcall(firesignal, obj.MouseButton1Down)
            pcall(firesignal, obj.MouseButton1Click)
            pcall(firesignal, obj.MouseButton1Up)
            pcall(firesignal, obj.Activated)
            return true
        end
        return (pcall(function() obj:Activate() end))
    end

    local function byVIM()
        local VIM = game:GetService("VirtualInputManager")
        return pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function byExecutorMouse()
        return pcall(function()
            if mousemoveabs then mousemoveabs(x, y) end
            if mouse1click then mouse1click() end
        end)
    end

    if PressMethod == "firesignal" then
        return byFireSignal()
    elseif PressMethod == "vim" then
        return byVIM()
    elseif PressMethod == "mouse" then
        return byExecutorMouse()
    end

    local done = false
    if obj and obj:IsA("GuiButton") then
        done = byFireSignal()
    end
    if not done then
        if not byVIM() then
            byExecutorMouse()
        end
    end
    return true
end

-- ==================== 启发式自动按 ====================
heuristicTry = function(o)
    if dead or not HeuristicPress then return end
    if not o.Parent or not o.Visible then return end
    if not o:IsA("GuiButton") then return end
    local sz = o.AbsoluteSize
    if sz.X < 12 or sz.Y < 12 then return end
    if sz.X > 240 or sz.Y > 240 then return end
    local x = o.AbsolutePosition.X + sz.X / 2
    local y = o.AbsolutePosition.Y + sz.Y / 2
    addLine(string.format("自动点击 > %s", desc(o)))
    pressAt(x, y, o)
end

-- ==================== 启动 ====================
local purged = purgeOld()
local okGui, guiErr = pcall(buildGui)
if not okGui then
    print("[QTE侦查] 面板创建失败：" .. tostring(guiErr))
end

-- 慢速轮询（第一遍静默建档，不刷日志）
task.spawn(function()
    while not dead do
        pcall(slowScan)
        task.wait(POLL_INTERVAL)
    end
end)

-- ==================== 启动自检（告诉我们到底在看哪里） ====================
local function selfCheck()
    local names = {}
    pcall(function()
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") then
                local en = true
                pcall(function() en = sg.Enabled end)
                table.insert(names, sg.Name .. (en and "✓" or "✗"))
            end
        end
    end)
    addLine("自检 PlayerGui 有 " .. #names .. " 个 ScreenGui："
        .. (#names > 0 and table.concat(names, ", ") or "空"), true)

    local cnt = 0
    pcall(function() cnt = #pg:GetDescendants() end)
    addLine("自检 PlayerGui 元素总数：" .. cnt, true)

    local cg
    pcall(function() cg = game:GetService("CoreGui") end)
    if not cg then
        addLine("自检 CoreGui：取不到 ❌（执行器权限不够，Roblox自身UI抓不了）", true)
        return
    end
    local list
    local ok = pcall(function() list = cg:GetChildren() end)
    if not ok or not list then
        addLine("自检 CoreGui：不可读 ❌（执行器权限不够，Roblox自身UI抓不了）", true)
        return
    end
    local top = {}
    for _, c in ipairs(list) do table.insert(top, c.Name) end
    addLine("自检 CoreGui：可读 ✅ 顶层 " .. #list .. " 个：" .. table.concat(top, ", "), true)
end

task.spawn(function()
    task.wait(0.3)
    addLine("====== QTE 侦查 " .. VERSION .. " (" .. BUILD .. ") 已启动 ======", true)
    if purged > 0 then
        addLine("已清理旧面板 " .. purged .. " 个（如果你之前看到两个面板，现在只剩一个）", true)
    end
    pcall(selfCheck)
    addLine("先点「清空」，手动做一次 QTE，再点「复制日志」发我", true)
end)

notify("QTE侦查已启动", "面板在左上角，拖标题栏可移动")
