-- 拦截布娃娃状态（WindUI 独立版）
-- 开启后：角色一旦进入布娃娃（Ragdoll）状态立即强制取消，
-- 并自动重建被拆断的关节（Motor6D / Weld / WeldConstraint / 各种 Constraint）

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
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local blockActive = false
local jointsSnapshot = {}

local JOINT_CLASSES = {
    "Motor6D", "Weld", "WeldConstraint",
    "BallSocketConstraint", "HingeConstraint", "CylindricalConstraint",
    "PrismaticConstraint", "RigidConstraint",
}

local function getHum()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- 快照角色关节配置，布娃娃把关节拆掉后可以照着重建
local function snapshotJoints(model)
    jointsSnapshot = {}
    if not model then return end
    for _, joint in ipairs(model:GetDescendants()) do
        local found = false
        for _, cls in ipairs(JOINT_CLASSES) do
            if joint.ClassName == cls then
                found = true
                break
            end
        end
        if found then
            local data = {
                Class = joint.ClassName,
                Name = joint.Name,
                Parent = joint.Parent,
            }
            if joint:IsA("Motor6D") or joint:IsA("Weld") then
                data.Part0 = joint.Part0
                data.Part1 = joint.Part1
                data.C0 = joint.C0
                data.C1 = joint.C1
            elseif joint:IsA("WeldConstraint") then
                data.Part0 = joint.Part0
                data.Part1 = joint.Part1
            elseif joint:IsA("Constraint") then
                data.Attachment0 = joint.Attachment0
                data.Attachment1 = joint.Attachment1
            end
            jointsSnapshot[#jointsSnapshot + 1] = data
        end
    end
end

-- 重建被拆断的关节
local function restoreJoints(model)
    if not model then return end
    for _, data in ipairs(jointsSnapshot) do
        local parent = data.Part0 or data.Parent
        if parent and parent.Parent == model and not parent:FindFirstChild(data.Name) then
            pcall(function()
                local j
                if data.Class == "Motor6D" or data.Class == "Weld" then
                    j = Instance.new(data.Class)
                    j.Part0 = data.Part0
                    j.Part1 = data.Part1
                    j.C0 = data.C0
                    j.C1 = data.C1
                elseif data.Class == "WeldConstraint" then
                    j = Instance.new("WeldConstraint")
                    j.Part0 = data.Part0
                    j.Part1 = data.Part1
                elseif data.Attachment0 and data.Attachment1
                    and data.Attachment0.Parent and data.Attachment1.Parent then
                    j = Instance.new(data.Class)
                    j.Attachment0 = data.Attachment0
                    j.Attachment1 = data.Attachment1
                end
                if j then
                    j.Name = data.Name
                    j.Parent = parent
                end
            end)
        end
    end
end

-- 判断是否处于布娃娃：状态机 Ragdoll 或 R6 的 Ragdolled 属性
local function isRagdolled(h)
    if not h then return false end
    local ok, state = pcall(function()
        return h:GetState()
    end)
    if ok and state == Enum.HumanoidStateType.Ragdoll then return true end
    local ok2, rag = pcall(function()
        return h.Ragdolled
    end)
    if ok2 and rag then return true end
    return false
end

-- 强制取消布娃娃：退出状态 + 恢复物理 + 禁用布娃娃状态防止立刻再触发
local function forceStand(h)
    if not h then return end
    pcall(function()
        h:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
    pcall(function()
        h:ChangeState(Enum.HumanoidStateType.Running)
    end)
    pcall(function()
        h.Ragdolled = false
    end)
    pcall(function()
        h.PlatformStand = false
    end)
    pcall(function()
        h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end)
    -- 身体部件解除锚定，防止被游戏锁死
    local c = lp.Character
    if c then
        for _, part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function()
                    part.Anchored = false
                end)
            end
        end
    end
end

-- 恢复布娃娃状态许可（关闭拦截时调用）
local function allowRagdoll(h)
    if not h then return end
    pcall(function()
        h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end)
end

-- 状态监听：进入布娃娃的瞬间同步打断，不等下一帧
local function hookHumanoid(h)
    if not h or h:GetAttribute("SutureRagdollHooked") then return end
    h:SetAttribute("SutureRagdollHooked", true)
    h.StateChanged:Connect(function(oldState, newState)
        if blockActive and newState == Enum.HumanoidStateType.Ragdoll then
            forceStand(h)
            restoreJoints(lp.Character)
        end
    end)
end

-- 角色出生时：快照关节 + 挂状态监听
local function onCharacterAdded(char)
    task.spawn(function()
        local h = char:WaitForChild("Humanoid", 8)
        if h then
            task.wait(0.5)
            snapshotJoints(char)
            hookHumanoid(h)
        end
    end)
end

if lp.Character then task.spawn(onCharacterAdded, lp.Character) end
lp.CharacterAdded:Connect(onCharacterAdded)

-- 每帧兜底：状态机/Ragdolled 属性 + 关节缺失，任何漏网场景都能立刻处理
RunService.Heartbeat:Connect(function()
    if not blockActive then return end
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h then
        if isRagdolled(h) then
            forceStand(h)
        end
    end
end)

-- 关节修复循环（比每帧便宜一点，持续补关节 + 重申禁用布娃娃状态）
task.spawn(function()
    while true do
        task.wait(0.05)
        if blockActive then
            restoreJoints(lp.Character)
            local h = getHum()
            if h then
                pcall(function()
                    h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                end)
            end
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
                pcall(function()
                    h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                end)
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
    Desc = "状态机 + Ragdolled 属性 + 关节重建三重拦截，角色重生后自动重新生效",
})

tab:Select()
WindUI:Notify({ Title = "拦截布娃娃", Content = "加载完成", Icon = "user", Duration = 3 })
