-- 闪光 自瞄 + 弹道（WindUI 独立版）
-- 移植自小西源码/闪光.lua：视角自瞄 AimBot + 子弹追踪 Ragebot
-- 用法：在对应游戏里直接执行本脚本

if getgenv().__SUTURE_FLASH_LOADED then
    return
end
getgenv().__SUTURE_FLASH_LOADED = true

-- ==================== WindUI 加载 ====================
local WindUI
local ok, res = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok then
    warn("[闪光] WindUI 加载失败:", res)
    return
end
WindUI = res

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==================== 自瞄配置 ====================
local AimSettings = {
    Enabled = false,
    FOV = 100,
    Smoothness = 10,
    CrosshairDistance = 5,
    FOVColor = Color3.fromRGB(0, 255, 0),
    FriendCheck = true,
    WallCheck = true,
    TeamCheck = false,
    TargetPlayer = nil,
    TargetAll = true,
    FOVRainbowEnabled = true,
    FOVRainbowSpeed = 8,
    FOVEnabled = true
}
local AimTargetPart = "头"

-- ==================== 自瞄辅助 ====================
local FOVCircle = nil
local CurrentFOVHue = 0
local CurrentTarget = nil
local AimConnection = nil

local function GetRainbowColor(hue)
    local h = hue % 1
    local r, g, b
    if h < 1 / 6 then
        r, g, b = 1, h * 6, 0
    elseif h < 2 / 6 then
        r, g, b = 1 - (h - 1 / 6) * 6, 1, 0
    elseif h < 3 / 6 then
        r, g, b = 0, 1, (h - 2 / 6) * 6
    elseif h < 4 / 6 then
        r, g, b = 0, 1 - (h - 3 / 6) * 6, 1
    elseif h < 5 / 6 then
        r, g, b = (h - 4 / 6) * 6, 0, 1
    else
        r, g, b = 1, 0, 1 - (h - 5 / 6) * 6
    end
    return Color3.fromRGB(r * 255, g * 255, b * 255)
end

local function IsFriend(player)
    if not AimSettings.FriendCheck then
        return false
    end
    local success, result = pcall(function()
        return LocalPlayer:IsFriendsWith(player.UserId)
    end)
    return success and result
end

local function WallCheck(targetPosition, targetCharacter)
    if not AimSettings.WallCheck then
        return true
    end
    local success, result = pcall(function()
        local origin = Camera.CFrame.Position
        local direction = (targetPosition - origin).Unit
        local distance = (targetPosition - origin).Magnitude
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = { LocalPlayer.Character, targetCharacter }
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
        rayParams.IgnoreWater = true
        rayParams.CollisionGroup = "Default"
        local ray = Workspace:Raycast(origin, direction * distance, rayParams)
        return ray == nil
    end)
    return success and result
end

local function GetTargetPosition(character, partName)
    if not character then return nil end
    local part
    if partName == "头" then
        part = character:FindFirstChild("Head")
    elseif partName == "上身" then
        part = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
    elseif partName == "左腿" then
        part = character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("LeftUpperLeg")
    elseif partName == "右腿" then
        part = character:FindFirstChild("Right Leg") or character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("RightUpperLeg")
    elseif partName == "裆部" then
        part = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("LowerTorso")
    elseif partName == "胸部" then
        part = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    else
        part = character:FindFirstChild("Head")
    end
    return part and part.Position
end

