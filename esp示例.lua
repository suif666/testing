-- ESP 独立测试脚本
-- 用法：复制进注入器执行（不需要主脚本）
-- 测试没问题后，再把这个文件改回远程格式即可

local WindUI = getgenv().WindUI
if not WindUI then
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
    getgenv().WindUI = WindUI
end

local win = WindUI:CreateWindow({
    Title = "ESP测试",
    Icon = "user",
    Author = "suif",
    Folder = "ESPTest",
    Size = UDim2.fromOffset(620, 460),
    MinSize = Vector2.new(560, 350),
    MaxSize = Vector2.new(900, 600),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    NewElements = true,
})

local shijueSec = win:Section({ Title = "视觉类", Icon = "palette", Locked = false })
local Tab = shijueSec:Tab({ Title = "ESP", Icon = "user", Locked = false })
Tab:Select()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- ===== 配置（参考 Xa 的设置项） =====
local defaultESP = {
    PlayerEnabled = false,
    NpcEnabled = false,
    ShowName = true,
    ShowBox = false,
    ShowHealth = false,
    ShowDistance = false,
    ShowTracer = false,
    SkipTeam = false,
    TeamColor = false,
    WallCheck = false,
    TracerPosition = "中",
    TracerThickness = 1,
}
getgenv().SutureESP = getgenv().SutureESP or {}
for k, v in pairs(defaultESP) do
    if getgenv().SutureESP[k] == nil then
        getgenv().SutureESP[k] = v
    end
end

local ESP = getgenv().SutureESP
local warnedDrawing = false

local function teamColor(p)
    return p.TeamColor.Color
end

-- ===== 玩家 ESP =====
local playerStates = {}

local function destroyState(state)
    if not state then return end
    if state.Highlight then pcall(function() state.Highlight:Destroy() end) end
    if state.Box then pcall(function() state.Box:Destroy() end) end
    if state.Info then pcall(function() state.Info:Destroy() end) end
    if state.Tracer then pcall(function() state.Tracer:Remove() end) end
end

local function applyPlayerESP(p)
    local state = playerStates[p]
    local char = p.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local head = char and char:FindFirstChild("Head")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    local valid = char and hum and head and root and hum.Health > 0
        and not (ESP.SkipTeam and p.Team and lp.Team and p.Team == lp.Team)

    if not valid then
        if state then
            destroyState(state)
            playerStates[p] = nil
        end
        return
    end

    if not state then
        state = {}
        playerStates[p] = state
    elseif state.Char ~= char then
        destroyState(state)
        state = {}
        playerStates[p] = state
    end
    state.Char = char

    local color = ESP.TeamColor and teamColor(p) or Color3.fromRGB(255, 255, 255)

    -- 高亮（穿墙显示用 AlwaysOnTop）
    if ESP.WallCheck then
        if not state.Highlight then
            state.Highlight = Instance.new("Highlight", char)
            state.Highlight.FillTransparency = 0.75
            state.Highlight.OutlineTransparency = 0
        end
        state.Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        state.Highlight.FillColor = color
        state.Highlight.OutlineColor = color
    elseif state.Highlight then
        pcall(function() state.Highlight:Destroy() end)
        state.Highlight = nil
    end

    -- 方框
    if ESP.ShowBox then
        if not state.Box then
            state.Box = Instance.new("BillboardGui", char)
            state.Box.Size = UDim2.new(4.5, 0, 6, 0)
            state.Box.Adornee = root
            state.Box.AlwaysOnTop = ESP.WallCheck
            local f = Instance.new("Frame", state.Box)
            f.Size = UDim2.new(1, 0, 1, 0)
            f.BackgroundTransparency = 1
            local s = Instance.new("UIStroke", f)
            s.Thickness = 1.5
        end
        state.Box.AlwaysOnTop = ESP.WallCheck
        state.Box.Frame.UIStroke.Color = color
    elseif state.Box then
        pcall(function() state.Box:Destroy() end)
        state.Box = nil
    end

    -- 头顶信息（名称 / 血量 / 距离）
    if ESP.ShowName or ESP.ShowHealth or ESP.ShowDistance then
        if not state.Info then
            state.Info = Instance.new("BillboardGui", char)
            state.Info.Size = UDim2.new(0, 200, 0, 50)
            state.Info.Adornee = head
            state.Info.ExtentsOffset = Vector3.new(0, 3.5, 0)
            state.Info.AlwaysOnTop = ESP.WallCheck
            local txt = Instance.new("TextLabel", state.Info)
            txt.Size = UDim2.new(1, 0, 1, 0)
            txt.BackgroundTransparency = 1
            txt.RichText = true
            txt.TextStrokeTransparency = 0.5
            txt.Font = Enum.Font.GothamMedium
        end
        state.Info.AlwaysOnTop = ESP.WallCheck

        local text = ""
        if ESP.ShowName then
            text = text .. "<font color='#ffffff'><b>" .. p.DisplayName .. "</b></font>"
        end
        if ESP.ShowHealth then
            local hp = math.floor(hum.Health)
            local c = hp > 50 and "#55ff55" or "#ff5555"
            text = text .. (text ~= "" and "\n" or "") .. "<font color='" .. c .. "'>血量: " .. hp .. "</font>"
        end
        if ESP.ShowDistance then
            local dist = math.floor((workspace.CurrentCamera.CFrame.Position - root.Position).Magnitude)
            text = text .. (text ~= "" and "\n" or "") .. "<font color='#ffffff'>距离: " .. dist .. "m</font>"
        end
        state.Info.TextLabel.Text = text
    elseif state.Info then
        pcall(function() state.Info:Destroy() end)
        state.Info = nil
    end

    -- 射线（依赖 Drawing）
    if ESP.ShowTracer then
        if Drawing then
            if not state.Tracer then
                state.Tracer = Drawing.new("Line")
                state.Tracer.Thickness = ESP.TracerThickness
            end
            state.Tracer.Thickness = ESP.TracerThickness
            state.Tracer.Color = color
            state.Tracer.Visible = true
        elseif not warnedDrawing then
            warnedDrawing = true
            warn("[ESP] 当前注入器不支持 Drawing，射线功能不可用")
        end
    elseif state.Tracer then
        state.Tracer.Visible = false
    end
