--[[
    方块故事(Block Tales) QTE 完美攻击 · 改写版 v1
    ==================================================================
    原理（基于你提供的 Cobalt 拦截日志解码）：
      1. 你用道具时，客户端先发一个「动作请求」：
           { K1 = { { "Dynamite", 目标, 总点数 } }, n = 1 }
      2. QTE 长条走完，客户端再发一个「命中数上报」：
           { K2 = { { 命中数 } }, n = 1 }      -- 0/1/2/3
      3. 服务器按命中数结算：命中数 == 全部 → Success = true（完美）

    → 本脚本把「命中数上报」在发出的瞬间改写成「总点数」，
      于是服务器永远认为是完美攻击。你不需要点 QTE。

    安全性设计：
      · 协议 key 每局随机（上一份日志是 V/6，这一份是 U/5）
        → 脚本不写死任何 key，完全靠「形状识别 + 第一次动作时学习」
      · 第 1 次动作只观察不定稿（用来确认哪个 key 是命中上报）
      · 回合计数器（值会超过 4 的那个）会被自动排除，绝不改写
      · 面板上可以随时关掉改写

    用法：
      1. 执行脚本 → 面板出现在左上角
      2. 先用一次道具（随便打，中不中都行）→ 脚本学会命中上报的 key
      3. 之后每次用道具，命中数都会被改写成满分
      4. 想验证：点「导出文件」把日志发我
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

local VERSION = "v1"
local BUILD = "09-19 14:10"
local GUI_NAME = "QTE_Rewrite_Panel"

-- ==================== 开关 ====================
local RewriteOn = true          -- 改写总开关
local RewriteMode = "total"     -- "total" = 改写成总点数（完美）/ "3" = 固定 3 / "off"
local Verbose = true            -- 详细日志（记录每个发出的包）
local dead = false
local ExecName = "未知执行器"
pcall(function()
    if identifyexecutor then ExecName = identifyexecutor() end
end)

-- ==================== 学习状态 ====================
local MoveKey = nil             -- 动作请求的 key
local HitKey = nil              -- 命中上报的 key（学到后才开始改写）
local CounterKeys = {}          -- 被判定为「回合计数器」的 key（值会 > 4）
local keySeen = {}              -- key -> { 出现过的值 }
local turn = { active = false, total = nil, move = nil, nums = {} }
local lastTotalNum = nil
local stat = { moves = 0, resolves = 0, rewrites = 0, lastHit = "—", lastTotal = "—" }

-- ==================== 日志 ====================
local SHOW_WIDTH = 56
local MAX_SHOW = 60
local showLines, allLines = {}, {}
local logDirty, logLabel = false, nil
local rateCount, rateStart = 0, os.clock()
local LOG_RATE = 12

local function addLine(s, force)
    s = tostring(s)
    table.insert(allLines, s)
    if #allLines > 4000 then table.remove(allLines, 1) end
    local now = os.clock()
    if now - rateStart >= 1 then rateStart, rateCount = now, 0 end
    rateCount = rateCount + 1
    if not force and rateCount > LOG_RATE then return end
    table.insert(showLines, #s > SHOW_WIDTH and (s:sub(1, SHOW_WIDTH) .. "…") or s)
    if #showLines > MAX_SHOW then table.remove(showLines, 1) end
    logDirty = true
    print("[QTE改写] " .. s)
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title), Text = tostring(text), Duration = 3,
        })
    end)
end

-- ==================== 包形状识别（认 key 不认名字） ====================
-- 返回 nil 或 { kind = "move"|"resolve"|"num", key = ..., ... }
local function shapeOf(payload)
    if type(payload) ~= "table" then return nil end
    for k, v in pairs(payload) do
        if type(v) == "table" and type(v[1]) == "table" then
            local e = v[1]
            if type(e.Move) == "string" then
                -- 结算包：{ { Move = "...", Damage = ..., Success = true } }
                return { kind = "resolve", key = k, move = e.Move }
            elseif type(e[1]) == "string" then
                -- 动作请求：{ { "Dynamite", 目标, 总点数 } }
                return { kind = "move", key = k, move = e[1], target = e[2], total = e[3] }
            elseif type(e[1]) == "number" then
                -- 单个数字：{ { 3 } }  ← 命中上报 / 回合计数器 都是这个形状
                return { kind = "num", key = k, val = e[1] }
            end
        end
    end
    return nil
end

local function noteKeyValue(key, val)
    keySeen[key] = keySeen[key] or {}
    table.insert(keySeen[key], val)
    if val > 4 and not CounterKeys[key] then
        CounterKeys[key] = true
        addLine("排除 key [" .. tostring(key) .. "]：值 " .. tostring(val) .. " > 4，是回合计数器", true)
        if HitKey == key then
            HitKey = nil
            addLine("⚠ 命中上报 key 被推翻，重新学习", true)
        end
    end
