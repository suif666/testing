-- 拦截布娃娃状态（WindUI 独立版）
-- 开启后：角色一旦进入布娃娃（Ragdoll）状态立即强制取消，
-- 并自动重建被拆断的 Motor6D 关节（很多布娃娃效果是拆关节实现的）

local WindUI
do
    local ok, res = pcall(function()
        local source = game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
        local fn, compileErr = loadstring(source)
        if not fn then
            error(compileErr)
        end
        return fn()
    end)

    if not ok or not res then
        warn("WindUI 加载失败，脚本已停止:", res)
        return
    end
    WindUI = res
end

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local blockActive = false
local jointsSnapshot = {}

local function getHum()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- 快照角色关节配置，布娃娃把关节拆掉后可以照着重建
local function snapshotJoints(model)
    jointsSnapshot = {}
    if not model then return end
    for _, joint in ipairs(model:GetDescendants()) do
        if joint:IsA("Motor6D") then
            jointsSnapshot[#jointsSnapshot + 1] = {
                Name = joint.Name,
                Part0 = joint.Part0,
                Part1 = joint.Part1,
                C0 = joint.C0,
                C1 = joint.C1,
            }
        end
    end
end

-- 重建被拆断的关节
local function restoreJoints(model)
    if not model then return end
    for _, data in ipairs(jointsSnapshot) do
        local p0, p1 = data.Part0, data.Part1
        if p0 and p1 and p0.Parent == model and p1.Parent == model then
            if not p0:FindFirstChild(data.Name) then
                local m = Instance.new("Motor6D")
                m.Name = data.Name
                m.Part0 = p0
                m.Part1 = p1
                m.C0 = data.C0
                m.C1 = data.C1
                m.Parent = p0
            end
        end
    end
end

local function isRagdolled(h)
    if not h then return false end
    local ok, state = pcall(function()
        return h:GetState()
    end)
    return ok and state == Enum.HumanoidStateType.Ragdoll
end

-- 强制取消布娃娃：退出状态、恢复站立、禁用布娃娃状态防止立刻再触发
local function forceStand(h)
    if not h then return end
    pcall(function()
        h:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
    pcall(function()
        h.PlatformStand = false
    end)
    pcall(function()
        h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end)
end

-- 恢复布娃娃状态许可（关闭拦截时调用）
local function allowRagdoll(h)
    if not h then return end
    pcall(function()
        h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end)
end

-- 状态监听：进入布娃娃的瞬间就打断（响应比轮询快）
local function hookHumanoid(h)
    if not h or h:GetAttribute("SutureRagdollHooked") then return end
    h:SetAttribute("SutureRagdollHooked", true)
    h.StateChanged:Connect(function(oldState, newState)
        if blockActive and newState == Enum.HumanoidStateType.Ragdoll then
            task.spawn(function()
                task.wait(0.02)
                forceStand(h)
                restoreJoints(lp.Character)
            end)
        end
    end)
end

-- 角色出生时：快照关节 + 挂状态监听
local function onCharacterAdded(char)
    task.spawn(function()
        local h = char:WaitForChild("Humanoid", 8)
        if h then
            task.wait(0.3)
            snapshotJoints(char)
            hookHumanoid(h)
        end
    end)
end

if lp.Character then task.spawn(onCharacterAdded, lp.Character) end
lp.CharacterAdded:Connect(onCharacterAdded)

-- 主循环：轮询兜底（状态监听可能漏掉的场景）+ 关节修复
task.spawn(function()
    while true do
        task.wait(0.1)
        if not blockActive then
            task.wait(0.3)
            continue
        end
        local c = lp.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if h then
            if isRagdolled(h) then
                forceStand(h)
            end
            restoreJoints(c)
        end
    end
end)

-- ============================================
-- WINDUI 界面
-- ============================================

local win = WindUI:CreateWindow({
    Title = "拦截布娃娃",
    Icon = "user",
    Author = "Suture",
    Folder = "RagdollBlocker",
    Size = UDim2.fromOffset(400, 300),
    MinSize = Vector2.new(340, 240),
    Resizable = true,
    Theme = "Dark",
    SideBarWidth = 140,
})

local sec = win:Section({ Title = "功能", Icon = "folder", Opened = true })
local tab = sec:Tab({ Title = "拦截", Icon = "shield" })

tab:Toggle({
    Title = "拦截布娃娃状态",
    Desc = "开启后角色一旦进入布娃娃立即强制取消并修复关节",
    Value = false,
    Callback = function(v)
        blockActive = v
        local h = getHum()
        if v then
            if h then
                forceStand(h)
            end
            snapshotJoints(lp.Character)
        else
            allowRagdoll(h)
        end
    end,
})

tab:Button({
    Title = "立即强制站立",
    Desc = "手动触发一次站立（开关未开启时也有效）",
    Callback = function()
        local h = getHum()
        if h then
            forceStand(h)
            restoreJoints(lp.Character)
        end
    end,
})

tab:Paragraph({
    Title = "说明",
    Desc = "支持状态拦截 + 关节重建，角色重生后自动重新生效",
})

tab:Select()
WindUI:Notify({ Title = "拦截布娃娃", Content = "加载完成", Icon = "user", Duration = 3 })
