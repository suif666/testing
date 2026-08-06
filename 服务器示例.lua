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

-- ===== 自定义服务器列表界面（参考 Suture UI 示例） =====
local refreshing = false
local currentInfo = nil
local currentPlayers = nil
local TweenService = game:GetService("TweenService")

local function clearRows()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

local function createCurrentCard()
    local card = Instance.new("Frame")
    card.Name = "CurrentCard"
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    card.BorderSizePixel = 0
    card.Parent = listFrame
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color = Color3.fromRGB(38, 38, 48)
    stroke.Thickness = 1
    local pad = Instance.new("UIPadding", card)
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    local layout = Instance.new("UIListLayout", card)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)

    local cap = Instance.new("TextLabel")
    cap.Size = UDim2.new(1, 0, 0, 18)
    cap.BackgroundTransparency = 1
    cap.Text = "当前服务器"
    cap.TextColor3 = Color3.fromRGB(150, 150, 170)
    cap.TextSize = 12
    cap.Font = Enum.Font.GothamMedium
    cap.TextXAlignment = Enum.TextXAlignment.Left
    cap.Parent = card

    currentInfo = Instance.new("TextLabel")
    currentInfo.Size = UDim2.new(1, 0, 0, 0)
    currentInfo.AutomaticSize = Enum.AutomaticSize.Y
    currentInfo.BackgroundTransparency = 1
    currentInfo.Text = "人数: - / -\n你的Ping: -ms\n房间ID: -\n游戏: -"
    currentInfo.TextColor3 = Color3.fromRGB(220, 220, 230)
    currentInfo.TextSize = 14
    currentInfo.Font = Enum.Font.Gotham
    currentInfo.TextXAlignment = Enum.TextXAlignment.Left
    currentInfo.TextYAlignment = Enum.TextYAlignment.Top
    currentInfo.Parent = card

    local pcap = Instance.new("TextLabel")
    pcap.Size = UDim2.new(1, 0, 0, 18)
    pcap.BackgroundTransparency = 1
    pcap.Text = "服务器玩家"
    pcap.TextColor3 = Color3.fromRGB(140, 140, 155)
    pcap.TextSize = 12
    pcap.Font = Enum.Font.GothamMedium
    pcap.TextXAlignment = Enum.TextXAlignment.Left
    pcap.Parent = card

    currentPlayers = Instance.new("TextLabel")
    currentPlayers.Size = UDim2.new(1, 0, 0, 0)
    currentPlayers.AutomaticSize = Enum.AutomaticSize.Y
    currentPlayers.BackgroundTransparency = 1
    currentPlayers.Text = "加载中..."
    currentPlayers.TextColor3 = Color3.fromRGB(200, 200, 210)
    currentPlayers.TextSize = 13
    currentPlayers.Font = Enum.Font.Gotham
    currentPlayers.TextXAlignment = Enum.TextXAlignment.Left
    currentPlayers.TextWrapped = true
    currentPlayers.Parent = card
end

local function createSectionTitle(text)
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 22)
    title.BackgroundTransparency = 1
    title.Text = text
    title.TextColor3 = Color3.fromRGB(160, 160, 175)
    title.TextSize = 13
    title.Font = Enum.Font.GothamMedium
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = listFrame
end