end

-- ==================== 处理一个待发送的包（可改写） ====================
local function process(args)
    local payload = args[1]
    local info = shapeOf(payload)
    if not info then return false end

    if info.kind == "move" then
        stat.moves = stat.moves + 1
        stat.lastTotal = tostring(info.total)
        MoveKey = info.key
        if type(info.total) == "number" then lastTotalNum = info.total end
        turn = { active = true, total = info.total, move = info.move, nums = {} }
        if Verbose then
            addLine(string.format("动作 #%d  %s  总点数=%s  key=[%s]",
                stat.moves, tostring(info.move), tostring(info.total), tostring(info.key)))
        end
        return false

    elseif info.kind == "num" then
        noteKeyValue(info.key, info.val)
        if turn.active then
            table.insert(turn.nums, { key = info.key, val = info.val })
        end
        if Verbose then
            addLine(string.format("  数字包 key=[%s] 值=%s%s",
                tostring(info.key), tostring(info.val),
                turn.active and " (回合内)" or ""))
        end
        -- ★ 改写：只有学到 HitKey 之后才动手
        if RewriteOn and RewriteMode ~= "off" and HitKey and info.key == HitKey
            and not CounterKeys[info.key] then
            local target
            if RewriteMode == "total" then
                target = turn.active and turn.total or nil
                if type(target) ~= "number" then target = lastTotalNum or 3 end
            else
                target = tonumber(RewriteMode) or 3
            end
            if type(info.val) == "number" and info.val < target then
                payload[info.key] = { { target } }
                stat.rewrites = stat.rewrites + 1
                stat.lastHit = tostring(target)
                addLine(string.format("★ 改写命中数 %d → %d（第 %d 次）",
                    info.val, target, stat.rewrites), true)
                notify("QTE改写", string.format("命中数 %d → %d", info.val, target))
                return true
            else
                stat.lastHit = tostring(info.val)
            end
        end
        return false

    elseif info.kind == "resolve" then
        stat.resolves = stat.resolves + 1
        -- 只有「我们自己的动作」的结算才算本回合结束（敌人攻击的结算不打断）
        local mine = (not turn.active) or turn.move == nil
            or info.move == turn.move or info.move == "BruhMiss"
        if turn.active and mine then
            local last = turn.nums[#turn.nums]
            if last then
                stat.lastHit = tostring(last.val)
                if not HitKey then
                    HitKey = last.key
                    addLine(string.format("★ 学到命中上报 key=[%s]（本回合命中 %s）从下一次开始改写",
                        tostring(HitKey), tostring(last.val)), true)
                    notify("QTE改写", "已学会，下次开始改写")
                end
            end
            turn.active = false
        end
        if Verbose then
            addLine("  结算包 Move=" .. tostring(info.move)
                .. (info.move == "BruhMiss" and "（打空）" or ""))
        end
        return false
    end
    return false
end

-- ==================== Hook FireServer ====================
local hookOk, hookErr = pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and typeof(self) == "Instance" then
            local args = { ... }
            if args[1] ~= nil then
                local ok, changed = pcall(process, args)
                if ok and changed then
                    return oldNamecall(self, table.unpack(args))
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)

-- ==================== 面板 ====================
local main, bubble, logLabelRef, statusLabel, btnRewrite, btnMode

