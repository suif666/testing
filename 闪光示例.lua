-- 闪光 Ragebot（远程脚本格式，挂主脚本"闪光" Tab）
-- 主脚本需设置：getgenv().Tabs.SGTab（或 getgenv().SutureSGTab）

if getgenv().__SUTURE_FLASH_RAGEBOT_LOADED then
    return
end
getgenv().__SUTURE_FLASH_RAGEBOT_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.SGTab) or getgenv().SutureSGTab
if not Tab then
    warn("[闪光Ragebot] 未找到 Tab，请检查主脚本赋值")
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==================== 设置 ====================
local ragebotEnabled = false
local currentTarget = nil
local lastShotTime = 0
local connection = nil
local fireRateValue = 0.56        -- 射击间隔（秒/发，原版固定 0.56）
local useAimbotFov = true         -- 适配主脚本自瞄类 FOV 圈（选项）

-- ==================== 视野判断（只打屏幕内能看到的目标） ====================
local VIEW_MARGIN = 50
local function isInView(targetPos)
    local cam = Camera
    if not cam then return true end
    local screenPos, onScreen = cam:WorldToScreenPoint(targetPos)
    if not onScreen then return false end
    local vp = cam.ViewportSize
    if screenPos.X < -VIEW_MARGIN or screenPos.X > vp.X + VIEW_MARGIN
        or screenPos.Y < -VIEW_MARGIN or screenPos.Y > vp.Y + VIEW_MARGIN then
        return false
    end
    -- 适配主脚本自瞄类的 FOV 圈：圈外目标不打
    if useAimbotFov then
        local aim = getgenv().SutureAimbot
        if aim and aim.Fov and aim.Fov > 0 then
            local center = vp / 2
            local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
            if screenDist > aim.Fov then
                return false
            end
        end
    end
    return true
end

-- ==================== 工具 ====================
local function getVisiblePart(targetCharacter)
    if not targetCharacter or not LocalPlayer.Character then return nil end
    local localCharacter = LocalPlayer.Character
    local humanoidRootPart = localCharacter:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return nil end
    local partNames = { "Head", "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart" }
    local bestPart, bestPosition, bestOrigin = nil, nil, nil
    local minDistance = math.huge
    for _, partName in ipairs(partNames) do
        local part = targetCharacter:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            local targetPosition = part.Position
            for height = 0, 10.5, 2 do
                local startPos = humanoidRootPart.Position + Vector3.new(0, height, 0)
                local direction = (targetPosition - startPos).Unit
                local forwardPos = startPos + direction * 2.5
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = { localCharacter, Camera }
                rayParams.IgnoreWater = true
                local ray = Workspace:Raycast(forwardPos, targetPosition - forwardPos, rayParams)
                if not ray or ray.Instance:IsDescendantOf(targetCharacter) or ray.Instance.Transparency >= 0.9 then
                    local distance = (targetPosition - forwardPos).Magnitude
                    if distance < minDistance then
                        minDistance = distance
                        bestPart = part
                        bestPosition = targetPosition
                        bestOrigin = forwardPos
                    end
                end
            end
        end
    end
    return bestPart, bestPosition, bestOrigin
end

local function isDead(player)
    if not player or not player.Character then return true end
    local humanoid = player.Character:FindFirstChild("Humanoid")
    return not humanoid or humanoid.Health <= 0
end

local function playShootSound()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6534948092"
    sound.Volume = 1
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

