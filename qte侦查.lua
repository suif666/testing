--[[
    方块故事(Block Tales) QTE 完美攻击 · 改写版 v2
    ==================================================================
    v1 的 bug：把「结算包」的层数数错了，导致回合永远不结束 → 一直显示"学习中"。
      我以为：{ K = { { Move = "..." } } }
      实际是：{ K = { { { Move = "..." }, [3] = 敌人 } } }   ← 多包了一层
    v2 改成「深度搜索」：不管包几层，只要在里面找到特征就认得。

    ---------------------------------------------------------------
    原理（基于 Cobalt 拦截日志解码）：
      1. 你用道具 → 客户端发「动作请求」：{ K1 = { { "Dynamite", 目标, 总点数 } } }
      2. QTE 走完 → 客户端发「命中数上报」：{ K2 = { { 命中数 } } }   -- 0/1/2/3
      3. 服务器：命中数 = 满分 → Success = true（完美攻击）
    → 本脚本在「命中数上报」发出的瞬间把它改成满分，你不用点 QTE。

    ---------------------------------------------------------------
    每局的协议 key 都随机（上一局 V/6，这一局 U/5），所以脚本不写死 key：
      · 按「形状」识别，自动学习哪个 key 是命中上报
      · 第 1 次动作只观察，从第 2 次开始改写
      · 回合计数器（值会超过 4 的那个）自动排除，永不改写
      · 学不到时可以点「手动key」自己指定

    用法：
      1. 执行 → 面板出现
      2. 先用一次道具（中不中都行）→ 状态栏变成 命中key：[x]
      3. 之后每次用道具都自动满分
      4. 没效果就点「导出文件」把日志发我
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

local VERSION = "v2"
local BUILD = "09-19 14:40"
local GUI_NAME = "QTE_Rewrite_Panel"

-- ==================== 开关 ====================
local RewriteOn = true
local RewriteMode = "total"     -- total / 3 / off
local ManualKey = nil           -- nil = 自动学习
local Diagnose = false          -- 诊断模式：记录所有 FireServer 包
local Verbose = true
local dead = false
local ExecName = "未知执行器"
pcall(function() if identifyexecutor then ExecName = identifyexecutor() end end)

-- ==================== 状态 ====================
local HitKey = nil
local MoveKey = nil
local CounterKeys = {}
local keySeen = {}
local numKeyOrder = {}
local turn = { id = 0, active = false, total = nil, move = nil, nums = {} }
local lastTotalNum = nil
local stat = { fireSeen = 0, moves = 0, nums = 0, resolves = 0, rewrites = 0,
               lastHit = "—", lastTotal = "—" }

local function effKey() return ManualKey or HitKey end

-- ==================== 日志 ====================
local SHOW_WIDTH = 58
local MAX_SHOW = 60
local showLines, allLines = {}, {}
local logDirty, logLabel = false, nil
local rateCount, rateStart = 0, os.clock()
local LOG_RATE = 12

local function addLine(s, force)
    s = tostring(s)
    table.insert(allLines, s)
    if #allLines > 5000 then table.remove(allLines, 1) end
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
        StarterGui:SetCore("SendNotification",
            { Title = tostring(title), Text = tostring(text), Duration = 3 })
    end)
end

-- ==================== 深度识别（这才是 v2 的核心修复） ====================
-- 返回 nil 或 { kind = "move"|"num"|"resolve", entry = 那个表, ... }
local function classifyEntry(t)
    if type(t) ~= "table" then return nil end
    -- 结算元素：{ Move = "Slingshot", Damage = ..., Success = true }
    if type(t.Move) == "string" then
        return { kind = "resolve", entry = t, move = t.Move, success = t.Success == true }
    end
    -- 动作请求元素：{ "Slingshot", 目标Instance, 3 }
    if type(t[1]) == "string" then
        if type(t[2]) == "number" or typeof(t[2]) == "Instance" then
            return { kind = "move", entry = t, move = t[1], target = t[2], total = t[3] }
        end
        return nil
    end
    -- 单个数字元素：{ 3 }
    if type(t[1]) == "number" and t[2] == nil then
        return { kind = "num", entry = t, val = t[1] }
    end
    return nil
end

local function deepFind(t, depth)
    if type(t) ~= "table" or depth > 4 then return nil end
    local r = classifyEntry(t)
    if r then return r end
    local n = #t
    if n > 6 then n = 6 end
    for i = 1, n do
        local r2 = deepFind(t[i], depth + 1)
        if r2 then return r2 end
    end
    return nil
end

local function shapeOf(payload)
    if type(payload) ~= "table" then return nil end
    for k, v in pairs(payload) do
        if type(v) == "table" then
            local r = deepFind(v, 0)
            if r then r.key = k; return r end
        end
    end
    return nil
end

local function briefShape(payload, depth)
    depth = depth or 0
    if depth > 3 then return "…" end
    if type(payload) ~= "table" then return type(payload) end
    local parts = {}
    local cnt = 0
    for k, v in pairs(payload) do
        cnt = cnt + 1
        if cnt > 4 then table.insert(parts, "…"); break end
        local kk = type(k) == "string" and ('["' .. k .. '"]') or tostring(k)
        if type(v) == "table" then
            table.insert(parts, kk .. "=" .. briefShape(v, depth + 1))
        else
            table.insert(parts, kk .. "=" .. tostring(v):sub(1, 14))
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- ==================== key 记录 ====================
local function noteKeyValue(key, val)
    keySeen[key] = keySeen[key] or {}
    table.insert(keySeen[key], val)
    if not numKeyOrder[key] then
        numKeyOrder[key] = true
        table.insert(numKeyOrder, key)   -- 记录顺序（手动选择的循环用）
    end
    if val > 4 and not CounterKeys[key] then
        CounterKeys[key] = true
        addLine("排除 key [" .. tostring(key) .. "]：值 " .. tostring(val)
            .. " > 4，判定为回合计数器", true)
        if HitKey == key then
            HitKey = nil
            addLine("⚠ 命中上报 key 被推翻，重新学习", true)
        end
    end
end

-- ==================== 学习（带兜底） ====================
local function tryLearn(reason)
    if HitKey then return end
    -- 规则 1：本回合内、结算之前、最后一个数字包
    local last = turn.nums[#turn.nums]
    if last and not CounterKeys[last.key] then
        HitKey = last.key
        addLine(string.format("★ 学到命中上报 key=[%s]（本回合命中 %s，%s）→ 下次开始改写",
            tostring(HitKey), tostring(last.val), reason), true)
        task.spawn(function()
            pcall(notify, "QTE改写", "已学会 key [" .. tostring(HitKey) .. "]，下次开始改写")
        end)
        return
    end
    -- 规则 2：全局只有一个「值从没超过 4」的数字 key，那它就是命中上报
    local cands = {}
    for k, vals in pairs(keySeen) do
        if not CounterKeys[k] then
            local ok = true
            for _, v in ipairs(vals) do if v > 4 then ok = false break end end
            if ok then table.insert(cands, k) end
        end
    end
    if #cands == 1 then
        HitKey = cands[1]
        addLine(string.format("★ 兜底学到 key=[%s]（全局唯一候选，%s）→ 下次开始改写",
            tostring(HitKey), reason), true)
        task.spawn(function()
            pcall(notify, "QTE改写", "已学会 key [" .. tostring(HitKey) .. "]")
        end)
    end
end

local function closeTurn(reason)
    if not turn.active then return end
    tryLearn(reason)
    local last = turn.nums[#turn.nums]
    if last then stat.lastHit = tostring(last.val) end
    turn.active = false
end

-- ==================== 处理一个待发送的包 ====================
local function process(args)
    local payload = args[1]
    local info = shapeOf(payload)
    if not info then
        if Diagnose then
            addLine("未识别包 " .. briefShape(payload))
        end
        return false
    end

    if info.kind == "move" then
        stat.moves = stat.moves + 1
        stat.lastTotal = tostring(info.total)
        MoveKey = info.key
        if type(info.total) == "number" then lastTotalNum = info.total end
        turn.id = turn.id + 1
        local myId = turn.id
        turn = { id = myId, active = true, total = info.total, move = info.move, nums = {} }
        addLine(string.format("动作 #%d  %s  总点数=%s  请求key=[%s]",
            stat.moves, tostring(info.move), tostring(info.total), tostring(info.key)), true)
        -- 兜底：万一结算包一直没出现，12 秒后也强制结算学习一次
        task.delay(12, function()
            if turn.id == myId and turn.active then
                addLine("（12 秒没等到结算包，强制结算学习）", true)
                closeTurn("超时兜底")
            end
        end)
        return false

    elseif info.kind == "num" then
        stat.nums = stat.nums + 1
        noteKeyValue(info.key, info.val)
        if turn.active then
            table.insert(turn.nums, { key = info.key, val = info.val })
        end
        if Verbose then
            addLine(string.format("  数字包 key=[%s] 值=%s%s%s",
                tostring(info.key), tostring(info.val),
                turn.active and " (回合内)" or "",
                CounterKeys[info.key] and " (计数器)" or ""))
        end
        local k = effKey()
        if RewriteOn and RewriteMode ~= "off" and k and info.key == k
            and not CounterKeys[info.key] then
            local target
            if RewriteMode == "total" then
                target = (turn.active and turn.total) or lastTotalNum or 3
            else
                target = tonumber(RewriteMode) or 3
            end
            if type(target) ~= "number" then target = 3 end
            if type(info.val) == "number" and info.val < target then
                info.entry[1] = target          -- ★ 就地改写，形状不变
                stat.rewrites = stat.rewrites + 1
                stat.lastHit = tostring(target)
                addLine(string.format("★★ 改写命中数 %d → %d（第 %d 次）",
                    info.val, target, stat.rewrites), true)
                -- 通知放到新线程里（namecall 里不能 yield）
                task.spawn(function()
                    pcall(notify, "QTE改写", string.format("命中数 %d → %d", info.val, target))
                end)
                return true
            else
                stat.lastHit = tostring(info.val)
            end
        end
        return false

    elseif info.kind == "resolve" then
        stat.resolves = stat.resolves + 1
        -- 只有「我们自己的动作」结算才算本回合结束（敌人攻击不打断）
        local mine = (not turn.active) or turn.move == nil
            or info.move == turn.move or info.move == "BruhMiss"
        if Verbose then
            addLine("  结算包 Move=" .. tostring(info.move)
                .. (info.success and " [完美]" or "")
                .. (info.move == "BruhMiss" and " [打空]" or "")
                .. (mine and "" or " [敌人的]"))
        end
        if turn.active and mine then
            closeTurn("结算包到达")
        end
        return false
    end
    return false
end

-- ==================== Hook ====================
local hookOk, hookErr, hookMode = false, nil, "无"
local oldNamecall

local function hookBody(self, ...)
    stat.fireSeen = stat.fireSeen + 1
    local method
    pcall(function() method = getnamecallmethod() end)
    if method == "FireServer" then
        local args = { ... }
        if args[1] ~= nil then
            local ok, changed = pcall(process, args)
            if not ok then
                addLine("⚠ 处理包出错：" .. tostring(changed), true)
            elseif changed then
                return oldNamecall(self, table.unpack(args))
            end
        end
    end
    return oldNamecall(self, ...)
end

-- 方式 1：hookmetamethod（最稳）
if not hookOk and hookmetamethod and newcclosure then
    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(hookBody))
    end)
    if ok and oldNamecall then
        hookOk, hookMode = true, "hookmetamethod"
    else
        hookErr = err
    end
end
-- 方式 2：getrawmetatable
if not hookOk and getrawmetatable and setreadonly and newcclosure then
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(hookBody)
        setreadonly(mt, true)
    end)
    if ok and oldNamecall then
        hookOk, hookMode = true, "getrawmetatable"
    else
        hookErr = err
    end
