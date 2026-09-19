--[[
    方块故事(Block Tales) QTE 侦查 + 自动按工具【手机版】
    ------------------------------------------------------------------
    全部操作都在屏幕上的小面板里点，不需要键盘。
    日志直接显示在面板上，点「复制日志」就能复制全部内容发给我。

    面板按钮：
      打印GUI   = 立刻列出当前屏幕上所有可见 GUI（位置/大小/图片/文字）
      Remote    = 开关「Remote 调用记录」，做 QTE 前点成"开"，做完点"关"
      清空      = 清空日志和已记录列表，重新侦查
      自动按    = 开关「启发式自动按」（新出现的小按钮自动点）
      复制日志  = 把全部日志复制到剪贴板
      隐藏      = 收起面板（变成右下角一个小圆点，再点展开）

    用法：
      1. 执行本脚本（单独跑，别和方块故事汉化脚本同时执行）
      2. 面板出现在屏幕左上角，可以拖标题栏移动
      3. 手动成功做一次 QTE（弹弓/炸药/自动剑）
      4. 点「复制日志」，把内容发给我
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

-- ==================== 开关 ====================
local HookRemoteLog = false      -- Remote 记录
local HeuristicPress = false     -- 启发式自动按
local PressMethod = "auto"       -- "auto" / "firesignal" / "vim" / "mouse"
local GUI_NAME = "QTE_Recon_Panel"

-- 前置声明：buildGui 里的按钮回调要用这些，必须先声明（否则会写成全局变量）
local seen = {}
local remoteFilter = {}
local remoteCount = {}
local heuristicTry

-- ==================== 日志（屏幕显示 + 剪贴板） ====================
local MAX_SHOW = 150             -- 面板上最多显示多少行
local showLines = {}             -- 面板显示用
local allLines = {}              -- 复制用（全量）
local logDirty = false
local logLabel, logScroll, logCopyHint

local function addLine(s)
    s = tostring(s)
    table.insert(showLines, s)
    if #showLines > MAX_SHOW then
        table.remove(showLines, 1)
    end
    table.insert(allLines, s)
    if #allLines > 5000 then
        table.remove(allLines, 1)
    end
    logDirty = true
    print("[QTE侦查] " .. s)
end

-- ==================== 小工具 ====================
local function roots()
    local t = { pg }
    pcall(function() table.insert(t, game:GetService("CoreGui")) end)
    pcall(function() if gethui then table.insert(t, gethui()) end end)
    return t
end

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
        if t ~= "" then table.insert(extra, "文字=" .. t:sub(1, 28)) end
    end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then
        table.insert(extra, "图片=" .. tostring(o.Image))
    end
    if o:IsA("GuiButton") then table.insert(extra, "★可点按钮") end
    return string.format("%s | 位置%s 大小%s%s", pathOf(o), pos, sz,
        #extra > 0 and (" | " .. table.concat(extra, " ")) or "")
end

-- 排除我们自己的面板和系统界面，避免刷屏
local function isNoise(o)
    local p = pathOf(o, 8)
    if p:find(GUI_NAME, 1, true) then return true end
    if p:find("QTE_Recon", 1, true) then return true end
    if p:find("WindUI", 1, true) or p:find("CoordTP", 1, true) then return true end
    if p:find("RobloxGui", 1, true) or p:find("PlayerList", 1, true)
        or p:find("Chat", 1, true) then return true end
    return false
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title), Text = tostring(text), Duration = 3,
        })
    end)
end

-- ==================== 面板 GUI ====================
local main, bubble, logBtnRemote, logBtnAuto

