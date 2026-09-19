-- 玩家类 远程脚本（显示功能 + UI，依赖主脚本提供 PlayerTab）
-- 主脚本需设置：getgenv().Tabs.PlayerTab（或 getgenv().SuturePlayerTab）

if getgenv().__SUTURE_PLAYER_LOADED then
    return
end

local Tab = (getgenv().Tabs and getgenv().Tabs.PlayerTab) or getgenv().SuturePlayerTab
if not Tab then
    warn("[玩家类] 未找到 PlayerTab，请检查主脚本是否正确赋值")
    return
end

-- 确认 Tab 拿到后才标记已加载。
-- （原实现把标志位设在 Tab 检查之前：一旦首次加载时 Tab 未就绪，
--   就会永久标记为已加载，之后点 Tab 重新加载也会被直接 return，UI 再也建不出来）
getgenv().__SUTURE_PLAYER_LOADED = true

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
-- 本版改动（参考主流 hub 写法）：
--   1. 速度与跳跃【各自独立锁定】：拖"移动速度"不再顺带改动跳跃。
--      原实现是一个 AutoLock 同时管速度和跳跃，一拖速度就会强制 UseJumpPower=true
--      并覆盖 JumpPower —— 调速度等于顺手改了跳跃手感，这是"移动类功能不对劲"的主因。
--   2. 锁定方式改为 RunService.Heartbeat【每帧】检查（原为 0.25 秒轮询）。
--      游戏重置 WalkSpeed 后能在下一帧立刻压回去，不再出现"改了没效果 / 时快时慢"。
--   3. 两项都没锁定时 Heartbeat 里直接 return，零性能开销。
getgenv().SutureMoveCfg = getgenv().SutureMoveCfg or {}
local MoveCfg = getgenv().SutureMoveCfg
if MoveCfg.WalkSpeed == nil then MoveCfg.WalkSpeed = origWalkSpeed end
if MoveCfg.JumpPower == nil then MoveCfg.JumpPower = origJumpPower end
if MoveCfg.WalkLock == nil then MoveCfg.WalkLock = false end
if MoveCfg.JumpLock == nil then MoveCfg.JumpLock = false end
-- 兼容旧存档：旧字段 AutoLock 表示速度+跳跃一起锁
if MoveCfg.AutoLock == true then
    MoveCfg.WalkLock = true
    MoveCfg.JumpLock = true
end

-- 记录脚本自己加的隐形 ForceField（跳跃过高防摔死用），跳回安全值时要能移除
local ownForceField = nil

local function applyMovementToHumanoid(h)
    if not h or not h.Parent then return end

    -- 速度：只受 WalkLock 控制
    if MoveCfg.WalkLock then
        if h.WalkSpeed ~= MoveCfg.WalkSpeed then
            h.WalkSpeed = MoveCfg.WalkSpeed
        end
    end

    -- 跳跃：只受 JumpLock 控制（不再被速度滑块连带触发）
    if MoveCfg.JumpLock then
        -- 注意：不再【每帧】强制 UseJumpPower = true。
        -- 若游戏本身用 JumpHeight 模式（把 UseJumpPower 设回 false），
        -- 每帧抢改会形成属性拉锯，同样表现为人物上下抖动。
        -- 现在只在用户拖动跳跃滑块时切换一次（见 UI 回调）。
        if h.JumpPower ~= MoveCfg.JumpPower then
            h.JumpPower = MoveCfg.JumpPower
        end
        -- 跳跃高度过高时落地会摔死，自动挂隐形保护罩
        if MoveCfg.JumpPower > 120 then
            if not ownForceField or not ownForceField.Parent then
                pcall(function()
                    local ff = Instance.new("ForceField")
                    ff.Visible = false
                    ff.Parent = h.Parent
                    ownForceField = ff
                end)
            end
        elseif ownForceField and ownForceField.Parent then
            -- 跳跃调回安全值：移除脚本自己加的那个护罩，避免一直无敌
            pcall(function()
                ownForceField:Destroy()
            end)
            ownForceField = nil
        end
    end
end

local function applyMovement()
    local h = getHum()
    if h then
        applyMovementToHumanoid(h)
    end
end

-- 每帧锁定（原为 0.25 秒轮询，太慢，游戏一重置速度就会被拉回）
getgenv().SutureMoveToken = (getgenv().SutureMoveToken or 0) + 1
local MoveToken = getgenv().SutureMoveToken
if getgenv().SutureMoveConn then
    pcall(function() getgenv().SutureMoveConn:Disconnect() end)
