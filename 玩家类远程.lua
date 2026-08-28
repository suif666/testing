-- 玩家类 远程脚本（显示功能 + UI，依赖主脚本提供 PlayerTab）
-- 主脚本需设置：getgenv().Tabs.PlayerTab（或 getgenv().SuturePlayerTab）

if getgenv().__SUTURE_PLAYER_LOADED then
    return
end
getgenv().__SUTURE_PLAYER_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.PlayerTab) or getgenv().SuturePlayerTab
if not Tab then
    warn("[玩家类] 未找到 PlayerTab，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local function getHum()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- ============ 记录游戏初始值（脚本加载时读取，不覆盖游戏设定） ============
local origWalkSpeed = 16
local origJumpPower = 50
local origGravity = workspace.Gravity or 196.2
do
    local h = getHum()
    if h then
        origWalkSpeed = h.WalkSpeed
        origJumpPower = h.JumpPower
    end
    origGravity = workspace.Gravity or origGravity
end

-- ============ 移动速度 / 跳跃高度（默认不锁定！避免加载即干扰游戏移动导致漂移） ============
-- 只有用户在 UI 里拖动"移动速度/跳跃高度"滑块后才会开始锁定（AutoLock = true）
getgenv().SutureMoveCfg = getgenv().SutureMoveCfg or {}
if getgenv().SutureMoveCfg.WalkSpeed == nil then getgenv().SutureMoveCfg.WalkSpeed = origWalkSpeed end
if getgenv().SutureMoveCfg.JumpPower == nil then getgenv().SutureMoveCfg.JumpPower = origJumpPower end
if getgenv().SutureMoveCfg.AutoLock == nil then getgenv().SutureMoveCfg.AutoLock = false end

local MoveCfg = getgenv().SutureMoveCfg

local function applyMovementToHumanoid(h)
    if not h or not h.Parent then return end
    if MoveCfg.AutoLock then
        if h.WalkSpeed ~= MoveCfg.WalkSpeed then
            h.WalkSpeed = MoveCfg.WalkSpeed
        end
        if not h.UseJumpPower then
            h.UseJumpPower = true
        end
        if h.JumpPower ~= MoveCfg.JumpPower then
            h.JumpPower = MoveCfg.JumpPower
        end
        -- 跳跃高度过高时落地会摔死，自动挂隐形保护罩（只加不删，避免误删游戏自带的）
        if h.JumpPower > 120 and h.Parent then
            pcall(function()
                if not h.Parent:FindFirstChildOfClass("ForceField") then
                    local ff = Instance.new("ForceField")
                    ff.Visible = false
                    ff.Parent = h.Parent
                end
            end)
        end
    end
end

local function applyMovement()
    local h = getHum()
    if h then
        applyMovementToHumanoid(h)
    end
end

getgenv().SutureMoveToken = (getgenv().SutureMoveToken or 0) + 1
local MoveToken = getgenv().SutureMoveToken

-- 循环保留，但 AutoLock = false 时什么都不做（零干扰）
task.spawn(function()
    while getgenv().SutureMoveToken == MoveToken do
        applyMovement()
        task.wait(0.25)
    end
end)

lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        local h = char:WaitForChild("Humanoid", 8)
        if h then
            task.wait(0.2)
            applyMovementToHumanoid(h)
        end
    end)
end)

-- ============ 玩家增强配置 ============
local defaultPlayerExtra = {
    InfJump = false, Noclip = false,
    Spin = false, SpinSpeed = 16, Gravity = origGravity / 19.62, GravityLock = false,
    AirJumps = 0, NoFallDamage = false,
}
getgenv().SuturePlayerExtra = getgenv().SuturePlayerExtra or {}
for k, v in pairs(defaultPlayerExtra) do
    if getgenv().SuturePlayerExtra[k] == nil then
        getgenv().SuturePlayerExtra[k] = v
    end
end

local PlayerExtra = getgenv().SuturePlayerExtra

-- 旧版本存的是绝对重力值（如 196.2），转成新的档位
if (PlayerExtra.Gravity or 10) > 50 then
    PlayerExtra.Gravity = PlayerExtra.Gravity / 19.62
end

-- ============ 无限跳跃 / 空中跳跃次数 ============
local function isGrounded()
    local h = getHum()
    return h ~= nil and h.FloorMaterial ~= Enum.Material.Air
