-- 服务器类 独立测试脚本
-- 用法：复制进注入器执行（不需要主脚本）
-- 功能：自动换服 / 人数最多服务器 / 人数最少服务器 / 随机服务器 / 管理员监测
-- 测试没问题后，再做成远程脚本格式

local WindUI = _G.WindUI
if not WindUI then
    local ok, res = pcall(function()
        if not loadstring then
            error("当前环境没有 loadstring（可能不是注入器而是 Studio），无法加载 WindUI")
        end
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
    _G.WindUI = WindUI
end

local win = WindUI:CreateWindow({
    Title = "服务器测试",
    Icon = "aperture",
    Author = "suif",
    Folder = "ServerTest",
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

local srvSection = win:Section({ Title = "服务器类", Icon = "folder", Locked = false })
local Tab = srvSection:Tab({ Title = "服务器", Icon = "user", Locked = false })
Tab:Select()

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local PlaceId = game.PlaceId
local CurrentJob = game.JobId

-- ===== 配置 =====
local ServerConfig = {
    Mode = "随机",
    AutoEnabled = false,
    AutoInterval = 60,
    AdminEnabled = false,
    AdminInterval = 10,
    KeywordCheck = false,
}

local statusText
local adminListText
local browserServers = {}
local UIS = game:GetService("UserInputService")
local ServerUI = { Root = nil }
local listFrame = nil
local statusLabel = nil
local searchBox = nil
local refreshBtn = nil
local lastBrowserFetch = 0

local function notify(title, content, icon, duration)
    pcall(function()
        WindUI:Notify({
            Title = title,
            Content = content or "",
            Icon = icon or "bell",
            Duration = duration or 3,
        })
    end)
end

local function setStatus(text)
    if statusText and statusText.SetDesc then
        statusText:SetDesc(text)
    end
end

local function unwrap(v)
    if type(v) == "table" then
        return v.Value or v[1]
    end
    return v
end

-- ===== 服务器列表获取 =====
-- sortOrder: Asc = 人数最少在前, Desc = 人数最多在前
local function fetchServers(sortOrder)
    local url = "https://games.roblox.com/v1/games/"
        .. PlaceId
        .. "/servers/Public?limit=100&sortOrder="
        .. sortOrder

    local data = HttpService:JSONDecode(game:HttpGet(url))
    local list = {}
    for _, s in ipairs(data.data or {}) do
        -- 过滤掉当前服务器和已满的服务器
        if s.id and s.id ~= CurrentJob and s.playing < s.maxPlayers then
            table.insert(list, s)
        end
    end
    return list
end

local function pickServer(mode)
    if mode == "人数最多" then
        local list = fetchServers("Desc")
        return list[1]
    elseif mode == "人数最少" then
        local list = fetchServers("Asc")
        return list[1]
    else
        local list = fetchServers("Desc")
        if #list == 0 then return nil end
        return list[math.random(1, #list)]
    end
end

local function doSwitch(mode)
    task.spawn(function()
        local ok, server = pcall(pickServer, mode)
        if not ok then
            setStatus("获取服务器列表失败: " .. tostring(server))
            notify("换服失败", "获取服务器列表失败", "alert-triangle", 4)
            return
        end
        if not server then
            setStatus("没有可用的服务器")
            notify("换服失败", "没有可用的服务器", "alert-triangle", 4)
            return
        end

        setStatus("正在加入 " .. mode .. " 服务器，在线 "
            .. server.playing .. "/" .. server.maxPlayers)
        notify("正在换服", "在线 " .. server.playing .. "/" .. server.maxPlayers, "arrow-right", 3)
        task.wait(0.5)
        TeleportService:TeleportToPlaceInstance(PlaceId, server.id)
    end)
end

-- ===== 服务器浏览器：拉取全部服务器 =====
local function fetchAllServers()
    local all = {}
    local cursor = nil

    for page = 1, 20 do
        local url = "https://games.roblox.com/v1/games/"
            .. PlaceId
            .. "/servers/Public?limit=100&sortOrder=Desc"
        if cursor then
            url = url .. "&cursor=" .. cursor
        end

        local data = HttpService:JSONDecode(game:HttpGet(url))
        for _, s in ipairs(data.data or {}) do
            -- 过滤掉当前服务器和已满的服务器
            if s.id and s.id ~= CurrentJob and s.playing < s.maxPlayers then
                table.insert(all, s)
            end
        end

        cursor = data.nextPageCursor
        setStatus("正在获取服务器... 第 " .. page .. " 页（已获取 " .. #all .. " 个）")
        if not cursor then break end
        task.wait(0.4)
    end

    -- 按在线人数从多到少排序
    table.sort(all, function(a, b)
        return (a.playing or 0) > (b.playing or 0)
    end)
    return all
end

-- ===== 自定义服务器列表界面（适配手机） =====
local listMode = "servers" -- servers / players
local modeServersBtn = nil
local modePlayersBtn = nil
local refreshing = false
local infoPanel = nil
local infoMain = nil
local infoSub = nil

local function clearRows()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
end

local function makeRow(primary, secondary, dotColor, onClick)
    local row = Instance.new("Frame")
    row.Name = "Row"
    row.Size = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
    row.BorderSizePixel = 0
    row.Parent = listFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", row)
    stroke.Color = Color3.fromRGB(48, 52, 64)
    stroke.Thickness = 1

    if dotColor then
        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(10, 10)
        dot.Position = UDim2.new(0, 14, 0.5, -5)
        dot.BackgroundColor3 = dotColor
        dot.BorderSizePixel = 0
        dot.Parent = row
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    end

    local prim = Instance.new("TextLabel")
    prim.Size = UDim2.new(1, -160, 1, 0)
    prim.Position = UDim2.new(0, dotColor and 32 or 14, 0, 0)
    prim.BackgroundTransparency = 1
    prim.Font = Enum.Font.GothamBold
    prim.TextSize = 15
    prim.TextColor3 = Color3.fromRGB(235, 238, 245)
    prim.TextXAlignment = Enum.TextXAlignment.Left
    prim.Text = primary
    prim.Parent = row

    if secondary then
        local sec = Instance.new("TextLabel")
        sec.Size = UDim2.new(0, 160, 1, 0)
        sec.Position = UDim2.new(1, -168, 0, 0)
        sec.BackgroundTransparency = 1
        sec.Font = Enum.Font.Gotham
        sec.TextSize = 13
        sec.TextColor3 = Color3.fromRGB(140, 148, 165)
        sec.TextXAlignment = Enum.TextXAlignment.Right
        sec.Text = secondary
        sec.Parent = row
    end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.Parent = row

    local function press(active)
        row.BackgroundColor3 = active
            and Color3.fromRGB(44, 48, 62)
            or Color3.fromRGB(30, 32, 40)
    end
    btn.MouseEnter:Connect(function() press(true) end)
    btn.MouseLeave:Connect(function() press(false) end)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            press(true)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            press(false)
        end
    end)
    if onClick then
        btn.Activated:Connect(function()
            onClick()
        end)
    end
end

local function buildServersRows()
    local query = searchBox.Text:lower()
    local shown = 0
    for _, s in ipairs(browserServers) do
        local id = tostring(s.id):lower()
        if query == "" or id:find(query, 1, true) then
            local ratio = s.maxPlayers > 0 and (s.playing / s.maxPlayers) or 0
            local dotColor = Color3.fromHSV((1 - ratio) * 0.35, 0.75, 1)
            local secondary = tostring(s.id):sub(1, 8)
            if type(s.ping) == "number" then
                secondary = secondary .. " · " .. math.floor(s.ping) .. "ms"
            end
            local server = s
            makeRow(s.playing .. " / " .. s.maxPlayers, secondary, dotColor, function()
                statusLabel.Text = "正在加入 " .. tostring(server.id) .. "（在线 " .. server.playing .. "/" .. server.maxPlayers .. "）..."
                notify("正在加入", "在线 " .. server.playing .. "/" .. server.maxPlayers, "arrow-right", 3)
                TeleportService:TeleportToPlaceInstance(PlaceId, server.id)
            end)
            shown = shown + 1
            if shown >= 800 then break end
        end
    end
    listFrame.CanvasSize = UDim2.new(0, 0, 0, shown * 52 + 4)

    if #browserServers == 0 then
        statusLabel.Text = "当前没有可用的公开服务器"
    elseif shown == 0 then
        statusLabel.Text = "没有匹配「" .. searchBox.Text .. "」的服务器"
    else
        local suffix = ""
        if searchBox.Text ~= "" then suffix = "（筛选结果）" end
        statusLabel.Text = "共 " .. #browserServers .. " 个可用服务器，显示前 " .. shown .. " 个" .. suffix
            .. " · " .. os.date("%H:%M:%S") .. " · 30秒自动刷新"
    end
end

local function buildPlayersRows()
    local players = Players:GetPlayers()
    table.sort(players, function(a, b)
        return (a.DisplayName or a.Name) < (b.DisplayName or b.Name)
    end)

    local lp = Players.LocalPlayer
    local pingMs = 0
    pcall(function()
        pingMs = math.floor(lp:GetNetworkPing() * 1000)
    end)
    if infoMain then
        infoMain.Text = "本服在线 " .. #players .. " / " .. Players.MaxPlayers .. "   ·   你的Ping " .. pingMs .. "ms"
    end
    if infoSub then
        infoSub.Text = "房间ID: " .. (game.JobId or "无") .. "   ·   游戏: " .. game.Name
    end

    for _, p in ipairs(players) do
        local isMe = p == Players.LocalPlayer
        local dotColor = isMe
            and Color3.fromRGB(64, 130, 255)
            or Color3.fromRGB(95, 103, 120)
        local plr = p
        makeRow(
            p.DisplayName .. (isMe and "  (你)" or ""),
            "@" .. p.Name .. " · UID " .. p.UserId .. " · 账号" .. p.AccountAge .. "天",
            dotColor,
            function()
            pcall(function()
                if setclipboard then
                    setclipboard(plr.Name)
                    statusLabel.Text = "已复制 " .. plr.Name .. " 到剪贴板"
                else
                    statusLabel.Text = "当前执行器不支持复制"
                end
            end)
            end
        )
    end
    listFrame.CanvasSize = UDim2.new(0, 0, 0, #players * 52 + 4)
    statusLabel.Text = "当前服务器玩家 " .. #players .. " 人 · 点击玩家复制用户名 · 30秒自动刷新"
end

local function rebuildList()
    clearRows()
    if infoPanel then
        infoPanel.Visible = (listMode == "players")
        if listMode == "players" then
            listFrame.Position = UDim2.new(0, 12, 0, 250)
            listFrame.Size = UDim2.new(1, -24, 1, -292)
        else
            listFrame.Position = UDim2.new(0, 12, 0, 154)
            listFrame.Size = UDim2.new(1, -24, 1, -196)
        end
    end
    if listMode == "players" then
        buildPlayersRows()
    else
        buildServersRows()
    end
    if modeServersBtn then
        modeServersBtn.BackgroundColor3 = listMode == "servers"
            and Color3.fromRGB(58, 116, 255)
            or Color3.fromRGB(30, 32, 40)
        modePlayersBtn.BackgroundColor3 = listMode == "players"
            and Color3.fromRGB(58, 116, 255)
            or Color3.fromRGB(30, 32, 40)
    end
end

local function uiRefresh()
    if not refreshBtn then return end
    if listMode == "players" then
        rebuildList()
        return
    end
    if refreshing then return end
    refreshing = true
    refreshBtn.Text = "获取中..."
    statusLabel.Text = "正在获取服务器列表（30秒自动刷新）..."
    task.spawn(function()
        local ok, list = pcall(fetchAllServers)
        refreshing = false
        refreshBtn.Text = "刷新"
        if not ok then
            statusLabel.Text = "获取失败: " .. tostring(list)
            return
        end
        browserServers = list
        lastBrowserFetch = os.clock()
        rebuildList()
        notify("服务器列表", "找到 " .. #list .. " 个可用服务器", "check", 3)
    end)
end

local function createServerUI()
    if ServerUI.Root then
        ServerUI.Root.Visible = true
        rebuildList()
        return
    end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ServerBrowserUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local parented = pcall(function()
        ScreenGui.Parent = game:GetService("CoreGui")
    end)
    if not parented then
        ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    local cam = workspace.CurrentCamera
    local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local winW = math.clamp(viewport.X - 24, 300, 560)
    local winH = math.clamp(viewport.Y - 36, 400, 760)

    local root = Instance.new("Frame")
    root.Name = "Main"
    root.Size = UDim2.fromOffset(winW, winH)
    root.Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2)
    root.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    root.BorderSizePixel = 0
    root.Parent = ScreenGui
    Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", root)
    stroke.Color = Color3.fromRGB(58, 64, 82)
    stroke.Thickness = 2

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 46)
    titleBar.BackgroundColor3 = Color3.fromRGB(48, 84, 220)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = root
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    local headerGradient = Instance.new("UIGradient", titleBar)
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 84, 220)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 64, 210)),
    })
    headerGradient.Rotation = 90

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -130, 1, 0)
    titleLabel.Position = UDim2.new(0, 14, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 17
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "服务器列表"
    titleLabel.Parent = titleBar

    refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 70, 0, 32)
    refreshBtn.Position = UDim2.new(1, -116, 0.5, -16)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    refreshBtn.BackgroundTransparency = 0.15
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Font = Enum.Font.Gotham
    refreshBtn.TextSize = 15
    refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshBtn.Text = "刷新"
    refreshBtn.Parent = titleBar
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 10)
    refreshBtn.Activated:Connect(uiRefresh)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 38, 0, 32)
    closeBtn.Position = UDim2.new(1, -46, 0.5, -16)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.BackgroundTransparency = 0.15
    closeBtn.BorderSizePixel = 0
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 15
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Text = "x"
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
    closeBtn.MouseEnter:Connect(function()
        closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 80)
        closeBtn.BackgroundTransparency = 0
    end)
    closeBtn.MouseLeave:Connect(function()
        closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        closeBtn.BackgroundTransparency = 0.15
    end)
    closeBtn.Activated:Connect(function()
        ServerUI.Root.Visible = false
    end)

    -- 拖动窗口
    local dragging = false
    local dragOffset = Vector2.zero
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local pos = input.Position
            if typeof(pos) == "Vector3" then
                pos = Vector2.new(pos.X, pos.Y)
            end
            dragOffset = pos - root.AbsolutePosition
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
        if input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Delta
            root.Position = UDim2.fromOffset(
                math.clamp(root.AbsolutePosition.X + delta.X, -root.AbsoluteSize.X + 80, vp.X - 80),
                math.clamp(root.AbsolutePosition.Y + delta.Y, 0, vp.Y - 50)
            )
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = input.Position
            if typeof(pos) == "Vector3" then
                pos = Vector2.new(pos.X, pos.Y)
            end
            local newPos = pos - dragOffset
            root.Position = UDim2.fromOffset(
                math.clamp(newPos.X, -root.AbsoluteSize.X + 80, vp.X - 80),
                math.clamp(newPos.Y, 0, vp.Y - 50)
            )
        end
    end)

    searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -24, 0, 40)
    searchBox.Position = UDim2.new(0, 12, 0, 56)
    searchBox.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
    searchBox.BorderSizePixel = 0
    searchBox.PlaceholderText = "搜索服务器ID...（回车应用）"
    searchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 145)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 15
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = root
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 10)
    local searchStroke = Instance.new("UIStroke", searchBox)
    searchStroke.Color = Color3.fromRGB(48, 52, 64)
    searchStroke.Thickness = 1
    searchBox.FocusLost:Connect(function()
        if listMode == "servers" then
            rebuildList()
        end
    end)

    -- 模式切换：服务器列表 / 当前服玩家
    modeServersBtn = Instance.new("TextButton")
    modeServersBtn.Size = UDim2.new(0.5, -10, 0, 38)
    modeServersBtn.Position = UDim2.new(0, 12, 0, 106)
    modeServersBtn.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
    modeServersBtn.BorderSizePixel = 0
    modeServersBtn.Font = Enum.Font.GothamBold
    modeServersBtn.TextSize = 15
    modeServersBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    modeServersBtn.Text = "服务器列表"
    modeServersBtn.Parent = root
    Instance.new("UICorner", modeServersBtn).CornerRadius = UDim.new(0, 10)
    local msStroke = Instance.new("UIStroke", modeServersBtn)
    msStroke.Color = Color3.fromRGB(58, 116, 255)
    msStroke.Thickness = 1
    modeServersBtn.Activated:Connect(function()
        listMode = "servers"
        rebuildList()
    end)

    modePlayersBtn = Instance.new("TextButton")
    modePlayersBtn.Size = UDim2.new(0.5, -10, 0, 38)
    modePlayersBtn.Position = UDim2.new(0.5, 2, 0, 106)
    modePlayersBtn.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
    modePlayersBtn.BorderSizePixel = 0
    modePlayersBtn.Font = Enum.Font.GothamBold
    modePlayersBtn.TextSize = 15
    modePlayersBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    modePlayersBtn.Text = "当前服玩家"
    modePlayersBtn.Parent = root
    Instance.new("UICorner", modePlayersBtn).CornerRadius = UDim.new(0, 10)
    local mpStroke = Instance.new("UIStroke", modePlayersBtn)
    mpStroke.Color = Color3.fromRGB(58, 116, 255)
    mpStroke.Thickness = 1
    modePlayersBtn.Activated:Connect(function()
        listMode = "players"
        rebuildList()
    end)

    -- 本服信息面板（仅当前服玩家模式显示）
    infoPanel = Instance.new("Frame")
    infoPanel.Name = "InfoPanel"
    infoPanel.Size = UDim2.new(1, -24, 0, 84)
    infoPanel.Position = UDim2.new(0, 12, 0, 154)
    infoPanel.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
    infoPanel.BorderSizePixel = 0
    infoPanel.Visible = false
    infoPanel.Parent = root
    Instance.new("UICorner", infoPanel).CornerRadius = UDim.new(0, 10)
    local infoStroke = Instance.new("UIStroke", infoPanel)
    infoStroke.Color = Color3.fromRGB(58, 64, 82)
    infoStroke.Thickness = 1

    infoMain = Instance.new("TextLabel")
    infoMain.Size = UDim2.new(1, -20, 0, 40)
    infoMain.Position = UDim2.new(0, 10, 0, 8)
    infoMain.BackgroundTransparency = 1
    infoMain.Font = Enum.Font.GothamBold
    infoMain.TextSize = 15
    infoMain.TextColor3 = Color3.fromRGB(235, 238, 245)
    infoMain.TextXAlignment = Enum.TextXAlignment.Left
    infoMain.TextYAlignment = Enum.TextYAlignment.Center
    infoMain.Text = "本服在线 - / -"
    infoMain.Parent = infoPanel

    infoSub = Instance.new("TextLabel")
    infoSub.Size = UDim2.new(1, -20, 0, 26)
    infoSub.Position = UDim2.new(0, 10, 0, 48)
    infoSub.BackgroundTransparency = 1
    infoSub.Font = Enum.Font.Gotham
    infoSub.TextSize = 13
    infoSub.TextColor3 = Color3.fromRGB(150, 158, 175)
    infoSub.TextXAlignment = Enum.TextXAlignment.Left
    infoSub.Text = "房间ID: -"
    infoSub.Parent = infoPanel

    listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, -24, 1, -196)
    listFrame.Position = UDim2.new(0, 12, 0, 154)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 6
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
    listFrame.ScrollBarImageTransparency = 0.4
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.Parent = root
    local layout = Instance.new("UIListLayout", listFrame)
    layout.Padding = UDim.new(0, 6)

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 30)
    statusLabel.Position = UDim2.new(0, 12, 1, -38)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Text = "等待刷新"
    statusLabel.Parent = root

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Escape and ServerUI.Root and ServerUI.Root.Visible then
            ServerUI.Root.Visible = false
        end
    end)

    ServerUI.Root = root
    rebuildList()

    -- 30 秒自动刷新（窗口可见时）
    task.spawn(function()
        while true do
            task.wait(30)
            if ServerUI.Root and ServerUI.Root.Visible then
                if listMode == "players" then
                    rebuildList()
                else
                    uiRefresh()
                end
            end
        end
    end)