local function createServerCard(server, recommended)
    local card = Instance.new("Frame")
    card.Name = "ServerCard"
    card.Size = UDim2.new(1, 0, 0, 64)
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    card.BorderSizePixel = 0
    card.Parent = listFrame
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color = recommended and Color3.fromRGB(108, 92, 231) or Color3.fromRGB(38, 38, 48)
    stroke.Thickness = 1

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0.62, 0, 0, 20)
    nameLabel.Position = UDim2.new(0, 16, 0, 12)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "服务器 " .. tostring(server.id):sub(1, 8) .. (recommended and " · 推荐" or "")
    nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = card

    local infoText = string.format("人数: %d / %d", server.playing, server.maxPlayers)
    if type(server.ping) == "number" then
        infoText = infoText .. string.format("   Ping: %dms", math.floor(server.ping))
    end
    if server.region then
        infoText = infoText .. "   地区: " .. tostring(server.region)
    end
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(0.72, 0, 0, 18)
    infoLabel.Position = UDim2.new(0, 16, 0, 34)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = infoText
    infoLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
    infoLabel.TextSize = 12
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.Parent = card

    local joinBtn = Instance.new("TextButton")
    joinBtn.Size = UDim2.new(0, 72, 0, 32)
    joinBtn.Position = UDim2.new(1, -88, 0.5, -16)
    joinBtn.BackgroundColor3 = Color3.fromRGB(108, 92, 231)
    joinBtn.BorderSizePixel = 0
    joinBtn.Text = "加入"
    joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    joinBtn.TextSize = 13
    joinBtn.Font = Enum.Font.GothamBold
    joinBtn.Parent = card
    Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 8)
    joinBtn.MouseEnter:Connect(function()
        TweenService:Create(joinBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(130, 110, 245) }):Play()
    end)
    joinBtn.MouseLeave:Connect(function()
        TweenService:Create(joinBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(108, 92, 231) }):Play()
    end)
    joinBtn.Activated:Connect(function()
        statusLabel.Text = "正在加入 " .. tostring(server.id) .. "（在线 " .. server.playing .. "/" .. server.maxPlayers .. "）..."
        notify("正在加入", "在线 " .. server.playing .. "/" .. server.maxPlayers, "arrow-right", 3)
        TeleportService:TeleportToPlaceInstance(PlaceId, server.id)
    end)
end

local function buildCurrentInfo()
    if not currentInfo or not currentPlayers then return end
    local players = Players:GetPlayers()
    local lp = Players.LocalPlayer
    local pingMs = 0
    pcall(function()
        pingMs = math.floor(lp:GetNetworkPing() * 1000)
    end)
    currentInfo.Text = "人数: " .. #players .. " / " .. Players.MaxPlayers
        .. "\n你的Ping: " .. pingMs .. "ms"
        .. "\n房间ID: " .. (game.JobId or "无")
        .. "\n游戏: " .. game.Name
    local names = {}
    for _, p in ipairs(players) do
        table.insert(names, p.DisplayName)
    end
    if #names == 0 then
        currentPlayers.Text = "只有你一个人"
    else
        currentPlayers.Text = table.concat(names, ", ")
    end
end