end

local airJumpsUsed = 0
local wasGrounded = true

UIS.JumpRequest:Connect(function()
    local h = getHum()
    local c = lp.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if not h or not root or h.Health <= 0 or h.SeatPart then return end

    local grounded = isGrounded()

    if grounded and not wasGrounded then
        airJumpsUsed = 0
    end
    wasGrounded = grounded

    if grounded then
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        airJumpsUsed = 0
        return
    end

    local allow = PlayerExtra.InfJump
        or (PlayerExtra.AirJumps > 0 and airJumpsUsed < PlayerExtra.AirJumps)
    if allow then
        if not PlayerExtra.InfJump then
            airJumpsUsed = airJumpsUsed + 1
        end
        pcall(function()
            local v = root.Velocity
            root.Velocity = Vector3.new(v.X, h.JumpPower, v.Z)
        end)
    end
end)

-- ============ 穿墙 ============
local function setCharacterCollide(collide)
    local c = lp.Character
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = collide
            end)
        end
    end
end

RunService.Stepped:Connect(function()
    if not PlayerExtra.Noclip then return end
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if not c or not h or not root then return end
    local moving = h.MoveDirection.Magnitude > 0.5
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = not moving
            end)
        end
    end
    -- 防止无碰撞时下沉穿地板摔死：移动中下落时把竖直速度清零
    if moving and root.Velocity.Y < 0 then
        local v = root.Velocity
        root.Velocity = Vector3.new(v.X, 0, v.Z)
    end
end)

-- ============ 修改重力（0~10，0=无重力，10=正常） ============
local function applyGravity()
    workspace.Gravity = PlayerExtra.Gravity * 19.62
end

task.spawn(function()
    while true do
        if PlayerExtra.GravityLock then
            pcall(applyGravity)
        end
        task.wait(0.5)
    end
end)

-- ============ 人物旋转 ============
RunService.Heartbeat:Connect(function(step)
    if PlayerExtra.Spin then
        local c = lp.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(PlayerExtra.SpinSpeed) * step, 0)
        end
    end
end)

-- ============ 无伤坠落（位移平滑方案：借鉴夜脚本方案2，兼容所有直接扣血游戏） ============
-- 原理：Heartbeat 每帧监测 Y 轴位移，下坠超过阈值时把下落速度限制到安全值，
--      避免高速落地触发坠落伤害。即使游戏不用 Humanoid.FallDamage 事件也能生效。
local noFallConn = nil
local function applyNoFallDamage(on)
    local char = lp.Character
    if not char then return end
    if on then
        -- 先断开旧连接（角色重生/切换角色后需重建）
        if noFallConn then
            pcall(function() noFallConn:Disconnect() end)
            noFallConn = nil
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local lastY = root.Position.Y
        noFallConn = game:GetService("RunService").Heartbeat:Connect(function()
            if not noFallConn then return end
            local c = lp.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not c or not r or r ~= root then return end  -- 角色已换
            if not c.Parent then return end

            local cur = r.Position
            -- 下坠超过阈值，把下落速度限制为 -10（安全落地速度，不触发坠落伤害）
            local fallDist = lastY - cur.Y
            if fallDist >= 12 then
                local vel = r.AssemblyLinearVelocity
                if vel.Y < -10 then
                    r.AssemblyLinearVelocity = Vector3.new(vel.X, -10, vel.Z)
                end
            end
            -- 上升时刷新安全高度参照
            if cur.Y > lastY then
                lastY = cur.Y
            end
        end)
    else
        if noFallConn then
            pcall(function() noFallConn:Disconnect() end)
            noFallConn = nil
        end
    end
end

-- 角色重生后自动补上开启中的无伤坠落
lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 8)
        local root = char:WaitForChild("HumanoidRootPart", 8)
        if hum and root then
            task.wait(0.2)
            if PlayerExtra.NoFallDamage then
                applyNoFallDamage(true)
            end
        end
    end)
end)