local function buildGui()
    local parent = pg
    pcall(function() if gethui then parent = gethui() end end)

    local vp = Vector2.new(800, 400)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then vp = cam.ViewportSize end
    end)

    local panelW = math.floor(math.max(280, math.min(400, math.min(vp.X * 0.55, vp.X - 24))))
    local panelH = math.floor(math.max(200, math.min(320, math.min(vp.Y * 0.62, vp.Y - 56))))

    local titleH = 30
    local statusH = 62
    local COLS, BTN_H, GAP = 4, 32, 6
    local btnRows = 2
    local btnAreaH = btnRows * BTN_H + (btnRows - 1) * GAP
    local logTop = titleH + statusH + 6
    local logH = math.max(36, panelH - logTop - btnAreaH - 10)
    local btnW = math.floor((panelW - 12 - (COLS - 1) * GAP) / COLS)

    local errs = {}
    local function step(what, fn)
        local ok, err = pcall(fn)
        if not ok then
            table.insert(errs, what .. ": " .. tostring(err))
            print("[QTE改写] 创建失败 " .. what .. " -> " .. tostring(err))
        end
        return ok
    end

    local gui
    step("ScreenGui", function()
        gui = Instance.new("ScreenGui")
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9998
        gui.Parent = parent
    end)
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.Parent = pg
    end

    main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, panelW, 0, panelH)
    main.Position = UDim2.new(0, 10, 0, 40)
    main.BackgroundColor3 = Color3.fromRGB(22, 26, 24)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui

    local title = Instance.new("Frame")
    title.Size = UDim2.new(1, 0, 0, titleH)
    title.BackgroundColor3 = Color3.fromRGB(36, 48, 42)
    title.BorderSizePixel = 0
    title.Active = true
    title.Parent = main

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -10, 1, 0)
    titleText.Position = UDim2.new(0, 6, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "QTE改写 " .. VERSION .. " · " .. BUILD .. "   拖这里移动"
    titleText.TextColor3 = Color3.fromRGB(230, 245, 235)
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextWrapped = false
    titleText.Active = true
    titleText.Parent = title

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -12, 0, statusH)
    statusLabel.Position = UDim2.new(0, 6, 0, titleH + 2)
    statusLabel.BackgroundColor3 = Color3.fromRGB(16, 20, 18)
    statusLabel.BackgroundTransparency = 0.15
    statusLabel.BorderSizePixel = 0
    statusLabel.Text = ""
    statusLabel.TextColor3 = Color3.fromRGB(190, 235, 205)
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.TextWrapped = false
    statusLabel.Parent = main

    local logBox = Instance.new("Frame")
    logBox.Size = UDim2.new(1, -12, 0, logH)
    logBox.Position = UDim2.new(0, 6, 0, logTop)
    logBox.BackgroundColor3 = Color3.fromRGB(13, 16, 15)
    logBox.BorderSizePixel = 0
    logBox.Parent = main

    local linesFit = math.max(3, math.floor((logH - 6) / 14))
    logLabel = Instance.new("TextLabel")
    logLabel.Size = UDim2.new(1, -8, 0, 0)
    logLabel.Position = UDim2.new(0, 4, 0, 3)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = ""
    logLabel.TextColor3 = Color3.fromRGB(180, 215, 185)
    logLabel.TextSize = 11
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextWrapped = false
    logLabel.Parent = logBox

    local btnRow = Instance.new("Frame")
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
        b.BackgroundColor3 = color or Color3.fromRGB(52, 62, 56)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(238, 248, 242)
        b.TextSize = 13
        b.TextScaled = true
        b.Parent = btnRow
        local last = 0
        local function fire()
            local now = os.clock()
            if now - last < 0.25 then return end
            last = now
            task.spawn(function()
                local ok, err = pcall(onClick)
                if not ok then addLine("按钮出错: " .. tostring(err), true) end
            end)
        end
        pcall(function() b.Activated:Connect(fire) end)
        pcall(function() b.MouseButton1Click:Connect(fire) end)
        return b
    end

    btnRewrite = mkBtn("改写:开", Color3.fromRGB(40, 110, 66), function()
        RewriteOn = not RewriteOn
        btnRewrite.Text = RewriteOn and "改写:开" or "改写:关"
        btnRewrite.BackgroundColor3 = RewriteOn
            and Color3.fromRGB(40, 110, 66) or Color3.fromRGB(80, 60, 60)
        addLine("改写开关：" .. (RewriteOn and "开" or "关"), true)
        notify("QTE改写", RewriteOn and "改写已开启" or "改写已关闭")
    end)

    btnMode = mkBtn("模式:满分", Color3.fromRGB(52, 62, 56), function()
        if RewriteMode == "total" then
            RewriteMode = "3"
        elseif RewriteMode == "3" then
            RewriteMode = "off"
        else
            RewriteMode = "total"
        end
        btnMode.Text = "模式:" .. (RewriteMode == "total" and "满分"
            or (RewriteMode == "3" and "固定3" or "不改"))
        addLine("改写模式：" .. RewriteMode, true)
    end)

    mkBtn("重新学习", Color3.fromRGB(90, 80, 50), function()
        HitKey = nil
        MoveKey = nil
        CounterKeys = {}
        keySeen = {}
        lastTotalNum = nil
        turn = { active = false, total = nil, move = nil, nums = {} }
        addLine("已清空学习结果，下一次动作重新学习", true)
        notify("QTE改写", "已重置学习，请再做一次动作")
    end)

    mkBtn("清空日志", Color3.fromRGB(70, 70, 60), function()
        showLines, allLines = {}, {}
        logDirty = true
    end)

    mkBtn("复制日志", Color3.fromRGB(46, 96, 130), function()
        local text = table.concat(allLines, "\n")
        local fn = setclipboard or toclipboard
        if fn then
            pcall(fn, text)
            addLine("已复制 " .. #allLines .. " 行", true)
            notify("QTE改写", "日志已复制")
        else
            notify("QTE改写", "没有 setclipboard")
        end
    end)

    mkBtn("导出文件", Color3.fromRGB(46, 110, 90), function()
        local name = "QTE改写日志_" .. tostring(os.date("%m%d_%H%M%S")) .. ".txt"
        local text = "执行器：" .. ExecName .. "\n版本：" .. VERSION .. " " .. BUILD
            .. "\n学到 HitKey=" .. tostring(HitKey) .. " MoveKey=" .. tostring(MoveKey)
            .. "\n改写次数=" .. stat.rewrites .. "\n----\n" .. table.concat(allLines, "\n")
        local fn = writefile or (syn and syn.writefile)
        if not fn then
            addLine("❌ 没有 writefile，请用「复制日志」", true)
            return
        end
        local ok, err = pcall(fn, name, text)
        if ok then
            addLine("✅ 已导出：" .. name, true)
            local ok2, ws = pcall(function() return getworkspace and getworkspace() end)
            if ok2 and ws then addLine("   文件夹：" .. tostring(ws), true) end
            notify("QTE改写", "已导出 " .. name)
        else
            addLine("❌ 导出失败：" .. tostring(err), true)
        end
    end)

    bubble = Instance.new("TextButton")
    bubble.Size = UDim2.new(0, 46, 0, 46)
    bubble.Position = UDim2.new(1, -60, 0, 180)
    bubble.BackgroundColor3 = Color3.fromRGB(40, 110, 66)
    bubble.BorderSizePixel = 0
    bubble.Text = "QTE"
    bubble.TextColor3 = Color3.fromRGB(240, 255, 245)
    bubble.TextSize = 13
    bubble.Visible = false
    bubble.Parent = gui

    mkBtn("隐藏", Color3.fromRGB(52, 62, 56), function()
        main.Visible = false
        bubble.Visible = true
    end)

    mkBtn("停止", Color3.fromRGB(130, 62, 62), function()
        addLine("已停止（重新执行可再启动）", true)
        dead = true
        task.wait(0.2)
        pcall(function() gui:Destroy() end)
        notify("QTE改写", "已停止")
    end)

    local function tap(b)
        local last = 0
        local function fire()
            local now = os.clock()
            if now - last < 0.25 then return end
            last = now
            if b == bubble then
                main.Visible = true
                bubble.Visible = false
            end
        end
        pcall(function() b.Activated:Connect(fire) end)
        pcall(function() b.MouseButton1Click:Connect(fire) end)
    end
    tap(bubble)

    -- 拖动：全局 InputChanged，手指移出标题栏也跟手
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

    -- 状态 + 日志刷新
    task.spawn(function()
        while not dead do
            task.wait(0.4)
            if logDirty and logLabel then
                logDirty = false
                pcall(function()
                    local from = math.max(1, #showLines - linesFit + 1)
                    local out = {}
                    for i = from, #showLines do table.insert(out, showLines[i]) end
                    logLabel.Text = table.concat(out, "\n")
                end)
            end
            if statusLabel then
                pcall(function()
                    statusLabel.Text = string.format(
                        "改写：%s（模式 %s）   Hook：%s\n学到命中key：%s   总点数：%s   最近命中：%s\n动作 %d 次 · 结算 %d 次 · ★改写 %d 次",
                        RewriteOn and "开" or "关", RewriteMode,
                        hookOk and "已装" or "失败",
                        HitKey and ("[" .. tostring(HitKey) .. "]") or "学习中（先做一次动作）",
                        tostring(stat.lastTotal), tostring(stat.lastHit),
                        stat.moves, stat.resolves, stat.rewrites)
                end)
            end
        end
    end)

    if #errs > 0 then
        local banner = Instance.new("TextLabel")
        banner.Size = UDim2.new(1, -12, 0, 40)
        banner.Position = UDim2.new(0, 6, 0, logTop)
        banner.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
        banner.Text = "⚠ 创建出错：" .. tostring(errs[1])
        banner.TextColor3 = Color3.fromRGB(255, 235, 235)
        banner.TextSize = 11
        banner.TextWrapped = true
        banner.ZIndex = 5
        banner.Parent = main
        for _, e in ipairs(errs) do addLine("创建失败 > " .. e, true) end
    end
end

-- ==================== 启动 ====================
pcall(function()
    local old = pg:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end
    if gethui then
        local h = gethui()
        local o2 = h and h:FindFirstChild(GUI_NAME)
        if o2 then o2:Destroy() end
    end
end)

local okGui, guiErr = pcall(buildGui)
if not okGui then
    print("[QTE改写] 面板创建失败：" .. tostring(guiErr))
end

if not hookOk then
    addLine("⚠ Hook 安装失败：" .. tostring(hookErr) .. "（脚本无法改写）", true)
end

addLine("====== QTE改写 " .. VERSION .. " (" .. BUILD .. ") 已启动 ======", true)
addLine("先用一次道具（中不中都行），脚本会学会命中上报的 key", true)
addLine("从第 2 次开始自动改写成满分", true)
notify("QTE改写已启动", "先做一次动作让它学习")