end
local moveConn = RunService.Heartbeat:Connect(function()
    if getgenv().SutureMoveToken ~= MoveToken then
        pcall(function() moveConn:Disconnect() end)
        getgenv().SutureMoveConn = nil
        return
    end
    if not (MoveCfg.WalkLock or MoveCfg.JumpLock) then return end  -- 没锁定：直接跳过
    local h = getHum()
    if h then
        applyMovementToHumanoid(h)
    end
end)
getgenv().SutureMoveConn = moveConn

lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        local h = char:WaitForChild("Humanoid", 8)
        if h then
            task.wait(0.2)
            -- 重生后若跳跃锁定还开着，补一次模式切换（只切一次，不每帧抢改）
            if MoveCfg.JumpLock then
                pcall(function() h.UseJumpPower = true end)
            end
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

UIS.JumpRequest:Connect(function()
    -- 【重要】未开启无限跳跃/空中跳跃时，完全不介入。
    -- 原实现无条件执行，导致每次地面跳跃都会额外 ChangeState(Jumping) 一次，
    -- 与原生跳跃重复触发 —— 部分游戏（自定义角色控制器 / R15 特殊 rig）会表现为
    -- 人物上下抖动。其他脚本（Rb脚本中心、夜脚本源）都带这个开关判断。
    if not (PlayerExtra.InfJump or (PlayerExtra.AirJumps or 0) > 0) then return end

    local h = getHum()
    local c = lp.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if not h or not root or h.Health <= 0 or h.SeatPart then return end

    if isGrounded() then
        -- 地面跳跃交给原生 Humanoid 处理，脚本不插手（只重置空中跳跃计数）
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

-- 记录当前已应用的碰撞状态，避免每帧重复写属性
local noclipApplied = nil

RunService.Stepped:Connect(function()
    if not PlayerExtra.Noclip then
        noclipApplied = nil
        return
    end
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not c or not h then return end
    local moving = h.MoveDirection.Magnitude > 0.5
    -- 只在状态真正变化时切换碰撞（原来每帧都写一遍，
    -- 玩家移动时 MoveDirection 在阈值附近抖动会导致碰撞状态反复切换）
    if noclipApplied == moving then return end
    noclipApplied = moving
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = not moving
            end)
        end
    end
    -- 【已移除】原实现在移动中每帧把竖直速度清零（root.Velocity.Y = 0）。
    -- 那会与重力/地面吸附每帧对抗，表现为人物上下抖动 —— 主流写法
    -- （Rb脚本中心、夜脚本源）都不碰速度，只改 CanCollide。
end)