local function buildGui()
    local parent = pg
    pcall(function()
        if gethui then parent = gethui() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent

    -- 面板尺寸按实际屏幕算（手机小屏也能放下）
    local vp = Vector2.new(800, 400)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then vp = cam.ViewportSize end
    end)
    local panelW = math.clamp(math.floor(vp.X * 0.42), 250, 350)
    local panelH = math.clamp(math.floor(vp.Y * 0.62), 190, 330)

    -- 主面板
    main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, panelW, 0, panelH)
    main.Position = UDim2.new(0, 8, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    main.BackgroundTransparency = 0.08
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = false          -- 用下面的手动拖动（触摸更稳，避免双重移动）
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(70, 70, 90)
    stroke.Thickness = 1

    -- 标题栏（拖动 + 隐藏按钮）
    local title = Instance.new("Frame")
    title.Name = "TitleBar"
    title.Size = UDim2.new(1, 0, 0, 32)
    title.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
    title.BorderSizePixel = 0
    title.Parent = main
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -80, 1, 0)
    titleText.Position = UDim2.new(0, 10, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "QTE 侦查面板（可拖动）"
    titleText.TextColor3 = Color3.fromRGB(230, 230, 240)
    titleText.TextSize = 14
    titleText.Font = Enum.Font.GothamBold
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = title

    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 62, 0, 22)
    hideBtn.Position = UDim2.new(1, -68, 0, 5)
    hideBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 78)
    hideBtn.BorderSizePixel = 0
    hideBtn.Text = "隐藏"
    hideBtn.TextColor3 = Color3.fromRGB(235, 235, 245)
    hideBtn.TextSize = 13
    hideBtn.Font = Enum.Font.Gotham
    hideBtn.Parent = title
    Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

    -- 日志区
    logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, -16, 1, -124)
    logScroll.Position = UDim2.new(0, 8, 0, 38)
    logScroll.BackgroundColor3 = Color3.fromRGB(15, 15, 19)
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 4
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = main
    Instance.new("UICorner", logScroll).CornerRadius = UDim.new(0, 8)

    logLabel = Instance.new("TextLabel")
    logLabel.Name = "LogText"
    logLabel.Size = UDim2.new(1, -8, 0, 0)
    logLabel.Position = UDim2.new(0, 4, 0, 4)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = ""
    logLabel.TextColor3 = Color3.fromRGB(190, 220, 190)
    logLabel.TextSize = 11
    logLabel.Font = Enum.Font.Code
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextWrapped = true
    logLabel.AutomaticSize = Enum.AutomaticSize.Y
    logLabel.Parent = logScroll

    -- 按钮行
    local btnRow = Instance.new("Frame")
    btnRow.Name = "Buttons"
    btnRow.Size = UDim2.new(1, -16, 0, 74)
    btnRow.Position = UDim2.new(0, 8, 1, -82)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = main
    local list = Instance.new("UIListLayout", btnRow)
    list.FillDirection = Enum.FillDirection.Horizontal
    list.Wrap = true
    list.Padding = UDim.new(0, 6)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local function mkBtn(text, order, w, h, color, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, h or 32)
        b.BackgroundColor3 = color or Color3.fromRGB(52, 52, 66)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(238, 238, 248)
        b.TextSize = 13
        b.Font = Enum.Font.GothamBold
        b.LayoutOrder = order
        b.Parent = btnRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(onClick)
            if not ok then
                addLine("按钮出错: " .. tostring(err))
            end
        end)
        return b
    end

    mkBtn("打印GUI", 1, 84, 32, Color3.fromRGB(52, 84, 120), function()
        dumpAll()
        notify("QTE侦查", "已打印当前可见 GUI")
    end)

    logBtnRemote = mkBtn("Remote:关", 2, 92, 32, Color3.fromRGB(60, 60, 78), function()
        HookRemoteLog = not HookRemoteLog
        remoteFilter = {}
        logBtnRemote.Text = HookRemoteLog and "Remote:开" or "Remote:关"
        logBtnRemote.BackgroundColor3 = HookRemoteLog
            and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(60, 60, 78)
        addLine(HookRemoteLog and "=== 开始记录 Remote（现在去做 QTE）==="
            or "=== 停止记录 Remote ===")
        notify("QTE侦查", HookRemoteLog and "开始记录 Remote" or "已停止记录")
    end)

    mkBtn("清空", 3, 60, 32, Color3.fromRGB(90, 70, 50), function()
        showLines, allLines = {}, {}
        seen, remoteFilter, remoteCount = {}, {}, {}
        logDirty = true
        addLine("=== 日志已清空 ===")
        notify("QTE侦查", "日志已清空")
    end)

    logBtnAuto = mkBtn("自动按:关", 4, 92, 32, Color3.fromRGB(60, 60, 78), function()
        HeuristicPress = not HeuristicPress
        logBtnAuto.Text = HeuristicPress and "自动按:开" or "自动按:关"
        logBtnAuto.BackgroundColor3 = HeuristicPress
            and Color3.fromRGB(46, 120, 70) or Color3.fromRGB(60, 60, 78)
        addLine(HeuristicPress and "=== 启发式自动按：开启 ===" or "=== 启发式自动按：关闭 ===")
        notify("QTE侦查", HeuristicPress
            and "自动按已开启（新出现的小按钮会自动点）" or "自动按已关闭")
    end)

    mkBtn("复制日志", 5, 92, 32, Color3.fromRGB(46, 96, 130), function()
        local text = table.concat(allLines, "\n")
        local fn = setclipboard or toclipboard or (syn and syn.setclipboard)
        if fn then
            pcall(fn, text)
            addLine("已复制 " .. #allLines .. " 行日志到剪贴板")
            notify("QTE侦查", "日志已复制，粘贴给我即可")
        else
            notify("QTE侦查", "这个执行器没有 setclipboard")
        end
    end)

    local pressBtn = mkBtn("Press:auto", 6, 98, 32, Color3.new(0.35, 0.35, 0.45), function()
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
        addLine("按法切换为：" .. PressMethod)
    end)

    -- 收起后的小圆点
    bubble = Instance.new("TextButton")
    bubble.Name = "Bubble"
    bubble.Size = UDim2.new(0, 46, 0, 46)
    bubble.Position = UDim2.new(1, -60, 0, 120)
    bubble.BackgroundColor3 = Color3.fromRGB(46, 96, 130)
    bubble.BorderSizePixel = 0
    bubble.Text = "QTE"
    bubble.TextColor3 = Color3.fromRGB(240, 240, 250)
    bubble.TextSize = 13
    bubble.Font = Enum.Font.GothamBold
    bubble.Visible = false
    bubble.Parent = gui
    Instance.new("UICorner", bubble).CornerRadius = UDim.new(1, 0)

    hideBtn.MouseButton1Click:Connect(function()
        main.Visible = false
        bubble.Visible = true
    end)
    bubble.MouseButton1Click:Connect(function()
        main.Visible = true
        bubble.Visible = false
    end)

    -- 拖动（触摸 + 鼠标都支持）
    local dragging, dragStart, startPos = false, nil, nil
    local function beginDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end
    title.InputBegan:Connect(beginDrag)
    titleText.InputBegan:Connect(beginDrag)
    title.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    -- 日志刷新（每 0.3 秒，避免频繁写 Text 卡顿）
    task.spawn(function()
        while true do
            task.wait(0.3)
            if logDirty and logLabel then
                logDirty = false
                pcall(function()
                    logLabel.Text = table.concat(showLines, "\n")
                end)
            end
        end
    end)
end

-- ==================== 侦查1：新出现的可见 GUI ====================
function scanNew()
    for _, r in ipairs(roots()) do
        local ok, list = pcall(function() return r:GetDescendants() end)
        if ok then
            for _, o in ipairs(list) do
                if o:IsA("GuiObject") then
                    if o.Visible and not isNoise(o) then
                        if not seen[o] then
                            seen[o] = true
                            addLine("新显示 > " .. desc(o))
                            if HeuristicPress and heuristicTry then
                                task.spawn(function()
                                    pcall(heuristicTry, o)
                                end)
                            end
                        end
                    elseif not o.Visible then
                        seen[o] = nil
                    end
                end
            end
        end
    end
end

-- ==================== 侦查2：记录「你点到了哪个 GUI」 ====================
-- 手机上你手指点中的 GUI 也会触发 InputBegan，这里能直接抓到目标
UIS.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local pos = input.Position
    for _, r in ipairs(roots()) do
        pcall(function()
            local objs = r:GetGuiObjectsAtPosition(pos.X, pos.Y)
            for _, o in ipairs(objs) do
                if not isNoise(o) then
                    addLine(string.format("你点到了 (%.0f,%.0f) > %s", pos.X, pos.Y, desc(o)))
                end
            end
        end)
    end
end)

