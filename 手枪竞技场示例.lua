-- 手枪竞技场 Ragebot（WindUI 独立版）
-- 移植自 XIAOXI付费版，只保留核心：自动锁定最近目标 + 子弹追踪 + 伤害直注
-- 用法：在手枪竞技场游戏里直接执行本脚本

if getgenv().__SUTURE_FFA_RAGEBOT_LOADED then
    return
end
getgenv().__SUTURE_FFA_RAGEBOT_LOADED = true

-- ==================== WindUI 加载 ====================
local WindUI
local ok, res = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok then
    warn("[Ragebot] WindUI 加载失败:", res)
    return
end
WindUI = res

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==================== 设置 ====================
local ragebotEnabled = false
local lastShotTime = 0
local connection = nil
local fireRateValue = 1          -- 射击间隔（秒/发）
local wallCheckEnabled = true    -- 默认开启墙壁检测
local headshotEnabled = true     -- 默认强制爆头

-- ==================== 远程事件获取 ====================
local function getDamageRemote()
    local systemResources = ReplicatedStorage:FindFirstChild("SystemResources")
    if not systemResources then return nil end
    local bufferCache = systemResources:FindFirstChild("BufferCache")
    if not bufferCache then return nil end
    return bufferCache:FindFirstChild("RequestActionSync")
end

local function getFakeBulletRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then return nil end
    local remoteEvents = events:FindFirstChild("RemoteEvents")
    if not remoteEvents then return nil end
    return remoteEvents:FindFirstChild("ReplicateFakeBullet")
end

local function getMuzzleFlashRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then return nil end
    local remoteEvents = events:FindFirstChild("RemoteEvents")
    if not remoteEvents then return nil end
    return remoteEvents:FindFirstChild("CharacterMuzzleFlash")
end

-- ==================== 墙壁检测 ====================
local function checkWallBetween(origin, targetPos, targetCharacter)
    if not wallCheckEnabled then
        return false
    end
    local direction = (targetPos - origin).Unit
    local distance = (targetPos - origin).Magnitude

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character, targetCharacter }
    rayParams.IgnoreWater = true

    local ray = Workspace:Raycast(origin, direction * distance, rayParams)
    if ray then
        local hitInstance = ray.Instance
        if hitInstance:IsDescendantOf(targetCharacter) then
            return false
        end
        if hitInstance.Transparency >= 0.9 then
            return false
        end
        return true
    end
    return false
end

-- ==================== 工具 ====================
local function isDead(player)
    if not player or not player.Character then return true end
    local humanoid = player.Character:FindFirstChild("Humanoid")
    return not humanoid or humanoid.Health <= 0
end

local function playShootSound()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6534948092"
    sound.Volume = 0.5
    sound.Parent = Camera
    sound.PlayOnRemove = true
    sound:Destroy()
end

local function createBeam(startPos, endPos)
    local part1 = Instance.new("Part")
    part1.Anchored = true
    part1.CanCollide = false
    part1.Transparency = 1
    part1.Size = Vector3.new(0.1, 0.1, 0.1)
    part1.Position = startPos
    part1.Parent = Workspace

    local part2 = Instance.new("Part")
    part2.Anchored = true
    part2.CanCollide = false
    part2.Transparency = 1
    part2.Size = Vector3.new(0.1, 0.1, 0.1)
    part2.Position = endPos
    part2.Parent = Workspace

    local attachment1 = Instance.new("Attachment")
    attachment1.Parent = part1
    local attachment2 = Instance.new("Attachment")
    attachment2.Parent = part2

    local beam1 = Instance.new("Beam")
    beam1.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
    beam1.Transparency = NumberSequence.new(0)
    beam1.Width0 = 0.25
    beam1.Width1 = 0.25
    beam1.Texture = "rbxassetid://7136858729"
    beam1.TextureSpeed = 0.8
    beam1.TextureMode = Enum.TextureMode.Wrap
    beam1.Brightness = 1
    beam1.LightEmission = 0
    beam1.FaceCamera = true
    beam1.Attachment0 = attachment1
    beam1.Attachment1 = attachment2
    beam1.Parent = part1

    local beam2 = Instance.new("Beam")
    beam2.Color = ColorSequence.new(Color3.fromRGB(180, 200, 255))
    beam2.Transparency = NumberSequence.new(0.4)
    beam2.Width0 = 0.12
    beam2.Width1 = 0.12
    beam2.Texture = "rbxassetid://7136858729"
    beam2.TextureSpeed = 1.2
    beam2.TextureMode = Enum.TextureMode.Wrap
    beam2.Brightness = 1.2
    beam2.LightEmission = 0.6
    beam2.FaceCamera = true
    beam2.Attachment0 = attachment1
    beam2.Attachment1 = attachment2
    beam2.Parent = part1

    local shaking = true
    task.spawn(function()
        while shaking and part1 and part1.Parent do
            attachment1.Position = Vector3.new(math.random(-3, 3) / 100, math.random(-3, 3) / 100, math.random(-3, 3) / 100)
            attachment2.Position = Vector3.new(math.random(-3, 3) / 100, math.random(-3, 3) / 100, math.random(-3, 3) / 100)
            task.wait(0.02)
        end
    end)

    task.delay(math.random(10, 40) / 10, function()
        shaking = false
        for i = 0, 1, 0.05 do
            if not part1 or not part1.Parent then break end
            beam1.Transparency = NumberSequence.new(i)
            beam2.Transparency = NumberSequence.new(0.4 + i * 0.6)
            task.wait(0.03)
        end
        pcall(function() part1:Destroy() end)
        pcall(function() part2:Destroy() end)
    end)