-- ==================== 最近目标（FOV 圈内） ====================
local function GetClosestPlayer()
    local camera = Camera
    local mousePos = camera.ViewportSize / 2
    local nearestPlayer = nil
    local shortestDistance = AimSettings.FOV

    if CurrentTarget and CurrentTarget ~= LocalPlayer and CurrentTarget.Character then
        local hrp = CurrentTarget.Character:FindFirstChild("HumanoidRootPart")
        local humanoid = CurrentTarget.Character:FindFirstChild("Humanoid")
        if hrp and humanoid and humanoid.Health > 0 then
            local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
            if onScreen then
                local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                if distance <= AimSettings.FOV and WallCheck(hrp.Position, CurrentTarget.Character) then
                    if not AimSettings.FriendCheck or not IsFriend(CurrentTarget) then
                        if not AimSettings.TeamCheck or not (LocalPlayer.Team and CurrentTarget.Team == LocalPlayer.Team) then
                            return CurrentTarget
                        end
                    end
                end
            end
        end
    end

    CurrentTarget = nil
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local skip = false
            if AimSettings.FriendCheck and IsFriend(player) then
                skip = true
            end
            if not skip and AimSettings.TeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                skip = true
            end
            if not skip then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChild("Humanoid")
                if humanoidRootPart and humanoid and humanoid.Health > 0 then
                    if WallCheck(humanoidRootPart.Position, player.Character) then
                        local screenPos, onScreen = camera:WorldToViewportPoint(humanoidRootPart.Position)
                        if onScreen then
                            local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if distance < shortestDistance then
                                shortestDistance = distance
                                nearestPlayer = player
                            end
                        end
                    end
                end
            end
        end
    end
    if nearestPlayer then
        CurrentTarget = nearestPlayer
    end
    return nearestPlayer
end

-- ==================== 视角自瞄 ====================
local function AimBot()
    if not AimSettings.Enabled then
        return
    end
    pcall(function()
        local target = GetClosestPlayer()
        if target and target.Character then
            local humanoidRootPart = target.Character:FindFirstChild("HumanoidRootPart")
            local head = target.Character:FindFirstChild("Head")
            local targetPosition = GetTargetPosition(target.Character, AimTargetPart) or (head and head.Position) or (humanoidRootPart and humanoidRootPart.Position)
            if not targetPosition then return end
            if humanoidRootPart then
                local targetVelocity = humanoidRootPart.Velocity
                if AimSettings.CrosshairDistance > 0 then
                    local distance = (targetPosition - Camera.CFrame.Position).Magnitude
                    local timeToTarget = distance / 1000
                    targetPosition = targetPosition + (targetVelocity * timeToTarget * AimSettings.CrosshairDistance)
                end
            end
            local currentCFrame = Camera.CFrame
            local targetCFrame = CFrame.new(currentCFrame.Position, targetPosition)
            local smoothedCFrame = currentCFrame:Lerp(targetCFrame, 1 / AimSettings.Smoothness)
            Camera.CFrame = smoothedCFrame
        end
    end)
end

-- ==================== FOV 圈（Drawing 库） ====================
local function InitializeAimDrawings()
    pcall(function()
        if not FOVCircle and Drawing then
            FOVCircle = Drawing.new("Circle")
            FOVCircle.Visible = AimSettings.Enabled and AimSettings.FOVEnabled
            FOVCircle.Thickness = 2
            FOVCircle.Filled = false
            FOVCircle.Radius = AimSettings.FOV
            FOVCircle.Position = Camera.ViewportSize / 2
        end
    end)
end

local function UpdateFOVCircle()
    pcall(function()
        if FOVCircle then
            FOVCircle.Visible = AimSettings.Enabled and AimSettings.FOVEnabled
            FOVCircle.Radius = AimSettings.FOV
            if AimSettings.FOVRainbowEnabled then
                FOVCircle.Color = GetRainbowColor(CurrentFOVHue)
            else
                FOVCircle.Color = AimSettings.FOVColor
            end
            FOVCircle.Position = Camera.ViewportSize / 2
        end
    end)
end

-- ==================== Ragebot（子弹追踪） ====================
local ragebotEnabled = false
local currentTarget = nil
local lastShotTime = 0
local connection = nil

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

local function shoot(player, targetPart, targetPos, origin)
    local currentTime = tick()
    if currentTime - lastShotTime < 0.56 then return false end

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

    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- ==================== 旧连接清理 ====================
if getgenv().flashAimConnection then
    pcall(function() getgenv().flashAimConnection:Disconnect() end)
    getgenv().flashAimConnection = nil
end
if getgenv().flashRagebotConnection then
    pcall(function() getgenv().flashRagebotConnection:Disconnect() end)
    getgenv().flashRagebotConnection = nil
end