-- ==================== 侦查3：Remote 调用记录 ====================
pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if HookRemoteLog and (method == "FireServer" or method == "InvokeServer")
            and typeof(self) == "Instance" then
            local key = self:GetFullName()
            remoteCount[key] = (remoteCount[key] or 0) + 1
            if remoteCount[key] <= 3 then
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
                        table.insert(shown, tostring(v):sub(1, 30))
                    end
                end
                addLine("Remote > " .. method .. " " .. key
                    .. (#shown > 0 and (" | 参数: " .. table.concat(shown, ", ")) or ""))
            end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
    table.insert(allLines, "Remote Hook 已安装")
end)

-- ==================== 侦查4：全量打印 ====================
function dumpAll()
    addLine("====== 当前屏幕可见 GUI ======")
    local list = {}
    for _, r in ipairs(roots()) do
        pcall(function()
            for _, o in ipairs(r:GetDescendants()) do
                if o:IsA("GuiObject") and o.Visible and not isNoise(o) then
                    local sz = o.AbsoluteSize
                    if sz.X * sz.Y > 150 then
                        table.insert(list, o)
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

-- ==================== 按下去（三种方式） ====================
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

    -- auto：按钮先走 firesignal（手机上最靠谱），再补真实点击
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

-- ==================== 启发式自动按（默认关） ====================
heuristicTry = function(o)
    if not HeuristicPress then return end
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
local okGui, guiErr = pcall(buildGui)
if not okGui then
    print("[QTE侦查] 面板创建失败：" .. tostring(guiErr))
end

task.spawn(function()
    while true do
        task.wait(0.1)
        pcall(scanNew)
    end
end)

addLine("====== QTE 侦查已启动 ======")
addLine("先点「清空」，再手动做一次 QTE，不会看的话点「复制日志」发我")
notify("QTE侦查已启动", "面板在左上角，拖标题栏可移动")
