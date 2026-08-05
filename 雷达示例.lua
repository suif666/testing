-- 雷达 远程脚本（显示功能 + UI，依赖主脚本提供 RadarTab）
-- 主脚本需设置：getgenv().Tabs.RadarTab（或 getgenv().SutureRadarTab）
print("[雷达] 远程脚本开始执行")

if getgenv().__SUTURE_RADAR_LOADED then
    return
end
getgenv().__SUTURE_RADAR_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.RadarTab) or getgenv().SutureRadarTab
if not Tab then
    warn("[雷达] 未找到 RadarTab，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local RADAR_SIZE = 200          -- 普通模式雷达边长
local BLIP_COUNT = 50           -- 亮点上限
local RANGE_MIN = 50            -- 范围滑块最小值（m）
local RANGE_MAX = 1000          -- 范围滑块最大值（m）

local Settings = {
    Enabled = false,            -- 默认关闭
    Zoomed = false,
    Position = "右上",
    Corner = 50,
    Range = 200,
    ShowEnemy = true,
    ShowTeam = true,
    ShowFriend = true,
    ShowNeutral = true,
}

local CAT_COLORS = {
    enemy = Color3.fromRGB(255, 70, 70),
    team = Color3.fromRGB(70, 200, 90),
    friend = Color3.fromRGB(255, 200, 60),
    neutral = Color3.fromRGB(180, 180, 190),
}

local function colorToHex(c)
    return string.format(
        "#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5)
    )
end

-- ============ 雷达父级：优先 gethui()（Delta 兼容） ============
local RadarParent
do
    local ok, p = pcall(gethui)
    if ok and p then
        RadarParent = p
    end
    if not RadarParent then
        local ok2, c = pcall(function()
            return game:GetService("CoreGui")
        end)
        if ok2 then
            RadarParent = c
        end
    end
    if not RadarParent then
        RadarParent = lp:WaitForChild("PlayerGui")
    end
end

local radarGui = Instance.new("ScreenGui")
radarGui.Name = "RadarOverlay"
radarGui.DisplayOrder = -99999      -- 尽量压在游戏 UI 下面，不挡界面
radarGui.IgnoreGuiInset = true
radarGui.ResetOnSpawn = false
radarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
radarGui.Parent = RadarParent

local protect = protectgui or (syn and syn.protect_gui)
if protect then
    pcall(protect, radarGui)
end

local okOverlay, errOverlay = pcall(function()
    -- ============ 雷达底板（Active=false 不拦截游戏点击） ============
    local radarFrame = Instance.new("Frame")
    radarFrame.Name = "Radar"
    radarFrame.Size = UDim2.fromOffset(RADAR_SIZE, RADAR_SIZE)
    radarFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    radarFrame.BackgroundTransparency = 0.25
    radarFrame.ClipsDescendants = true
    radarFrame.Active = false
    radarFrame.ZIndex = 4
    radarFrame.Parent = radarGui

    local corner = Instance.new("UICorner")
    corner.Parent = radarFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 200, 255)
    stroke.Thickness = 2
    stroke.Parent = radarFrame

    -- 十字参考线
    local crossH = Instance.new("Frame")
    crossH.Size = UDim2.new(1, 0, 0, 1)
    crossH.Position = UDim2.new(0, 0, 0.5, 0)
    crossH.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    crossH.BackgroundTransparency = 0.7
    crossH.ZIndex = 4
    crossH.Parent = radarFrame

    local crossV = Instance.new("Frame")
    crossV.Size = UDim2.new(0, 1, 1, 0)
    crossV.Position = UDim2.new(0.5, 0, 0, 0)
    crossV.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    crossV.BackgroundTransparency = 0.7
    crossV.ZIndex = 4
    crossV.Parent = radarFrame

    -- 自己（中心空心圆环，不遮挡其他玩家的亮点）
    local centerDot = Instance.new("Frame")
    centerDot.Size = UDim2.fromOffset(12, 12)
    centerDot.Position = UDim2.new(0.5, -6, 0.5, -6)
    centerDot.BackgroundTransparency = 1
    centerDot.ZIndex = 6
    centerDot.Parent = radarFrame
    Instance.new("UICorner", centerDot).CornerRadius = UDim.new(1, 0)

    local centerStroke = Instance.new("UIStroke")
    centerStroke.Color = Color3.fromRGB(255, 255, 255)
    centerStroke.Thickness = 1.5
    centerStroke.Parent = centerDot

    -- ============ 放大/还原按钮（自适应到雷达对角） ============
    local zoomBtn = Instance.new("TextButton")
    zoomBtn.Name = "ZoomButton"
    zoomBtn.Size = UDim2.fromOffset(26, 26)
    zoomBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    zoomBtn.BackgroundTransparency = 0.2
    zoomBtn.Font = Enum.Font.GothamBold
    zoomBtn.Text = "+"
    zoomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    zoomBtn.TextSize = 16
    zoomBtn.ZIndex = 10
    zoomBtn.Parent = radarFrame
    Instance.new("UICorner", zoomBtn).CornerRadius = UDim.new(0, 6)

    -- ============ 亮点池（头像 + 名字/距离标签） ============
    local blips = {}
    for i = 1, BLIP_COUNT do
        local b = Instance.new("Frame")
        b.Size = UDim2.fromOffset(6, 6)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Visible = false
        b.ZIndex = 5
        b.Parent = radarFrame
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0, 130, 0, 14)
        label.AnchorPoint = Vector2.new(0.5, 1)
        label.Position = UDim2.new(0.5, 0, 0, -4)
        label.Font = Enum.Font.GothamBold
        label.Text = ""
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextSize = 11
        label.TextStrokeTransparency = 0.1
        label.RichText = true
        label.Visible = false
        label.ZIndex = 7
        label.Parent = b

        local avatar = Instance.new("ImageLabel")
        avatar.BackgroundTransparency = 1
        avatar.Size = UDim2.new(1, 0, 1, 0)
        avatar.Visible = false
        avatar.ZIndex = 6
        avatar.Parent = b
        Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

        table.insert(blips, { Frame = b, Label = label, Avatar = avatar })
    end

    -- ============ 范围滑块面板（放大时显示在屏幕右侧） ============
    local rangePanel = Instance.new("Frame")
    rangePanel.Name = "RangePanel"
    rangePanel.Size = UDim2.fromOffset(44, 300)
    rangePanel.AnchorPoint = Vector2.new(1, 0.5)
    rangePanel.Position = UDim2.new(1, -16, 0.5, 0)
    rangePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    rangePanel.BackgroundTransparency = 0.15
    rangePanel.Visible = false
    rangePanel.ZIndex = 8
    rangePanel.Parent = radarFrame
    Instance.new("UICorner", rangePanel).CornerRadius = UDim.new(0, 8)

    local rangeLabel = Instance.new("TextLabel")
    rangeLabel.BackgroundTransparency = 1
    rangeLabel.Size = UDim2.new(1, 0, 0, 22)
    rangeLabel.Font = Enum.Font.GothamBold
    rangeLabel.Text = "200m"
    rangeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    rangeLabel.TextSize = 13
    rangeLabel.ZIndex = 9
    rangeLabel.Parent = rangePanel

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 8, 0, 230)
    track.Position = UDim2.new(0.5, -4, 0, 32)
    track.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    track.ZIndex = 9
    track.Parent = rangePanel
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(1, 0, 0, 0)
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
    fill.ZIndex = 9
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local handle = Instance.new("TextButton")
    handle.Size = UDim2.fromOffset(24, 24)
    handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    handle.Text = ""
    handle.ZIndex = 10
    handle.Parent = rangePanel
    Instance.new("UICorner", handle).CornerRadius = UDim.new(1, 0)

    local dragging = false

    local function updateRangeSlider()
        local pct = (Settings.Range - RANGE_MIN) / (RANGE_MAX - RANGE_MIN)
        fill.Size = UDim2.new(1, 0, 0, 230 * pct)
        local handleY = 32 + pct * 230 - 12      -- 上 = 近距离，下 = 远距离
        handle.Position = UDim2.new(0.5, -12, 0, handleY)
        rangeLabel.Text = tostring(math.floor(Settings.Range)) .. "m"
    end

    local function setRangeFromScreenY(screenY)
        local trackPos = track.AbsolutePosition
        local pct = (screenY - trackPos.Y) / 230   -- 越往下越大 = 越远
        pct = math.clamp(pct, 0, 1)
        Settings.Range = math.floor(RANGE_MIN + (RANGE_MAX - RANGE_MIN) * pct)
        updateRangeSlider()
    end

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            pcall(setRangeFromScreenY, input.Position.Y)
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    updateRangeSlider()

    -- ============ 位置 / 圆角 / 缩放 ============
    local PositionMap = {
        ["左上"] = { AnchorPoint = Vector2.new(0, 0), Pos = UDim2.new(0, 12, 0, 12) },
        ["右上"] = { AnchorPoint = Vector2.new(1, 0), Pos = UDim2.new(1, -12, 0, 12) },
        ["左下"] = { AnchorPoint = Vector2.new(0, 1), Pos = UDim2.new(0, 12, 1, -12) },
        ["右下"] = { AnchorPoint = Vector2.new(1, 1), Pos = UDim2.new(1, -12, 1, -12) },
    }

    local ZOOM_BTN_POS = {
        ["左上"] = { Anchor = Vector2.new(1, 1), Pos = UDim2.new(1, -6, 1, -6) },
        ["右上"] = { Anchor = Vector2.new(0, 1), Pos = UDim2.new(0, 6, 1, -6) },
        ["左下"] = { Anchor = Vector2.new(1, 0), Pos = UDim2.new(1, -6, 0, 6) },
        ["右下"] = { Anchor = Vector2.new(0, 0), Pos = UDim2.new(0, 6, 0, 6) },
    }

    local function applyZoomBtnPos()
        if Settings.Zoomed then
            zoomBtn.AnchorPoint = Vector2.new(1, 0)
            zoomBtn.Position = UDim2.new(1, -6, 0, 6)
        else
            local d = ZOOM_BTN_POS[Settings.Position] or ZOOM_BTN_POS["右上"]
            zoomBtn.AnchorPoint = d.Anchor
            zoomBtn.Position = d.Pos
        end
    end

    local function applyPosition()
        if Settings.Zoomed then return end
        local data = PositionMap[Settings.Position]
        if not data then return end
        radarFrame.AnchorPoint = data.AnchorPoint
        radarFrame.Position = data.Pos
        applyZoomBtnPos()
    end

    local function applyCorner()
        local pct = math.clamp(Settings.Corner, 0, 100) / 100
        corner.CornerRadius = UDim.new(0, math.floor((RADAR_SIZE / 2) * pct))
    end

    local function applyZoom()
        if Settings.Zoomed then
            radarFrame.Size = UDim2.new(1, 0, 1, 0)
            radarFrame.AnchorPoint = Vector2.new(0, 0)
            radarFrame.Position = UDim2.new(0, 0, 0, 0)
            zoomBtn.Text = "-"
            rangePanel.Visible = Settings.Enabled
        else
            radarFrame.Size = UDim2.fromOffset(RADAR_SIZE, RADAR_SIZE)
            zoomBtn.Text = "+"
            rangePanel.Visible = false
            applyPosition()
        end
        applyZoomBtnPos()
    end

    local function setEnabled(v)
        Settings.Enabled = v and true or false
        radarFrame.Visible = Settings.Enabled
        if not Settings.Enabled then
            rangePanel.Visible = false
        elseif Settings.Zoomed then
            rangePanel.Visible = true
        end
    end

    zoomBtn.MouseButton1Click:Connect(function()
        Settings.Zoomed = not Settings.Zoomed
        pcall(applyZoom)
    end)

    -- ============ 好友缓存（每 5 秒刷新） ============
    local friendCache = {}
    local function refreshFriends()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                local ok, v = pcall(function()
                    return p:IsFriendsWith(lp.UserId)
                end)
                friendCache[p] = ok and v or false
            end
        end
    end

    pcall(refreshFriends)

    task.spawn(function()
        while true do
            pcall(refreshFriends)
            task.wait(5)
        end
    end)

    -- ============ 玩家头像缓存 ============
    local avatarCache = {}
    local function getAvatar(p)
        local cached = avatarCache[p]
        if cached == nil then
            avatarCache[p] = false
            task.spawn(function()
                local ok, url = pcall(function()
                    return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                end)
                avatarCache[p] = ok and url or false
            end)
        end
        return cached
    end

    -- ============ 每帧更新 ============
    local function updateRadar()
        local myChar = lp.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then
            for _, blip in ipairs(blips) do
                blip.Frame.Visible = false
                blip.Avatar.Visible = false
                blip.Label.Visible = false
            end
            return
        end

        local cf = myHrp.CFrame
        local right = cf.RightVector
        local look = cf.LookVector
        local myPos = myHrp.Position
        local myTeam = lp.Team

        local w = radarFrame.AbsoluteSize.X
        local h = radarFrame.AbsoluteSize.Y
        if w <= 0 or h <= 0 then return end

        local margin = Settings.Zoomed and 80 or 10
        local scaleX = (w / 2 - margin) / Settings.Range
        local scaleY = (h / 2 - margin) / Settings.Range
        local blipSize = Settings.Zoomed and 22 or 6
        local showLabels = Settings.Zoomed

        local idx = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local rel = hrp.Position - myPos
                    local dist = rel.Magnitude
                    if dist <= Settings.Range then
                        local isFriend = friendCache[p] or false
                        local sameTeam = myTeam ~= nil and p.Team == myTeam
                        local cat
                        if isFriend then
                            cat = "friend"
                        elseif sameTeam then
                            cat = "team"
                        elseif myTeam ~= nil and p.Team ~= nil then
                            cat = "enemy"
                        elseif myTeam ~= nil then
                            cat = "neutral"
                        else
                            cat = "enemy"
                        end

                        local show = (cat == "enemy" and Settings.ShowEnemy)
                            or (cat == "team" and Settings.ShowTeam)
                            or (cat == "friend" and Settings.ShowFriend)
                            or (cat == "neutral" and Settings.ShowNeutral)

                        if show then
                            idx = idx + 1
                            if idx > BLIP_COUNT then break end

                            local rx = rel:Dot(right)
                            local rz = rel:Dot(look)
                            local blip = blips[idx]
                            blip.Frame.Position = UDim2.new(0.5, rx * scaleX, 0.5, -rz * scaleY)
                            blip.Frame.Size = UDim2.fromOffset(blipSize, blipSize)
                            blip.Frame.BackgroundColor3 = CAT_COLORS[cat]
                            blip.Frame.Visible = true

                            blip.Label.RichText = true
                            blip.Label.Text = string.format(
                                '<font color="%s">%s</font>  <font color="#FFFFFF">%dm</font>',
                                colorToHex(CAT_COLORS[cat]),
                                p.Name,
                                math.floor(dist)
                            )
                            blip.Label.TextColor3 = Color3.fromRGB(255, 255, 255)
                            blip.Label.Visible = showLabels

                            local avatarUrl = showLabels and getAvatar(p) or nil
                            if avatarUrl then
                                blip.Avatar.Visible = true
                                blip.Avatar.Image = avatarUrl
                            else
                                blip.Avatar.Visible = false
                            end
                        end
                    end
                end
            end
        end

        for i = idx + 1, BLIP_COUNT do
            local blip = blips[i]
            blip.Frame.Visible = false
            blip.Avatar.Visible = false
            blip.Label.Visible = false
        end
    end

    RunService.Heartbeat:Connect(function()
        if Settings.Enabled then
            pcall(updateRadar)
        end
    end)

    applyPosition()
    applyCorner()
    applyZoom()
    setEnabled(Settings.Enabled)

    return {
        ApplyPosition = applyPosition,
        ApplyCorner = applyCorner,
        ApplyZoom = applyZoom,
        SetEnabled = setEnabled,
    }