end

local function openServerBrowser()
    createServerUI()
    if os.clock() - lastBrowserFetch > 30 or #browserServers == 0 then
        uiRefresh()
    else
        rebuildList()
    end
end

-- ===== 自动换服 =====
local autoTask = nil

local function stopAuto()
    ServerConfig.AutoEnabled = false
    if autoTask then
        task.cancel(autoTask)
        autoTask = nil
    end
end

local function startAuto()
    ServerConfig.AutoEnabled = true
    autoTask = task.spawn(function()
        while ServerConfig.AutoEnabled do
            task.wait(ServerConfig.AutoInterval)
            if ServerConfig.AutoEnabled then
                doSwitch(ServerConfig.Mode)
                break
            end
        end
    end)
end

-- ===== 管理员监测 =====
local detected = {}

local function checkAdmin(p)
    if not p or not p.Parent then return end
    local uid = p.UserId
    if detected[uid] then return true end

    local reasons = {}

    -- 1. 游戏创建者（个人创建的游戏的拥有者）
    pcall(function()
        if game.CreatorType == Enum.CreatorType.User and p.UserId == game.CreatorId then
            table.insert(reasons, "游戏创建者")
        end
    end)

    -- 2. 群组高Rank（等级 200 以上，一般对应管理员/拥有者）
    pcall(function()
        for _, g in ipairs(p:GetGroups()) do
            if g.Rank and g.Rank >= 200 then
                table.insert(reasons, "群组高Rank(" .. (g.Name or "?") .. " Lv" .. g.Rank .. ")")
                break
            end
        end
    end)

    -- 3. 名字关键字（可选，可能误报）
    if ServerConfig.KeywordCheck then
        local keywords = { "admin", "owner", "moderator", "mod", "staff", "gm", "管理员", "官方", "客服", "开发者" }
        local name = (p.Name .. " " .. p.DisplayName):lower()
        for _, kw in ipairs(keywords) do
            if name:find(kw) then
                table.insert(reasons, "名字含" .. kw)
                break
            end
        end
    end

    if #reasons > 0 then
        detected[uid] = { Name = p.DisplayName or p.Name, Reasons = reasons }
        notify("检测到管理员", (p.DisplayName or p.Name) .. " - " .. table.concat(reasons, "、"), "alert-triangle", 4)
        return true
    end
    return false