local function buildList()
    clearRows()
    createCurrentCard()
    buildCurrentInfo()
    createSectionTitle("其他服务器")

    local query = searchBox.Text:lower()
    local shown = 0
    local recommended = nil
    for _, s in ipairs(browserServers) do
        if not recommended or s.playing < recommended.playing then
            recommended = s
        end
    end
    for _, s in ipairs(browserServers) do
        local id = tostring(s.id):lower()
        if query == "" or id:find(query, 1, true) then
            createServerCard(s, #browserServers > 1 and s == recommended)
            shown = shown + 1
            if shown >= 800 then break end
        end
    end

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

local function uiRefresh()
    if not refreshBtn then return end
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
        buildList()
        notify("服务器列表", "找到 " .. #list .. " 个可用服务器", "check", 3)
    end)
end

local function createServerUI()
    if ServerUI.Root then
        ServerUI.Root.Visible = true
        buildList()
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
    local winH = math.clamp(viewport.Y * 0.78, 400, 720)

    local root = Instance.new("Frame")
    root.Name = "Main"
    root.Size = UDim2.fromOffset(winW, winH)
    root.Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2)
    root.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    root.BorderSizePixel = 0
    root.Parent = ScreenGui
    Instance.new("UICorner", root).CornerRadius = UDim.new(0, 16)
    local stroke = Instance.new("UIStroke", root)
    stroke.Color = Color3.fromRGB(40, 40, 50)
    stroke.Thickness = 1

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 48)
    titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = root
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 16)
    local topFix = Instance.new("Frame")
    topFix.Size = UDim2.new(1, 0, 0, 20)
    topFix.Position = UDim2.new(0, 0, 1, -20)
    topFix.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    topFix.BorderSizePixel = 0
    topFix.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -140, 1, 0)
    titleLabel.Position = UDim2.new(0, 18, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Suture Hub · 服务器选择"
    titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 60, 0, 32)
    refreshBtn.Position = UDim2.new(1, -104, 0.5, -16)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(108, 92, 231)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "刷新"
    refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshBtn.TextSize = 13
    refreshBtn.Font = Enum.Font.GothamBold
    refreshBtn.Parent = titleBar
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 8)
    refreshBtn.MouseEnter:Connect(function()
        TweenService:Create(refreshBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(130, 110, 245) }):Play()
    end)
    refreshBtn.MouseLeave:Connect(function()
        TweenService:Create(refreshBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(108, 92, 231) }):Play()
    end)
    refreshBtn.Activated:Connect(uiRefresh)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "x"
    closeBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    closeBtn.TextSize = 15
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(200, 60, 70) }):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 30, 38) }):Play()
    end)
    closeBtn.Activated:Connect(function()
        ServerUI.Root.Visible = false
    end)

    searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -24, 0, 38)
    searchBox.Position = UDim2.new(0, 12, 0, 58)
    searchBox.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    searchBox.BorderSizePixel = 0
    searchBox.PlaceholderText = "搜索服务器ID...（回车应用）"
    searchBox.PlaceholderColor3 = Color3.fromRGB(110, 110, 125)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(230, 230, 238)
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 14
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = root
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 8)
    local searchStroke = Instance.new("UIStroke", searchBox)
    searchStroke.Color = Color3.fromRGB(40, 40, 50)
    searchStroke.Thickness = 1
    searchBox.FocusLost:Connect(function()
        buildList()
    end)

    listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, -24, 1, -118)
    listFrame.Position = UDim2.new(0, 12, 0, 106)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 4
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.Parent = root
    local layout = Instance.new("UIListLayout", listFrame)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 12)
    local padding = Instance.new("UIPadding", listFrame)
    padding.PaddingBottom = UDim.new(0, 12)

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 26)
    statusLabel.Position = UDim2.new(0, 12, 1, -32)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(120, 120, 135)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Text = "等待刷新"
    statusLabel.Parent = root

    -- 拖动窗口（鼠标 + 触摸，可拖到屏幕顶）
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
                math.clamp(root.AbsolutePosition.Y + delta.Y, 0, vp.Y - 60)
            )
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = input.Position
            if typeof(pos) == "Vector3" then
                pos = Vector2.new(pos.X, pos.Y)
            end
            local newPos = pos - dragOffset
            root.Position = UDim2.fromOffset(
                math.clamp(newPos.X, -root.AbsoluteSize.X + 80, vp.X - 80),
                math.clamp(newPos.Y, 0, vp.Y - 60)
            )
        end
    end)

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Escape and ServerUI.Root and ServerUI.Root.Visible then
            ServerUI.Root.Visible = false
        end
    end)

    ServerUI.Root = root
    buildList()

    -- 30 秒自动刷新（窗口可见时）
    task.spawn(function()
        while true do
            task.wait(30)
            if ServerUI.Root and ServerUI.Root.Visible then
                uiRefresh()
            end
        end
    end)
end

local function openServerBrowser()
    createServerUI()
    if os.clock() - lastBrowserFetch > 30 or #browserServers == 0 then
        uiRefresh()
    else
        buildList()
    end
end

Players.PlayerAdded:Connect(function()
    if ServerUI.Root and ServerUI.Root.Visible then
        buildCurrentInfo()
    end
end)

Players.PlayerRemoving:Connect(function()
    if ServerUI.Root and ServerUI.Root.Visible then
        buildCurrentInfo()
    end
end)

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