end

local function clearPlayerESP()
    for p, state in pairs(playerStates) do
        destroyState(state)
    end
    playerStates = {}
end

-- ===== NPC ESP =====
local npcStates = {}

local function isNpcModel(model)
    if not model or not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildWhichIsA("Humanoid", true)
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
    return hum ~= nil and root ~= nil
end

local function applyNpcESP(model)
    if not ESP.NpcEnabled or not isNpcModel(model) then return end
    local state = npcStates[model]
    if not state then
        state = {}
        npcStates[model] = state
    end

    if not state.Highlight then
        state.Highlight = Instance.new("Highlight", model)
        state.Highlight.FillColor = Color3.fromRGB(255, 255, 255)
        state.Highlight.FillTransparency = 0.75
        state.Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    end
    state.Highlight.DepthMode = ESP.WallCheck
        and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded

    if not state.Info then
        state.Info = Instance.new("BillboardGui", model)
        state.Info.Size = UDim2.new(0, 200, 0, 30)
        state.Info.Adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        state.Info.ExtentsOffset = Vector3.new(0, 3, 0)
        state.Info.AlwaysOnTop = ESP.WallCheck
        local txt = Instance.new("TextLabel", state.Info)
        txt.Size = UDim2.new(1, 0, 1, 0)
        txt.BackgroundTransparency = 1
        txt.RichText = true
        txt.TextStrokeTransparency = 0.5
        txt.Font = Enum.Font.GothamMedium
    end
    state.Info.AlwaysOnTop = ESP.WallCheck
    state.Info.TextLabel.Text = "<font color='#ffffff'><b>" .. model.Name .. "</b></font>"
end

local function clearNpcESP()
    for model, state in pairs(npcStates) do
        if state.Highlight then pcall(function() state.Highlight:Destroy() end) end
        if state.Info then pcall(function() state.Info:Destroy() end) end
    end
    npcStates = {}
end

-- NPC 扫描（3 秒兜底 + 新增实时）
local lastNpcScan = 0
local function scanNpcs()
    if not ESP.NpcEnabled then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isNpcModel(obj) then
            applyNpcESP(obj)
        end
    end
end

workspace.DescendantAdded:Connect(function(obj)
    if ESP.NpcEnabled and isNpcModel(obj) then
        applyNpcESP(obj)
    end
end)