end

-- ==================== 面板 ====================
local main, bubble, statusLabel, btnRewrite, btnMode, btnManual, btnDiag

local function buildGui()
    local parent = pg
    pcall(function() if gethui then parent = gethui() end end)

    local vp = Vector2.new(800, 400)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then vp = cam.ViewportSize end
    end)

    local panelW = math.floor(math.max(280, math.min(400, math.min(vp.X * 0.55, vp.X - 24))))
    local panelH = math.floor(math.max(230, math.min(360, math.min(vp.Y * 0.72, vp.Y - 56))))

    local titleH, statusH = 30, 62
    local COLS, ROWS, BTN_H, GAP = 4, 3, 32, 6
    local btnAreaH = ROWS * BTN_H + (ROWS - 1) * GAP
    local logTop = titleH + statusH + 6
    local logH = math.max(30, panelH - logTop - btnAreaH - 10)
    local btnW = math.floor((panelW - 12 - (COLS - 1) * GAP) / COLS)

    local errs = {}

    local gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9998
    gui.Parent = parent

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

    local linesFit = math.max(2, math.floor((logH - 6) / 14))
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
    end)

    btnMode = mkBtn("模式:满分", Color3.fromRGB(52, 62, 56), function()
        if RewriteMode == "total" then RewriteMode = "3"
        elseif RewriteMode == "3" then RewriteMode = "off"
        else RewriteMode = "total" end
        btnMode.Text = "模式:" .. (RewriteMode == "total" and "满分"
            or (RewriteMode == "3" and "固定3" or "不改"))
        addLine("改写模式：" .. btnMode.Text, true)
    end)

    btnManual = mkBtn("key:自动", Color3.fromRGB(90, 80, 50), function()
        -- 循环：自动 → 每个观察到的数字 key → 自动
        if #numKeyOrder == 0 then
            addLine("还没观察到任何数字包，先做一次动作", true)
            return
        end
        local cur = ManualKey
        local idx = 0
        if cur ~= nil then
            for i, k in ipairs(numKeyOrder) do if k == cur then idx = i end end
        end
        if idx >= #numKeyOrder then
            ManualKey = nil
        else
            ManualKey = numKeyOrder[idx + 1]
        end
        btnManual.Text = "key:" .. (ManualKey and ("[" .. tostring(ManualKey) .. "]") or "自动")
        addLine("手动指定命中key = " .. btnManual.Text, true)
    end)

    mkBtn("重新学习", Color3.fromRGB(90, 80, 50), function()
        HitKey, MoveKey, ManualKey = nil, nil, nil
        CounterKeys, keySeen, numKeyOrder = {}, {}, {}
        lastTotalNum = nil
        turn = { id = turn.id, active = false, total = nil, move = nil, nums = {} }
        if btnManual then btnManual.Text = "key:自动" end
        addLine("已清空学习结果，请再做一次动作", true)
        notify("QTE改写", "已重置学习")
    end)

    mkBtn("清空日志", Color3.fromRGB(70, 70, 60), function()
        showLines, allLines = {}, {}
        logDirty = true
    end)

    mkBtn("复制日志", Color3.fromRGB(46, 96, 130), function()
        local fn = setclipboard or toclipboard
        if fn then
            pcall(fn, table.concat(allLines, "\n"))
            addLine("已复制 " .. #allLines .. " 行", true)
            notify("QTE改写", "日志已复制")
        else
            notify("QTE改写", "没有 setclipboard")
        end
    end)

    mkBtn("导出文件", Color3.fromRGB(46, 110, 90), function()
        local name = "QTE改写日志_" .. tostring(os.date("%m%d_%H%M%S")) .. ".txt"
        local head = string.format(
            "执行器：%s\n版本：%s %s\nHook：%s (%s)\n学到 HitKey=%s  MoveKey=%s  手动=%s\n计数器=%s\n统计：拦包%d 动作%d 数字%d 结算%d 改写%d\n----\n",
            ExecName, VERSION, BUILD, hookOk and "已装" or "失败", hookMode,
            tostring(HitKey), tostring(MoveKey), tostring(ManualKey),
            (function()
                local t = {}
                for k in pairs(CounterKeys) do table.insert(t, tostring(k)) end
                return table.concat(t, ",")
            end)(),
            stat.fireSeen, stat.moves, stat.nums, stat.resolves, stat.rewrites)
        local fn = writefile or (syn and syn.writefile)
        if not fn then
            addLine("❌ 没有 writefile，请用「复制日志」", true)
            return
        end
        local ok, err = pcall(fn, name, head .. table.concat(allLines, "\n"))
        if ok then
            addLine("✅ 已导出：" .. name, true)
            local ok2, ws = pcall(function() return getworkspace and getworkspace() end)
            if ok2 and ws then addLine("   文件夹：" .. tostring(ws), true) end
            notify("QTE改写", "已导出 " .. name)
        else
            addLine("❌ 导出失败：" .. tostring(err), true)
        end
    end)

    btnDiag = mkBtn("诊断:关", Color3.fromRGB(52, 62, 56), function()
        Diagnose = not Diagnose
        btnDiag.Text = Diagnose and "诊断:开" or "诊断:关"
        addLine("诊断模式：" .. (Diagnose and "开（记录所有包）" or "关"), true)
    end)

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

    bubble = Instance.new("TextButton")
    bubble.Size = UDim2.new(0, 46, 0, 46)
    bubble.Position = UDim2.new(1, -60, 0, 180)
    bubble.BackgroundColor3 = Color3.fromRGB(40, 110, 66)
    bubble.BorderSizePixel = 0
    bubble.Text = "QTE"
    bubble.TextColor3 = Color3.fromRGB(240, 255, 245)
    bubble.TextScaled = true
    bubble.Visible = false
    bubble.Parent = gui
    do
        local last = 0
        local function fire()
            local now = os.clock()
            if now - last < 0.25 then return end
            last = now
            main.Visible = true
            bubble.Visible = false
        end
        pcall(function() bubble.Activated:Connect(fire) end)
        pcall(function() bubble.MouseButton1Click:Connect(fire) end)
    end

    -- 拖动
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
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    -- 刷新
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
                local counters = {}
                for k in pairs(CounterKeys) do table.insert(counters, tostring(k)) end
                pcall(function()
                    statusLabel.Text = string.format(
                        "改写:%s(%s)  Hook:%s 拦包%d  诊断:%s\n命中key:%s  总点数:%s  最近命中:%s\n动作%d 数字%d 结算%d ★改写%d  计数器[%s]",
                        RewriteOn and "开" or "关",
                        RewriteMode == "total" and "满分" or (RewriteMode == "3" and "固定3" or "不改"),
                        hookOk and hookMode or "失败",
                        stat.fireSeen, Diagnose and "开" or "关",
                        ManualKey and ("手动[" .. tostring(ManualKey) .. "]")
                            or (HitKey and ("[" .. tostring(HitKey) .. "]") or "学习中"),
                        tostring(stat.lastTotal), tostring(stat.lastHit),
                        stat.moves, stat.nums, stat.resolves, stat.rewrites,
                        table.concat(counters, ","))
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
if not okGui then print("[QTE改写] 面板创建失败：" .. tostring(guiErr)) end

if not hookOk then
    addLine("⚠ Hook 安装失败：" .. tostring(hookErr), true)
    addLine("   本脚本依赖 __namecall，没有 hook 就无法改写", true)
else
    addLine("Hook 已装（" .. hookMode .. "）", true)
end
addLine("====== QTE改写 " .. VERSION .. " (" .. BUILD .. ") 已启动 ======", true)
addLine("先用一次道具（中不中都行）→ 学会命中key → 第 2 次起自动满分", true)
notify("QTE改写已启动", "先用一次道具让它学习")
