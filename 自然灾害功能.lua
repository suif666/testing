-- 自然灾害 功能远程脚本 by suif
-- 远程脚本格式：由主脚本（Suture Hub）提供 getgenv().Tabs.ZRZHTab
-- 主脚本里现在只留一行 lazyLoad 链接，功能代码全在这个文件里
--
-- 本文件内容：
--   1. 苹果/气球刷（开关 + 倍率）—— 打游戏自己的 Event 远程，没有就退回点 ClickDetector
--   2. 主要功能：自动胜利1、在水上行走、岛边缘实体碰撞、防击退（防摔伤）
--   3. 传送：灾害岛、主塔
--   4. 道具功能：暂停游戏运行（需要指南针）
--
-- 坐标 / 对象名都是从实测能用的老脚本搬过来的；自然灾害改图的话传送落点会偏

if getgenv().__SUTURE_ZRZH_FUNC_LOADED then
    return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.ZRZHTab) or getgenv().SutureZRZHTab
if not Tab then
    warn("[自然灾害] 未找到 ZRZHTab，请检查主脚本是否赋值 getgenv().Tabs.ZRZHTab")
    return
end

-- 确认 Tab 拿到后才标记已加载（先标记的话，首次加载时 Tab 没就绪就永久废掉）
getgenv().__SUTURE_ZRZH_FUNC_LOADED = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local WindUI = getgenv().WindUI
local lp = Players.LocalPlayer

local function notify(title, content, icon, duration)
    if WindUI and WindUI.Notify then
        pcall(function()
            WindUI:Notify({
                Title = tostring(title or "自然灾害"),
                Content = tostring(content or ""),
                Icon = icon or "shell",
                Duration = duration or 3,
            })
        end)
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = tostring(title or "自然灾害"),
                Text = tostring(content or ""),
                Duration = duration or 3,
            })
        end)
    end
end

-- ==================== 自然灾害：苹果/气球刷（点击倍率） ====================
-- 原理：自然灾害把"点苹果 / 点气球"做成了远程 ReplicatedStorage.Event，
--       指令是 "ClickedApple" / "ClickedBalloon"。每帧多发几次就等于把点击速度放大几倍。
--       没有这个远程时，自动退回点道具上的 ClickDetector（BillboardApple / BillboardBalloon）。
-- 说明：这两个点击在游戏服务端的结算会把玩家装扮变成 noob（就是外面那个「让所有人变成NOOB」
--       脚本干的事，FE 所有人可见），所以"后面进来的玩家变 noob"是游戏行为，不是本地掉帧。
local NDS = { on = false, rate = 10, conn = nil }

local function ndsStop()
    NDS.on = false
    if NDS.conn then
        pcall(function() NDS.conn:Disconnect() end)
        NDS.conn = nil
    end
end

local function ndsStart()
    ndsStop()
    local RS = game:GetService("ReplicatedStorage")
    local rem = RS:FindFirstChild("Event")
    local detApple, detBalloon
    if not rem then
        for _, name in ipairs({ "BillboardApple", "BillboardBalloon" }) do
            local obj = workspace:FindFirstChild(name)
            local board = obj and obj:FindFirstChild("Board")
            local det = board and board:FindFirstChildOfClass("ClickDetector")
            if name == "BillboardApple" then
                detApple = det
            else
                detBalloon = det
            end
        end
        if not detApple and not detBalloon then
            notify("没找到目标", "ReplicatedStorage.Event 和 BillboardApple/BillboardBalloon 都不存在（可能不在自然灾害里）", "x", 5)
            return false
        end
    end

    NDS.on = true
    NDS.conn = RunService.Heartbeat:Connect(function()
        if not NDS.on then return end
        for _ = 1, NDS.rate do
            if rem then
                pcall(function()
                    rem:FireServer("ClickedApple")
                    rem:FireServer("ClickedBalloon")
                end)
            else
                if detApple and fireclickdetector then pcall(fireclickdetector, detApple) end
                if detBalloon and fireclickdetector then pcall(fireclickdetector, detBalloon) end
            end
        end
    end)
    return true
end

local ndsSec = Tab:Section({ Title = "苹果/气球刷", Icon = "apple", Opened = true })