-- ===== 每帧更新 =====
RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end

    -- 玩家状态更新
    if ESP.PlayerEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            applyPlayerESP(p)
        end
    else
        clearPlayerESP()
    end

    -- NPC 兜底扫描
    if ESP.NpcEnabled and os.clock() - lastNpcScan >= 3 then
        lastNpcScan = os.clock()
        scanNpcs()
    end

    -- 射线位置更新
    if ESP.ShowTracer and Drawing then
        local viewport = cam.ViewportSize
        local origin
        if ESP.TracerPosition == "上" then
            origin = Vector2.new(viewport.X / 2, 0)
        elseif ESP.TracerPosition == "下" then
            origin = Vector2.new(viewport.X / 2, viewport.Y)
        else
            origin = Vector2.new(viewport.X / 2, viewport.Y / 2)
        end

        for p, state in pairs(playerStates) do
            if state.Tracer and state.Tracer.Visible then
                local char = p.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    local pos, onScreen = cam:WorldToViewportPoint(root.Position)
                    if onScreen then
                        state.Tracer.From = origin
                        state.Tracer.To = Vector2.new(pos.X, pos.Y)
                    else
                        state.Tracer.Visible = false
                    end
                end
            end
        end
    end
end)

-- ===== UI（折叠分组） =====
local uiOk, uiErr = pcall(function()
    local playerSec = Tab:Section({ Title = "玩家ESP", Icon = "user", Opened = true })
    local npcSec = Tab:Section({ Title = "NPC ESP", Icon = "user", Opened = true })

    playerSec:Toggle({
        Title = "ESP开关",
        Type = "Checkbox",
        Value = ESP.PlayerEnabled or false,
        Callback = function(s)
            ESP.PlayerEnabled = s
            if not s then
                clearPlayerESP()
            end
        end
    })

    playerSec:Toggle({
        Title = "显示名称",
        Type = "Checkbox",
        Value = ESP.ShowName or false,
        Callback = function(s)
            ESP.ShowName = s
        end
    })

    playerSec:Toggle({
        Title = "显示方框",
        Type = "Checkbox",
        Value = ESP.ShowBox or false,
        Callback = function(s)
            ESP.ShowBox = s
        end
    })

    playerSec:Toggle({
        Title = "显示血量",
        Type = "Checkbox",
        Value = ESP.ShowHealth or false,
        Callback = function(s)
            ESP.ShowHealth = s
        end
    })

    playerSec:Toggle({
        Title = "显示距离",
        Type = "Checkbox",
        Value = ESP.ShowDistance or false,
        Callback = function(s)
            ESP.ShowDistance = s
        end
    })

    playerSec:Toggle({
        Title = "显示射线",
        Type = "Checkbox",
        Value = ESP.ShowTracer or false,
        Callback = function(s)
            ESP.ShowTracer = s
            if not s then
                for p, state in pairs(playerStates) do
                    if state.Tracer then
                        state.Tracer.Visible = false
                    end
                end
            end
        end
    })

    playerSec:Toggle({
        Title = "跳过队友",
        Type = "Checkbox",
        Value = ESP.SkipTeam or false,
        Callback = function(s)
            ESP.SkipTeam = s
        end
    })

    playerSec:Toggle({
        Title = "队伍颜色",
        Type = "Checkbox",
        Value = ESP.TeamColor or false,
        Callback = function(s)
            ESP.TeamColor = s
        end
    })

    playerSec:Toggle({
        Title = "穿墙显示",
        Type = "Checkbox",
        Value = ESP.WallCheck or false,
        Callback = function(s)
            ESP.WallCheck = s
        end
    })

    playerSec:Dropdown({
        Title = "射线位置",
        Values = { "上", "中", "下" },
        Value = ESP.TracerPosition or "中",
        Callback = function(v)
            ESP.TracerPosition = v
        end
    })

    playerSec:Slider({
        Title = "射线粗细",
        Step = 1,
        Value = { Min = 0, Max = 10, Default = ESP.TracerThickness or 1 },
        Callback = function(v)
            ESP.TracerThickness = tonumber(v) or 1
        end
    })

    npcSec:Toggle({
        Title = "NPC ESP",
        Desc = "高亮 + 名字（白色）",
        Type = "Checkbox",
        Value = ESP.NpcEnabled or false,
        Callback = function(s)
            ESP.NpcEnabled = s
            if s then
                scanNpcs()
            else
                clearNpcESP()
            end
        end
    })
end)

if not uiOk then
    warn("[ESP] UI 创建失败:", uiErr)
else
    print("[ESP] 独立测试脚本加载完成")
end