end)

if not okOverlay then
    warn("[雷达] 雷达覆盖层创建失败:", errOverlay)
    return
end

local Radar = errOverlay

-- ============ UI 控件（加到主脚本提供的 Tab 里） ============
local okUI, errUI = pcall(function()
    Tab:Toggle({
        Title = "启用雷达",
        Desc = "默认关闭，开启后显示",
        Value = Settings.Enabled,
        Callback = function(v)
            pcall(Radar.SetEnabled, v)
        end,
    })

    Tab:Dropdown({
        Title = "显示位置",
        Desc = "雷达放在哪个角",
        Values = { "左上", "右上", "左下", "右下" },
        Value = Settings.Position,
        Callback = function(v)
            Settings.Position = v
            pcall(Radar.ApplyPosition)
        end,
    })

    Tab:Slider({
        Title = "圆角程度",
        Desc = "越高越圆，100 为圆形",
        Step = 1,
        Value = { Min = 0, Max = 100, Default = Settings.Corner },
        Callback = function(v)
            Settings.Corner = v
            pcall(Radar.ApplyCorner)
        end,
    })

    Tab:Button({
        Title = "放大/还原雷达",
        Desc = "和雷达上的 +/- 按钮一样",
        Callback = function()
            Settings.Zoomed = not Settings.Zoomed
            pcall(Radar.ApplyZoom)
        end,
    })

    Tab:Toggle({
        Title = "显示敌人",
        Desc = "红色亮点",
        Value = Settings.ShowEnemy,
        Callback = function(v)
            Settings.ShowEnemy = v
        end,
    })

    Tab:Toggle({
        Title = "显示队友",
        Desc = "绿色亮点",
        Value = Settings.ShowTeam,
        Callback = function(v)
            Settings.ShowTeam = v
        end,
    })

    Tab:Toggle({
        Title = "显示好友",
        Desc = "黄色亮点",
        Value = Settings.ShowFriend,
        Callback = function(v)
            Settings.ShowFriend = v
        end,
    })

    Tab:Toggle({
        Title = "显示中立",
        Desc = "灰色亮点",
        Value = Settings.ShowNeutral,
        Callback = function(v)
            Settings.ShowNeutral = v
        end,
    })
end)

if not okUI then
    warn("[雷达] Tab UI 创建失败:", errUI)
else
    print("[雷达] 远程脚本加载完成")
end