ndsSec:Toggle({
    Title = "开启苹果/气球刷",
    Desc = "每帧按下面倍率发送点击（原版脚本 AttackRate=10 就是这里的倍率 10）",
    Icon = "zap",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        if s then
            if ndsStart() then
                notify("苹果/气球刷", "已开启，倍率 " .. tostring(NDS.rate), "check", 3)
            end
        else
            ndsStop()
            notify("苹果/气球刷", "已关闭", "info", 3)
        end
    end
})

ndsSec:Slider({
    Title = "倍率",
    Desc = "每帧发送次数（10 = 原版脚本强度，也就是每帧 20 次远程调用）",
    Step = 1,
    Value = { Min = 1, Max = 30, Default = 10 },
    Callback = function(v)
        NDS.rate = math.max(1, math.floor(tonumber(v) or 10))
    end
})

-- ==================== 自然灾害：主要功能 ====================
-- 以下坐标/对象名都是从 BS脚本 的自然灾害专区搬过来的（那边实测能用）
local NDS_CF = {
    win1   = CFrame.new(-236, 180, 360),
    win2   = CFrame.new(-280, 170, 341),
    tower  = CFrame.new(-280, 180, 341),
    island = CFrame.new(-83.5, 38.5, -27.5, -1, 0, 0, 0, 1, 0, 0, 0, -1),
    map    = CFrame.new(-115.828506, 65.4863434, 18.8461514,
        0.00697017973, 0.0789371505, -0.996855199,
        -3.13589936e-07, 0.996879458, 0.0789390653,
        0.999975681, -0.000549906865, 0.00694845384),
}

-- 通用：把角色传送到指定位置（没角色就提示，不再像原版那样直接报错）
local function ndsTeleport(cf, label, silent)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        notify("传送失败", "没有角色（先复活一次）", "x", 3)
        return false
    end
    local ok = pcall(function() root.CFrame = cf end)
    if not silent then
        notify(ok and "传送成功" or "传送失败", label or "已传送", ok and "check" or "x", 2)
    end
    return ok
end

local ndsMainSec = Tab:Section({ Title = "主要功能", Icon = "cloud-lightning", Opened = true })

-- 自动胜利1（原版把 while 循环直接写在回调里会卡住界面，这里改成开关 + 独立线程）
local ndsWinOn = { false, false }
local ndsWinThread = { nil, nil }
local function ndsWinSet(idx, on, cf, name)
    ndsWinOn[idx] = false
    if ndsWinThread[idx] then
        pcall(task.cancel, ndsWinThread[idx])
        ndsWinThread[idx] = nil
    end
    if not on then
        notify(name, "已关闭", "info", 2)
        return
    end
    if not ndsTeleport(cf, nil, true) then
        notify(name, "开启失败：没有角色", "x", 3)
        return
    end
    ndsWinOn[idx] = true
    ndsWinThread[idx] = task.spawn(function()
        while ndsWinOn[idx] do
            ndsTeleport(cf, nil, true)
            task.wait(0.1)
        end
    end)
    notify(name, "已开启（每 0.1 秒回胜利点）", "check", 2)
end

ndsMainSec:Toggle({
    Title = "自动胜利1",
    Desc = "持续传送到胜利位置1（原版写法会卡界面，这里改成开关）",
    Icon = "trophy",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        ndsWinSet(1, s, NDS_CF.win1, "自动胜利1")
    end
})

ndsMainSec:Toggle({
    Title = "在水上行走",
    Desc = "打开水面碰撞（把 WaterLevel 拉成 5000x1x5000），关掉恢复原样",
    Icon = "waves",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        local w = workspace:FindFirstChild("WaterLevel")
        if not w then
            notify("没找到水面", "workspace.WaterLevel 不存在（可能不在自然灾害里）", "x", 4)
            return
        end
        pcall(function()
            w.CanCollide = s
            w.Size = s and Vector3.new(5000, 1, 5000) or Vector3.new(10, 1, 10)
        end)
        notify("水上行走", s and "已开启" or "已关闭", "info", 2)
    end
})

