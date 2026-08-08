-- 自瞄类 远程脚本（显示功能 + UI，依赖主脚本提供 AimbotTab）
-- 主脚本需设置：getgenv().Tabs.AimbotTab（或 getgenv().SutureAimbotTab）

if getgenv().__SUTURE_AIMBOT_LOADED then
    return
end
getgenv().__SUTURE_AIMBOT_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.AimbotTab) or getgenv().SutureAimbotTab
if not Tab then
    warn("[自瞄类] 未找到 AimbotTab，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local plrs = Players

-- ============ 配置（显示FOV圈默认关闭） ============
local defaultAimbot = {
    Enabled = false, ShowFov = false, Fov = 200, MaxDistance = 1000,
    Part = "Head", TeamCheck = false, WallCheck = false,
    Smooth = 0.8, Prediction = 0.1,
    LockStrength = 0.5, Priority = "准心优先",
}
getgenv().SutureAimbot = getgenv().SutureAimbot or {}
for k, v in pairs(defaultAimbot) do
    if getgenv().SutureAimbot[k] == nil then
        getgenv().SutureAimbot[k] = v
    end
end

local Aimbot = getgenv().SutureAimbot

-- ============ FOV 圈（UI 版圆环，参考夜脚本源：UIStroke + UICorner） ============
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "AimbotFOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
do
    local ok, p = pcall(gethui)
    fovGui.Parent = ok and p or game:GetService("CoreGui")
end

local fovRing = Instance.new("Frame")
fovRing.Name = "Ring"
fovRing.AnchorPoint = Vector2.new(0.5, 0.5)
fovRing.Position = UDim2.new(0.5, 0, 0.5, 0)
fovRing.Size = UDim2.fromOffset(200, 200)
fovRing.BackgroundTransparency = 1
fovRing.Visible = false
fovRing.Parent = fovGui
Instance.new("UICorner", fovRing).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 2
fovStroke.Color = Color3.fromRGB(255, 255, 255)
fovStroke.Parent = fovRing

-- ============ 自瞄逻辑 ============
local function getAimPart(character)
    if not character then return nil end
    if Aimbot.Part == "随机" then
        local list = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }
        return character:FindFirstChild(list[math.random(1, #list)])
    end
    return character:FindFirstChild(Aimbot.Part)
end

local function getAimTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local center = cam.ViewportSize / 2
    local best, bestScore = nil, math.huge
    local myChar = lp.Character

    for _, p in ipairs(plrs:GetPlayers()) do
        if p == lp then continue end
        local char = p.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if Aimbot.TeamCheck and p.Team and lp.Team and p.Team == lp.Team then continue end

        local part = getAimPart(char)
        if not part then continue end

        local pos, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if screenDist > Aimbot.Fov then continue end

        local worldDist = (cam.CFrame.Position - part.Position).Magnitude
        if worldDist > Aimbot.MaxDistance then continue end

        if Aimbot.WallCheck then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { myChar, char }
            local ray = workspace:Raycast(
                cam.CFrame.Position,
                (part.Position - cam.CFrame.Position).Unit * Aimbot.MaxDistance,
                params
            )
            if ray and ray.Instance then continue end
        end

        -- 按优先级打分：血量低 / 距离近 / 准心近
        local score
        if Aimbot.Priority == "血量低优先" then
            score = hum.Health
        elseif Aimbot.Priority == "距离优先" then
            score = worldDist
        else
            score = screenDist
        end

        if score < bestScore then
            bestScore = score
            best = { Character = char, Part = part }
        end
    end

    return best
end

local lastMousePos = UIS:GetMouseLocation()

local function aimbotLoop()
    local cam = workspace.CurrentCamera
    if not cam then return end

    -- FOV 圈：只跟“显示FOV圈”开关绑定，不依赖自瞄总开关
    if Aimbot.ShowFov then
        pcall(function()
            fovRing.Visible = true
            fovRing.Size = UDim2.fromOffset(Aimbot.Fov * 2, Aimbot.Fov * 2)
            fovRing.Position = UDim2.new(0.5, 0, 0.5, 0)
        end)
    elseif fovRing.Visible then
        fovRing.Visible = false
    end

    if not Aimbot.Enabled then return end

    -- 追踪鼠标移动量
    local mousePos = UIS:GetMouseLocation()
    local mouseDelta = (mousePos - lastMousePos).Magnitude
    lastMousePos = mousePos

    local target = getAimTarget()
    if target and target.Part then
        local targetPos = target.Part.Position
        if Aimbot.Prediction > 0 then
            targetPos = targetPos + target.Part.AssemblyLinearVelocity * Aimbot.Prediction
        end
        local targetCF = CFrame.new(cam.CFrame.Position, targetPos)
        if mouseDelta > 1 then
            -- 鼠标移动中：吸附力度越大拉回越强，越小越跟手（容易移开）
            cam.CFrame = cam.CFrame:Lerp(targetCF, Aimbot.Smooth * (Aimbot.LockStrength or 0.5))
        else
            cam.CFrame = cam.CFrame:Lerp(targetCF, Aimbot.Smooth)
        end
    end
end

RunService.RenderStepped:Connect(aimbotLoop)

-- ============ UI ============
local uiOk, uiErr = pcall(function()
    Tab:Toggle({
        Title = "自瞄开关",
        Desc = "开启后一直自动瞄准",
        Type = "Checkbox",
        Value = Aimbot.Enabled or false,
        Callback = function(s)
            Aimbot.Enabled = s
        end
    })

    Tab:Toggle({
        Title = "显示FOV圈",
        Desc = "屏幕中心显示瞄准范围圈",
        Type = "Checkbox",
        Value = Aimbot.ShowFov or false,
        Callback = function(s)
            Aimbot.ShowFov = s
            if not s and fovRing then
                fovRing.Visible = false
            end
        end
    })

    Tab:Slider({
        Title = "FOV范围",
        Desc = "屏幕中心多大范围内会锁定目标",
        Step = 10,
        Value = { Min = 10, Max = 700, Default = Aimbot.Fov or 200 },
        Callback = function(v)
            Aimbot.Fov = tonumber(v) or 200
        end
    })

    Tab:Slider({
        Title = "最大距离",
        Desc = "超过该距离不锁定（米）",
        Step = 50,
        Value = { Min = 50, Max = 6000, Default = Aimbot.MaxDistance or 1000 },
        Callback = function(v)
            Aimbot.MaxDistance = tonumber(v) or 1000
        end
    })

    Tab:Dropdown({
        Title = "瞄准部位",
        Values = { "Head", "HumanoidRootPart", "随机" },
        Value = Aimbot.Part or "Head",
        Callback = function(v)
            Aimbot.Part = v
        end
    })

    Tab:Dropdown({
        Title = "优先级",
        Desc = "多个目标时优先锁定谁",
        Values = { "血量低优先", "距离优先", "准心优先" },
        Value = Aimbot.Priority or "准心优先",
        Callback = function(v)
            Aimbot.Priority = v
        end
    })

    Tab:Toggle({
        Title = "队伍检测",
        Desc = "开启后跳过同队玩家",
        Type = "Checkbox",
        Value = Aimbot.TeamCheck or false,
        Callback = function(s)
            Aimbot.TeamCheck = s
        end
    })

    Tab:Toggle({
        Title = "穿墙自瞄",
        Desc = "开启后有墙挡住就不会锁定",
        Type = "Checkbox",
        Value = Aimbot.WallCheck or false,
        Callback = function(s)
            Aimbot.WallCheck = s
        end
    })

    Tab:Slider({
        Title = "平滑度",
        Desc = "越低越平滑，1 = 瞬间转向",
        Step = 0.05,
        Value = { Min = 0.1, Max = 1, Default = Aimbot.Smooth or 0.8 },
        Callback = function(v)
            Aimbot.Smooth = tonumber(v) or 0.8
        end
    })

    Tab:Slider({
        Title = "吸附力度",
        Desc = "数值越大越难把准星从目标上拉开，越小越容易移开",
        Step = 1,
        Value = { Min = 0, Max = 10, Default = math.floor((Aimbot.LockStrength or 0.5) * 10) },
        Callback = function(v)
            Aimbot.LockStrength = (tonumber(v) or 5) / 10
        end
    })

    Tab:Slider({
        Title = "预判(秒)",
        Desc = "0 = 关闭；预测移动目标的位置（参考 Xa 的预判）",
        Step = 0.05,
        Value = { Min = 0, Max = 1, Default = Aimbot.Prediction or 0.1 },
        Callback = function(v)
            Aimbot.Prediction = tonumber(v) or 0.1
        end
    })
end)