end

local function updateAdminList()
    if not adminListText or not adminListText.SetDesc then return end
    if not ServerConfig.AdminEnabled then
        adminListText:SetDesc("未开启")
        return
    end

    local lines = {}
    for uid, info in pairs(detected) do
        table.insert(lines, info.Name .. " - " .. table.concat(info.Reasons, "、"))
    end
    if #lines == 0 then
        adminListText:SetDesc("暂未检测到管理员")
    else
        adminListText:SetDesc(table.concat(lines, "\n"))
    end
end

local adminTask = nil

local function stopAdmin()
    ServerConfig.AdminEnabled = false
    if adminTask then
        task.cancel(adminTask)
        adminTask = nil
    end
    updateAdminList()
end

local function startAdmin()
    ServerConfig.AdminEnabled = true
    updateAdminList()
    adminTask = task.spawn(function()
        while ServerConfig.AdminEnabled do
            for _, p in ipairs(Players:GetPlayers()) do
                checkAdmin(p)
            end
            updateAdminList()
            task.wait(ServerConfig.AdminInterval)
        end
    end)
end

Players.PlayerAdded:Connect(function(p)
    if ServerConfig.AdminEnabled then
        task.spawn(function()
            task.wait(1)
            checkAdmin(p)
            updateAdminList()
        end)
    end
end)