-- ==================== 窗口 ====================
local win = WindUI:CreateWindow({
    Title = "闪光 自瞄 + 弹道",
    Icon = "crosshair",
    Author = "WindUI 移植版",
    Folder = "Flash",
    Size = UDim2.fromOffset(540, 420),
    MinSize = Vector2.new(460, 320),
    MaxSize = Vector2.new(800, 560),
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

-- ==================== Tab1：自瞄 ====================
local aimTab = win:Tab({ Title = "自瞄", Icon = "crosshair", Locked = false })
local secA = aimTab:Section({ Title = "视角自瞄", Icon = "settings", Opened = true })

aimTab:Toggle({
    Title = "启用自瞄",
    Desc = "平滑转向目标（改相机视角）+ 显示 FOV 圈",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        AimSettings.Enabled = v
        if v then
            InitializeAimDrawings()
            UpdateFOVCircle()
            if AimConnection then
                AimConnection:Disconnect()
            end
            AimConnection = RunService.RenderStepped:Connect(function(deltaTime)
                pcall(function()
                    if AimSettings.FOVRainbowEnabled then
                        CurrentFOVHue = CurrentFOVHue + deltaTime * AimSettings.FOVRainbowSpeed / 10
                    end
                    UpdateFOVCircle()
                    AimBot()
                end)
            end)
        else
            if AimConnection then
                AimConnection:Disconnect()
                AimConnection = nil
            end
            if FOVCircle then
                FOVCircle.Visible = false
            end
        end
    end
})

aimTab:Slider({
    Title = "FOV 半径 (px)",
    Desc = "圈的大小，圈内才锁",
    Step = 5,
    Value = { Min = 20, Max = 500, Default = 100 },
    Callback = function(v)
        AimSettings.FOV = v
        if FOVCircle then
            FOVCircle.Radius = v
        end
    end
})

aimTab:Slider({
    Title = "平滑度",
    Desc = "越小转向越慢（像真人），越大越快",
    Step = 1,
    Value = { Min = 1, Max = 20, Default = 10 },
    Callback = function(v)
        AimSettings.Smoothness = v
    end
})

aimTab:Slider({
    Title = "提前量",
    Desc = "打移动目标预测（0 = 不打提前量）",
    Step = 1,
    Value = { Min = 0, Max = 20, Default = 5 },
    Callback = function(v)
        AimSettings.CrosshairDistance = v
    end
})

aimTab:Dropdown({
    Title = "瞄准部位",
    Desc = "选择锁定的身体部位",
    Values = { "头", "上身", "胸部", "裆部", "左腿", "右腿" },
    Value = "头",
    Callback = function(v)
        AimTargetPart = v
    end
})

aimTab:Toggle({
    Title = "显示 FOV 圈",
    Desc = "屏幕中央的圈",
    Type = "Checkbox",
    Value = true,
    Callback = function(v)
        AimSettings.FOVEnabled = v
        if FOVCircle then
            FOVCircle.Visible = AimSettings.Enabled and v
        end
    end
})

aimTab:Toggle({
    Title = "FOV 圈彩虹色",
    Desc = "圈的颜色渐变",
    Type = "Checkbox",
    Value = true,
    Callback = function(v)
        AimSettings.FOVRainbowEnabled = v
    end
})

aimTab:Toggle({
    Title = "墙壁检测",
    Desc = "有墙挡着不锁",
    Type = "Checkbox",
    Value = true,
    Callback = function(v)
        AimSettings.WallCheck = v
    end
})

aimTab:Toggle({
    Title = "跳过好友",
    Desc = "好友不锁",
    Type = "Checkbox",
    Value = true,
    Callback = function(v)
        AimSettings.FriendCheck = v
    end
})

aimTab:Toggle({
    Title = "队伍检测",
    Desc = "同队不锁",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        AimSettings.TeamCheck = v
    end
})

-- ==================== Tab2：Ragebot（弹道） ====================
local killTab = win:Tab({ Title = "Ragebot", Icon = "zap", Locked = false })
local secK = killTab:Section({ Title = "子弹追踪", Icon = "settings", Opened = true })

killTab:Paragraph({
    Title = "说明",
    Desc = "自动锁定可见目标，直接上报命中（ProjectileFinished）\n配合自瞄一起用效果最佳"
})

killTab:Toggle({
    Title = "启用 Ragebot",
    Desc = "自动瞄准并射击可见目标",
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
                            if visiblePart and visiblePos and origin then
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

print("[闪光] 自瞄 + 弹道 已加载")
warn("[闪光] 检测到此服务器闪光")