-- ==================== 射击（子弹追踪直注） ====================
local function shoot(player, targetPart, targetPos, origin)
    local currentTime = tick()
    if currentTime - lastShotTime < fireRateValue then return false end

    local character = LocalPlayer.Character
    if not character or not targetPart or not origin then return false end

    local direction = (targetPos - origin).Unit
    local time = tick()
    local cframe = CFrame.lookAt(origin, targetPos)

    local clientRemotes = LocalPlayer:FindFirstChild("ClientRemotes")
    if clientRemotes then
        pcall(function() clientRemotes.CheckFire:FireServer(time, origin) end)
        pcall(function() clientRemotes.CheckShot:FireServer(0, 0, 1, 0.8, cframe, targetPos, targetPart, 11, time) end)
        pcall(function() clientRemotes.Reload:FireServer() end)
    end

    local gun = ReplicatedStorage:FindFirstChild("ModuleScripts")
    if gun then
        gun = gun:FindFirstChild("GunModules")
        if gun then
            gun = gun:FindFirstChild("Remote")
            if gun then
                pcall(function() gun.ProjectileRender:FireServer(time, character, origin, direction * 999999, 360, 0, Vector3.zero, 5, "Bullet") end)
                pcall(function() gun.ProjectileFinished:FireServer(time, CFrame.new(targetPos), "Gib_T", false, 15, "rbxassetid://2814354338") end)
            end
        end
    end

    createBeam(origin, targetPos)
    playShootSound()
    lastShotTime = currentTime
    return true
end

-- ==================== 可见目标 ====================
local function getVisibleTargets()
    local targets = {}
    local character = LocalPlayer.Character
    if not character then return targets end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return targets end

    local origin = humanoidRootPart.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not isDead(player) and player.Character then
            local visiblePart, visiblePos, originPos = getVisiblePart(player.Character)
            if visiblePart and visiblePos and originPos then
                -- 只打视野内（屏幕内 + 自瞄 FOV 圈内）的目标
                if isInView(visiblePos) then
                    table.insert(targets, {
                        player = player,
                        distance = (visiblePos - origin).Magnitude,
                        part = visiblePart,
                        position = visiblePos,
                        origin = originPos
                    })
                end
            end
        end
    end

    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- ==================== 旧连接清理（重复执行不冲突） ====================
if getgenv().flashRagebotConnection then
    pcall(function() getgenv().flashRagebotConnection:Disconnect() end)
    getgenv().flashRagebotConnection = nil
end

-- ==================== UI（挂在主脚本"闪光" Tab 下） ====================
local sec = Tab:Section({ Title = "Ragebot 子弹追踪", Icon = "settings", Opened = true })

Tab:Paragraph({
    Title = "说明",
    Desc = "自动锁定视野内的可见目标，直接上报命中（ProjectileFinished）\n背后的/屏幕外的/自瞄FOV圈外的目标不会打"
})

Tab:Toggle({
    Title = "启用 Ragebot",
    Desc = "开启后自动锁定并射击可见目标",
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
                pcall(function()
                    if currentTarget and not isDead(currentTarget) then
                        local targetChar = currentTarget.Character
                        if targetChar then
                            local visiblePart, visiblePos, origin = getVisiblePart(targetChar)
                            if visiblePart and visiblePos and origin and isInView(visiblePos) then
                                shoot(currentTarget, visiblePart, visiblePos, origin)
                            else
                                currentTarget = nil
                            end
                        end
                    else
                        currentTarget = nil
                    end

                    if not currentTarget then
                        local targets = getVisibleTargets()
                        if #targets > 0 then
                            currentTarget = targets[1].player
                        end
                    end
                end)
            end)
        end
    end
})

Tab:Slider({
    Title = "射击间隔 (秒/发)",
    Desc = "越小射得越快，越容易被检测（原版固定 0.56）",
    Step = 0.05,
    Value = { Min = 0.2, Max = 2, Default = 0.56 },
    Callback = function(v)
        fireRateValue = v
    end
})

Tab:Toggle({
    Title = "适配自瞄 FOV 圈",
    Desc = "配合主脚本自瞄类的 FOV 圈，圈外目标不打（需自瞄类已加载）",
    Type = "Checkbox",
    Value = true,
    Callback = function(v)
        useAimbotFov = v
    end
})

print("[闪光Ragebot] 子弹追踪已挂载")