Players.PlayerRemoving:Connect(function(p)
    detected[p.UserId] = nil
    updateAdminList()
end)

-- ===== UI =====
local uiOk, uiErr = pcall(function()
    local srvSec = Tab:Section({ Title = "换服", Icon = "folder", Opened = true })
    local admSec = Tab:Section({ Title = "管理员监测", Icon = "user", Opened = true })

    -- 换服
    srvSec:Dropdown({
        Title = "换服模式",
        Values = { "随机", "人数最多", "人数最少" },
        Value = ServerConfig.Mode,
        Callback = function(v)
            ServerConfig.Mode = unwrap(v)
        end
    })

    srvSec:Button({
        Title = "立即换服",
        Desc = "按上方模式切换服务器",
        Icon = "shell",
        Callback = function()
            doSwitch(ServerConfig.Mode)
        end
    })

    srvSec:Button({
        Title = "加入人数最多服务器",
        Icon = "check",
        Callback = function()
            doSwitch("人数最多")
        end
    })

    srvSec:Button({
        Title = "加入人数最少服务器",
        Icon = "activity",
        Callback = function()
            doSwitch("人数最少")
        end
    })

    srvSec:Button({
        Title = "随机加入服务器",
        Icon = "user",
        Callback = function()
            doSwitch("随机")
        end
    })

    srvSec:Button({
        Title = "打开服务器列表",
        Desc = "打开自定义服务器浏览器，点击列表中的服务器即可加入",
        Icon = "shell",
        Callback = function()
            openServerBrowser()
        end
    })

    srvSec:Toggle({
        Title = "自动换服",
        Desc = "按下方间隔自动切换服务器（切换后需重新执行本脚本）",
        Type = "Checkbox",
        Value = ServerConfig.AutoEnabled,
        Callback = function(s)
            if s then
                startAuto()
            else
                stopAuto()
            end
        end
    })

    srvSec:Slider({
        Title = "换服间隔(秒)",
        Step = 5,
        Value = { Min = 30, Max = 600, Default = ServerConfig.AutoInterval },
        Callback = function(v)
            ServerConfig.AutoInterval = tonumber(v) or 60
        end
    })

    statusText = srvSec:Paragraph({ Title = "状态", Desc = "等待操作" })

    -- 管理员监测
    admSec:Toggle({
        Title = "自动监测管理员",
        Desc = "检测游戏创建者 / 群组高Rank / 名字关键字",
        Type = "Checkbox",
        Value = ServerConfig.AdminEnabled,
        Callback = function(s)
            if s then
                startAdmin()
            else
                stopAdmin()
            end
        end
    })

    admSec:Slider({
        Title = "检测间隔(秒)",
        Step = 1,
        Value = { Min = 5, Max = 60, Default = ServerConfig.AdminInterval },
        Callback = function(v)
            ServerConfig.AdminInterval = tonumber(v) or 10
        end
    })

    admSec:Toggle({
        Title = "名字关键字检测",
        Desc = "名字含 admin/管理员/官方 等关键字会标记（可能误报）",
        Type = "Checkbox",
        Value = ServerConfig.KeywordCheck,
        Callback = function(s)
            ServerConfig.KeywordCheck = s
        end
    })

    admSec:Button({
        Title = "清空检测记录",
        Icon = "folder",
        Callback = function()
            detected = {}
            updateAdminList()
        end
    })

    adminListText = admSec:Paragraph({ Title = "检测到的管理员", Desc = "未开启" })
end)

if not uiOk then
    warn("[服务器] UI 创建失败:", uiErr)
else
    print("[服务器] 独立测试脚本加载完成")
    notify("服务器类", "加载完成", "aperture", 3)
end