-- ============ UI（折叠分组） ============
local uiOk, uiErr = pcall(function()
    local moveSec = Tab:Section({ Title = "移动属性", Icon = "settings", Opened = true })

    local walkSpeedSlider = moveSec:Slider({
        Title = "移动速度",
        Desc = "修改并锁定 WalkSpeed，防止被游戏重置",
        Step = 1,
        Value = { Min = 1, Max = 100, Default = MoveCfg.WalkSpeed or origWalkSpeed },
        Callback = function(v)
            MoveCfg.WalkSpeed = tonumber(v) or 16
            MoveCfg.AutoLock = true   -- 用户主动调整后开始锁定
            applyMovement()
        end
    })

    local jumpPowerSlider = moveSec:Slider({
        Title = "跳跃高度",
        Desc = "修改并锁定 JumpPower，防止被游戏重置",
        Step = 1,
        Value = { Min = 1, Max = 200, Default = MoveCfg.JumpPower or origJumpPower },
        Callback = function(v)
            MoveCfg.JumpPower = tonumber(v) or 50
            MoveCfg.AutoLock = true   -- 用户主动调整后开始锁定
            applyMovement()
        end
    })

    local gravitySlider = moveSec:Slider({
        Title = "修改重力",
        Desc = "0 = 无重力，10 = 正常重力(196.2)，移动滑块后持续锁定",
        Step = 1,
        Value = { Min = 0, Max = 20, Default = math.floor(PlayerExtra.Gravity or 10) },
        Callback = function(v)
            PlayerExtra.Gravity = tonumber(v) or 10
            PlayerExtra.GravityLock = true
            pcall(applyGravity)
        end
    })

    moveSec:Toggle({
        Title = "穿墙（Noclip）",
        Desc = "移动时无视碰撞，停止移动恢复碰撞，关闭后全部恢复",
        Type = "Checkbox",
        Value = PlayerExtra.Noclip or false,
        Callback = function(s)
            PlayerExtra.Noclip = s
            if not s then
                setCharacterCollide(true)
            end
        end
    })

    moveSec:Button({
        Title = "恢复玩家初始属性",
        Desc = "恢复成脚本加载前游戏的速度、跳跃和重力",
        Callback = function()
            MoveCfg.WalkSpeed = origWalkSpeed
            MoveCfg.JumpPower = origJumpPower
            MoveCfg.AutoLock = false   -- 恢复初始后停止锁定，避免再次干扰
            PlayerExtra.GravityLock = false
            PlayerExtra.Gravity = origGravity / 19.62
            workspace.Gravity = origGravity
            applyMovement()
            pcall(function()
                walkSpeedSlider:Set(origWalkSpeed)
                jumpPowerSlider:Set(origJumpPower)
                gravitySlider:Set(math.floor(origGravity / 19.62))
            end)
        end
    })

    moveSec:Toggle({
        Title = "无限跳跃",
        Desc = "在空中可以连续跳跃，键盘和手机跳跃键都有效",
        Type = "Checkbox",
        Value = PlayerExtra.InfJump or false,
        Callback = function(s)
            PlayerExtra.InfJump = s
        end
    })

    moveSec:Slider({
        Title = "空中跳跃次数",
        Desc = "0 = 关闭；空中可额外跳跃的次数（无限跳跃开启时优先，不受此限制）",
        Step = 1,
        Value = { Min = 0, Max = 20, Default = PlayerExtra.AirJumps or 0 },
        Callback = function(v)
            PlayerExtra.AirJumps = tonumber(v) or 0
            airJumpsUsed = 0
        end
    })

    moveSec:Input({
        Title = "旋转速度",
        Desc = "自定义旋转速度，输入数字后生效",
        Placeholder = "默认 16",
        Callback = function(value)
            local n = tonumber(value)
            if n then
                PlayerExtra.SpinSpeed = n
            end
        end
    })

    moveSec:Toggle({
        Title = "人物旋转",
        Desc = "开启后角色持续旋转",
        Type = "Checkbox",
        Value = PlayerExtra.Spin or false,
        Callback = function(s)
            PlayerExtra.Spin = s
            local h = getHum()
            if h then
                h.AutoRotate = not s
            end
        end
    })

    moveSec:Toggle({
        Title = "无伤坠落",
        Desc = "下坠速度受限，避免坠落伤害（位移监测方案）",
        Type = "Checkbox",
        Value = PlayerExtra.NoFallDamage or false,
        Callback = function(s)
            PlayerExtra.NoFallDamage = s
            applyNoFallDamage(s)
        end
    })

    moveSec:Button({
        Title = "重置角色",
        Desc = "让自己的角色重生",
        Callback = function()
            local h = getHum()
            if h then
                h.Health = 0
            end
        end
    })
end)
