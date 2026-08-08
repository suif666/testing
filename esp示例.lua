-- ESP类 远程脚本（玩家ESP + NPC ESP，依赖主脚本提供 ESPTab）
-- 主脚本需设置：getgenv().Tabs.ESPTab（或 getgenv().SutureESPTab）

if getgenv().__SUTURE_ESP_LOADED then
    return
end
getgenv().__SUTURE_ESP_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.ESPTab) or getgenv().SutureESPTab
if not Tab then
    warn("[ESP] 未找到 ESPTab，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

-- ===== 配置 =====
local defaultESP = {
    PlayerEnabled = false,
    NpcEnabled = false,
    -- 玩家
    ShowName = true,
    ShowHealth = false,
    ShowDistance = false,
    ShowTracer = false,
    SkipTeam = false,
    TeamColor = false,
    WallCheck = false,
    TracerPosition = "中",
    FontSize = 14,
    -- NPC
    NpcShowName = true,
    NpcShowHealth = false,
    NpcShowDistance = false,
    NpcShowTracer = false,
    NpcWallCheck = false,
    NpcTracerPosition = "中",
    NpcFontSize = 14,
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
    if state.Info then pcall(function() state.Info:Destroy() end) end
    if state.Tracer then pcall(function() state.Tracer:Remove() end) end
end

local function applyPlayerESP(p)
    if p == lp then return end

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
        state.Info.TextLabel.TextSize = ESP.FontSize

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
            end
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

local function destroyNpcState(state)
    if not state then return end
    if state.Highlight then pcall(function() state.Highlight:Destroy() end) end
    if state.Info then pcall(function() state.Info:Destroy() end) end
    if state.Tracer then pcall(function() state.Tracer:Remove() end) end
end

local function updateNpcESP(model)
    if not ESP.NpcEnabled then return end
    local state = npcStates[model]
    local hum = model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildWhichIsA("Humanoid", true)
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
    local head = model:FindFirstChild("Head") or root

    local valid = hum ~= nil and root ~= nil and hum.Health > 0

    if not valid then
        if state then
            destroyNpcState(state)
            npcStates[model] = nil
        end
        return
    end

    if not state then
        state = {}
        npcStates[model] = state
    end

    local color = Color3.fromRGB(255, 255, 255)

    -- 轮廓高亮（穿墙显示）
    if ESP.NpcWallCheck then
        if not state.Highlight then
            state.Highlight = Instance.new("Highlight", model)
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

    -- 头顶信息（名称 / 血量 / 距离）
    if ESP.NpcShowName or ESP.NpcShowHealth or ESP.NpcShowDistance then
        if not state.Info then
            state.Info = Instance.new("BillboardGui", model)
            state.Info.Size = UDim2.new(0, 200, 0, 50)
            state.Info.Adornee = head
            state.Info.ExtentsOffset = Vector3.new(0, 3.5, 0)
            state.Info.AlwaysOnTop = ESP.NpcWallCheck
            local txt = Instance.new("TextLabel", state.Info)
            txt.Size = UDim2.new(1, 0, 1, 0)
            txt.BackgroundTransparency = 1
            txt.RichText = true
            txt.TextStrokeTransparency = 0.5
            txt.Font = Enum.Font.GothamMedium
        end
        state.Info.AlwaysOnTop = ESP.NpcWallCheck
        state.Info.TextLabel.TextSize = ESP.NpcFontSize

        local text = ""
        if ESP.NpcShowName then
            text = text .. "<font color='#ffffff'><b>" .. model.Name .. "</b></font>"
        end
        if ESP.NpcShowHealth then
            local hp = math.floor(hum.Health)
            local c = hp > 50 and "#55ff55" or "#ff5555"
            text = text .. (text ~= "" and "\n" or "") .. "<font color='" .. c .. "'>血量: " .. hp .. "</font>"
        end
        if ESP.NpcShowDistance then
            local dist = math.floor((workspace.CurrentCamera.CFrame.Position - root.Position).Magnitude)
            text = text .. (text ~= "" and "\n" or "") .. "<font color='#ffffff'>距离: " .. dist .. "m</font>"
        end
        state.Info.TextLabel.Text = text
    elseif state.Info then
        pcall(function() state.Info:Destroy() end)
        state.Info = nil
    end

    -- 射线
    if ESP.NpcShowTracer then
        if Drawing then
            if not state.Tracer then
                state.Tracer = Drawing.new("Line")
            end
            state.Tracer.Color = color
            state.Tracer.Visible = true
        end
    elseif state.Tracer then
        state.Tracer.Visible = false
    end
end

local function clearNpcESP()
    for model, state in pairs(npcStates) do
        destroyNpcState(state)
    end
    npcStates = {}
end

-- NPC 扫描（3 秒兜底 + 新增实时）
local lastNpcScan = 0
local function scanNpcs()
    if not ESP.NpcEnabled then return end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isNpcModel(obj) then
            npcStates[obj] = npcStates[obj] or {}
        end
    end
end

workspace.DescendantAdded:Connect(function(obj)
    if ESP.NpcEnabled and isNpcModel(obj) then
        npcStates[obj] = {}
    end
end)

-- ===== 每帧更新 =====
RunService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end

    -- 玩家（不绘制自己）
    if ESP.PlayerEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                applyPlayerESP(p)
            end
        end
    else
        clearPlayerESP()
    end

    -- NPC
    if ESP.NpcEnabled then
        for model in pairs(npcStates) do
            updateNpcESP(model)
        end
        if os.clock() - lastNpcScan >= 3 then
            lastNpcScan = os.clock()
            scanNpcs()
        end
    else
        clearNpcESP()
    end

    -- 射线位置更新
    if (ESP.ShowTracer or ESP.NpcShowTracer) and Drawing then
        local viewport = cam.ViewportSize
        local function originFor(pos)
            if pos == "上" then
                return Vector2.new(viewport.X / 2, 0)
            elseif pos == "下" then
                return Vector2.new(viewport.X / 2, viewport.Y)
            end
            return Vector2.new(viewport.X / 2, viewport.Y / 2)
        end

        local function updateTracer(rootPart, tracer, origin)
            if not tracer or not tracer.Visible or not rootPart then return end
            local pos, onScreen = cam:WorldToViewportPoint(rootPart.Position)
            if onScreen then
                tracer.From = origin
                tracer.To = Vector2.new(pos.X, pos.Y)
            else
                tracer.Visible = false
            end
        end

        local pOrigin = originFor(ESP.TracerPosition)
        for p, state in pairs(playerStates) do
            local char = p.Character
            updateTracer(char and char:FindFirstChild("HumanoidRootPart"), state.Tracer, pOrigin)
        end

        local nOrigin = originFor(ESP.NpcTracerPosition)
        for model, state in pairs(npcStates) do
            updateTracer(model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart, state.Tracer, nOrigin)
        end
    end
end)

-- ===== UI（折叠分组） =====
local uiOk, uiErr = pcall(function()
    local playerSec = Tab:Section({ Title = "玩家ESP", Icon = "user", Opened = true })
    local npcSec = Tab:Section({ Title = "NPC ESP", Icon = "user", Opened = true })

    -- ===== 玩家ESP =====
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
        Title = "轮廓高亮",
        Desc = "穿墙显示人物轮廓",
        Type = "Checkbox",
        Value = ESP.WallCheck or false,
        Callback = function(s)
            ESP.WallCheck = s
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

    playerSec:Dropdown({
        Title = "射线位置",
        Values = { "上", "中", "下" },
        Value = ESP.TracerPosition or "中",
        Callback = function(s)
            ESP.TracerPosition = s
        end
    })

    playerSec:Slider({
        Title = "字体大小",
        Step = 1,
        Value = { Min = 8, Max = 30, Default = ESP.FontSize or 14 },
        Callback = function(v)
            ESP.FontSize = tonumber(v) or 14
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

    -- ===== NPC ESP =====
    npcSec:Toggle({
        Title = "NPC ESP",
        Type = "Checkbox",
        Value = ESP.NpcEnabled or false,
        Callback = function(s)
            ESP.NpcEnabled = s
            if not s then
                clearNpcESP()
            end
        end
    })

    npcSec:Toggle({
        Title = "轮廓高亮",
        Desc = "穿墙显示 NPC 轮廓",
        Type = "Checkbox",
        Value = ESP.NpcWallCheck or false,
        Callback = function(s)
            ESP.NpcWallCheck = s
        end
    })

    npcSec:Toggle({
        Title = "显示名称",
        Type = "Checkbox",
        Value = ESP.NpcShowName or false,
        Callback = function(s)
            ESP.NpcShowName = s
        end
    })

    npcSec:Toggle({
        Title = "显示血量",
        Type = "Checkbox",
        Value = ESP.NpcShowHealth or false,
        Callback = function(s)
            ESP.NpcShowHealth = s
        end
    })

    npcSec:Toggle({
        Title = "显示距离",
        Type = "Checkbox",
        Value = ESP.NpcShowDistance or false,
        Callback = function(s)
            ESP.NpcShowDistance = s
        end
    })

    npcSec:Toggle({
        Title = "显示射线",
        Type = "Checkbox",
        Value = ESP.NpcShowTracer or false,
        Callback = function(s)
            ESP.NpcShowTracer = s
            if not s then
                for model, state in pairs(npcStates) do
                    if state.Tracer then
                        state.Tracer.Visible = false
                    end
                end
            end
        end
    })

    npcSec:Dropdown({
        Title = "射线位置",
        Values = { "上", "中", "下" },
        Value = ESP.NpcTracerPosition or "中",
        Callback = function(s)
            ESP.NpcTracerPosition = s
        end
    })

    npcSec:Slider({
        Title = "字体大小",
        Step = 1,
        Value = { Min = 8, Max = 30, Default = ESP.NpcFontSize or 14 },
        Callback = function(v)
            ESP.NpcFontSize = tonumber(v) or 14
        end
    })
end)