ndsMainSec:Toggle({
    Title = "岛边缘实体碰撞",
    Desc = "打开 LowerRocks 的碰撞，掉到岛边缘不会直接滑下去",
    Icon = "mountain",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        local n = 0
        for _, v in ipairs(workspace:GetDescendants()) do
            if v.Name == "LowerRocks" then
                pcall(function() v.CanCollide = s end)
                n = n + 1
            end
        end
        if n == 0 then
            notify("没找到目标", "地图里没有 LowerRocks（可能不在自然灾害里）", "x", 4)
        else
            notify("岛边缘碰撞", (s and "已开启，" or "已关闭，") .. "处理了 " .. n .. " 个", "check", 2)
        end
    end
})

-- 防击退（防摔伤）：每帧抵消一次速度，防止被灾害击飞/摔伤（BS脚本 的原始机制）
local ndsKnockOn = false
local ndsKnockConns = {}
local ndsKnockCharConn = nil

local function ndsKnockAttach(char)
    local root = char:WaitForChild("HumanoidRootPart", 6)
    if not root then return end
    local conn = RunService.Heartbeat:Connect(function()
        if not ndsKnockOn then return end
        if not root or not root.Parent then return end
        local v = root.AssemblyLinearVelocity
        local av = root.AssemblyAngularVelocity
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        RunService.RenderStepped:Wait()
        if root.Parent then
            root.AssemblyLinearVelocity = v
            root.AssemblyAngularVelocity = av
        end
    end)
    ndsKnockConns[#ndsKnockConns + 1] = conn
end

local function ndsKnockStop()
    ndsKnockOn = false
    for _, c in ipairs(ndsKnockConns) do
        pcall(function() c:Disconnect() end)
    end
    ndsKnockConns = {}
    if ndsKnockCharConn then
        pcall(function() ndsKnockCharConn:Disconnect() end)
        ndsKnockCharConn = nil
    end
end

ndsMainSec:Toggle({
    Title = "防击退（防摔伤）",
    Desc = "每帧抵消一次速度：防止被灾害击飞、摔伤；会造成移动手感发飘，只在需要时开",
    Icon = "shield",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        ndsKnockStop()
        if not s then
            notify("防击退", "已关闭，物理恢复正常", "info", 2)
            return
        end
        ndsKnockOn = true
        local char = lp.Character
        if char then ndsKnockAttach(char) end
        ndsKnockCharConn = lp.CharacterAdded:Connect(function(c)
            if not ndsKnockOn then return end
            task.wait(0.3)
            if ndsKnockOn then ndsKnockAttach(c) end
        end)
        notify("防击退", "已开启", "check", 2)
    end
})

-- ==================== 自然灾害：传送 ====================
local ndsTpSec = Tab:Section({ Title = "传送", Icon = "map-pin", Opened = false })

ndsTpSec:Button({
    Title = "灾害岛",
    Desc = "传送到灾害岛（位置可能偏差）",
    Icon = "map-pin",
    Callback = function() ndsTeleport(NDS_CF.island, "已传送到灾害岛") end
})

ndsTpSec:Button({
    Title = "主塔",
    Desc = "传送到主塔位置",
    Icon = "map-pin",
    Callback = function() ndsTeleport(NDS_CF.tower, "已传送到主塔") end
})

-- ==================== 自然灾害：道具功能 ====================
local ndsItemSec = Tab:Section({ Title = "道具功能", Icon = "compass", Opened = false })

ndsItemSec:Button({
    Title = "暂停游戏运行（所有人可见）",
    Desc = "需要背包里有指南针；通过 Compass 远程投票让游戏卡住",
    Icon = "pause",
    Callback = function()
        task.spawn(function()
            local backpack = lp:FindFirstChild("Backpack")
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local compass = backpack and backpack:FindFirstChild("Compass")
            local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
            local r = remotes and remotes:FindFirstChild("Compass")
            if not (hum and compass and r) then
                notify("条件不足", "需要指南针：背包/角色/Compass远程缺一个", "x", 5)
                return
            end
            pcall(function() hum:EquipTool(compass) end)
            task.wait(0.15)
            pcall(function()
                r:FireServer("Vote Map", 3)
                r:FireServer("Vote Map", 4)
            end)
            task.wait(0.1)
            pcall(function() hum:UnequipTools() end)
            notify("已发送", "已通过指南针投票（暂停游戏）", "check", 3)
        end)
    end
})