end

-- ==================== 目标获取 ====================
local function getAvailableTargets()
    local targets = {}
    local character = LocalPlayer.Character
    if not character then return targets end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return targets end

    local myPosition = humanoidRootPart.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not isDead(player) and player.Character then
            local targetChar = player.Character
            local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

            if targetRoot then
                local targetPart = targetRoot
                local targetPos = targetRoot.Position

                if headshotEnabled then
                    local head = targetChar:FindFirstChild("Head")
                    if head then
                        targetPart = head
                        targetPos = head.Position
                    end
                end

                local hasWall = checkWallBetween(myPosition, targetPos, targetChar)
                if not hasWall then
                    table.insert(targets, {
                        player = player,
                        character = targetChar,
                        part = targetPart,
                        position = targetPos,
                        distance = (targetPos - myPosition).Magnitude
                    })
                end
            end
        end
    end

    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- ==================== 射击 ====================
local function shootTarget(target)
    local currentTime = tick()
    if currentTime - lastShotTime < fireRateValue then
        return false
    end

    local character = LocalPlayer.Character
    if not character then return false end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end

    local origin = humanoidRootPart.Position
    local targetPart = target.part
    local targetPos = target.position
    local targetChar = target.character

    if not targetPart or not targetChar then return false end

    local direction = (targetPos - origin).Unit
    local cframe = CFrame.lookAt(origin, targetPos)

    pcall(function()
        local fakeBullet = getFakeBulletRemote()
        if fakeBullet then
            fakeBullet:FireServer(cframe, direction)
        end
    end)

    pcall(function()
        local muzzleFlash = getMuzzleFlashRemote()
        if muzzleFlash then
            muzzleFlash:FireServer()
        end
    end)

    pcall(function()
        local humanoid = targetChar:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health > 0 then
            local args = {
                {
                    direction = direction,
                    hitPosition = targetPos,
                    origin = origin,
                    hitInstance = targetPart,
                    hitHumanoid = humanoid,
                    IsHeadshot = (targetPart.Name == "Head")
                }
            }
            local damageRemote = getDamageRemote()
            if damageRemote then
                damageRemote:FireServer(unpack(args))
            end
        end
    end)

    createBeam(origin, targetPos)
    playShootSound()

    lastShotTime = currentTime
    return true
end

-- ==================== 旧连接清理（重复执行不冲突） ====================
if getgenv().ffaRagebotConnection then
    pcall(function() getgenv().ffaRagebotConnection:Disconnect() end)
    getgenv().ffaRagebotConnection = nil
end

-- ==================== 窗口 ====================
local win = WindUI:CreateWindow({
    Title = "手枪竞技场 Ragebot",
    Icon = "crosshair",
    Author = "WindUI 移植版",
    Folder = "FFARagebot",
    Size = UDim2.fromOffset(520, 400),
    MinSize = Vector2.new(440, 300),
    MaxSize = Vector2.new(760, 520),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 150,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    NewElements = true,
    User = { Enabled = false }
})

local tab = win:Tab({ Title = "Ragebot", Icon = "crosshair", Locked = false })
local sec = tab:Section({ Title = "自动锁定 + 子弹追踪", Icon = "settings", Opened = true })

tab:Paragraph({
    Title = "说明",
    Desc = "自动锁定最近敌人，模拟开枪并直注伤害\n射速慢一点更安全（默认 1 秒/发）"
})

tab:Toggle({
    Title = "启用 Ragebot",
    Desc = "开启后自动瞄准并射击最近目标",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        ragebotEnabled = state
        if connection then
            connection:Disconnect()
            connection = nil
        end
        if state then
            connection = RunService.Heartbeat:Connect(function()
                if not ragebotEnabled then return end
                pcall(function()
                    local targets = getAvailableTargets()
                    if #targets > 0 then
                        shootTarget(targets[1])
                    end
                end)
            end)
        end
    end
})

tab:Slider({
    Title = "射击间隔 (秒/发)",
    Desc = "越小射得越快，越容易被检测",
    Step = 0.1,
    Value = { Min = 0.2, Max = 2, Default = 1 },
    Callback = function(v)
        fireRateValue = v
    end
})

tab:Toggle({
    Title = "强制爆头",
    Desc = "只瞄准头部",
    Type = "Checkbox",
    Value = true,
    Callback = function(state)
        headshotEnabled = state
    end
})

tab:Toggle({
    Title = "无视墙壁",
    Desc = "关闭墙壁检测（穿墙打人，更容易被检测）",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        wallCheckEnabled = not state
    end
})

print("[Ragebot] 手枪竞技场 Ragebot 已加载")
warn("[Ragebot] 检测到此服务器手枪竞技场")