-- 角色重生后重置碰撞状态标记
lp.CharacterAdded:Connect(function()
    noclipApplied = nil
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

-- ============ 无伤坠落（从源头不产生摔落伤害，不补血） ============
-- 主流写法（BS-loves_you「防摔落机制」/ 夜脚本源 / Rb脚本中心）：
--   下坠全程保持原速，只有在【离地 6 格内】且【下坠速度低于 -50】的最后一瞬间，
--   才把竖直速度卸到 -20。游戏结算落地伤害时读到的冲击速度已经是安全值，
--   所以压根不会产生摔落伤害 —— 不是事后补血，也不是本地假血。
--   同时关掉 FallingDown 状态：摔落不会僵直倒地。
-- 【旧版为什么不满意】旧版是"下坠超过 12 格就把速度压到 -10"，整段下坠都被拖慢，
--   所以落地像飘下来一样。现在只在最后不到零点几秒卸力，下落手感跟原版一致。
local NOFALL_RAY = 6          -- 离地多少格内开始卸力
local NOFALL_DANGER = -50     -- 下坠速度低于这个值才算危险下坠
local NOFALL_SAFE = -20       -- 卸到的安全落地速度

local noFallConn = nil
local noFallHum = nil
local noFallRayParams = nil

local function noFallStop()
    if noFallConn then
        pcall(function() noFallConn:Disconnect() end)
        noFallConn = nil
    end
    if noFallHum then
        -- 关掉功能时把状态还原
        pcall(function()
            noFallHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
        noFallHum = nil
    end
end

local function noFallBuildParams(char)
    if not noFallRayParams then
        noFallRayParams = RaycastParams.new()
        pcall(function()
            noFallRayParams.FilterType = Enum.RaycastFilterType.Exclude
        end)
        if noFallRayParams.FilterType ~= Enum.RaycastFilterType.Exclude then
            -- 老版本枚举名兜底
            pcall(function()
                noFallRayParams.FilterType = Enum.RaycastFilterType.Blacklist
            end)
        end
        noFallRayParams.IgnoreWater = true
    end
    -- 排除自己（以及别的玩家，避免踩在别人头上提前刹车）
    local exclude = { char }
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            exclude[#exclude + 1] = p.Character
        end
    end
    noFallRayParams.FilterDescendantsInstances = exclude
end

local function applyNoFallDamage(on)
    -- 先断旧连接（角色重生/切换角色后要重建）
    noFallStop()
    if not on then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root then return end

    noFallHum = hum
    -- 摔落不僵直倒地
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    end)

    noFallBuildParams(char)

    local RS = game:GetService("RunService")
    noFallConn = RS.Heartbeat:Connect(function()
        local c = lp.Character
        if not c or c ~= char or not c.Parent then return end
        local h = c:FindFirstChildOfClass("Humanoid")
        local r = c:FindFirstChild("HumanoidRootPart")
        if not h or not r or h.Health <= 0 then return end

        local vel = r.AssemblyLinearVelocity
        if vel.Y > NOFALL_DANGER then return end        -- 下坠不够快：什么都不做（原速下落）

        -- 往下打一条 6 格的射线，看离地面还有多远
        local hit = workspace:Raycast(r.Position, Vector3.new(0, -NOFALL_RAY, 0), noFallRayParams)
        if not hit then return end                      -- 还高：继续保持原速

        -- 快落地了：把冲击速度卸掉（游戏结算到的就是这个速度，所以不产生摔落伤害）
        r.AssemblyLinearVelocity = Vector3.new(vel.X, NOFALL_SAFE, vel.Z)
    end)
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

-- 加载时如果上次是开着的，直接补上
-- （原来只有"重生"才会补，导致开关显示是 ON、功能却没在跑）
if PlayerExtra.NoFallDamage then
    task.spawn(function()
        local char = lp.Character or lp.CharacterAdded:Wait()
        char:WaitForChild("Humanoid", 8)
        char:WaitForChild("HumanoidRootPart", 8)
        task.wait(0.2)
        if PlayerExtra.NoFallDamage then
            applyNoFallDamage(true)
        end
    end)
end

-- ============ UI（折叠分组） ============
local uiOk, uiErr = pcall(function()
    local moveSec = Tab:Section({ Title = "移动属性", Icon = "settings", Opened = true })

    local walkSpeedSlider = moveSec:Slider({
        Title = "移动速度",
        Desc = "修改并锁定 WalkSpeed，防止被游戏重置（不影响跳跃）",
        Step = 1,
        Value = { Min = 1, Max = 100, Default = MoveCfg.WalkSpeed or origWalkSpeed },
        Callback = function(v)
            MoveCfg.WalkSpeed = tonumber(v) or 16
            MoveCfg.WalkLock = true   -- 只锁速度，不动跳跃
            applyMovement()
        end
    })

    local jumpPowerSlider = moveSec:Slider({
        Title = "跳跃高度",
        Desc = "修改并锁定 JumpPower，防止被游戏重置（不影响速度）",
        Step = 1,
        Value = { Min = 1, Max = 200, Default = MoveCfg.JumpPower or origJumpPower },
        Callback = function(v)
            MoveCfg.JumpPower = tonumber(v) or 50
            MoveCfg.JumpLock = true   -- 只锁跳跃，不动速度
            -- 切到 JumpPower 模式（只切这一次，之后不再每帧抢改，避免与游戏拉锯抖动）
            local h = getHum()
            if h then
                pcall(function() h.UseJumpPower = true end)
            end
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
            MoveCfg.WalkLock = false   -- 恢复初始后停止锁定，避免再次干扰
            MoveCfg.JumpLock = false
            PlayerExtra.GravityLock = false
            PlayerExtra.Gravity = origGravity / 19.62
            workspace.Gravity = origGravity
            -- 直接写回角色：锁定已关闭，applyMovement 此时不会做任何事，
            -- 必须手动恢复一次，否则速度/跳跃还停在改过的值上
            local h = getHum()
            if h then
                pcall(function()
                    h.WalkSpeed = origWalkSpeed
                    h.JumpPower = origJumpPower
                end)
            end
            -- 移除脚本加的隐形护罩（跳回安全值不该继续无敌）
            if ownForceField and ownForceField.Parent then
                pcall(function() ownForceField:Destroy() end)
            end
            ownForceField = nil
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
        Desc = "下坠全程原速，离地 6 格内卸掉冲击速度 → 从源头不产生摔落伤害（不补血）",
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

-- UI 创建失败时给出提示（原来 uiOk/uiErr 声明了却没检查，UI 挂了是完全静默的）
if not uiOk then
    warn("[玩家类] UI 创建失败：" .. tostring(uiErr))
end
