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
local statusLabel = nil
local searchBox = nil
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

    -- 3 秒一刷新，为了不触发接口限流，每轮最多拉 2 页（约 200 个）
    for page = 1, 2 do
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
        task.wait(0.2)
    end

    -- 按在线人数从多到少排序
    table.sort(all, function(a, b)
        return (a.playing or 0) > (b.playing or 0)
    end)
    return all
end

-- ===== 自定义服务器列表界面（全屏网格版） =====
local refreshing = false
local cardGrid = nil
local lastSig = nil
local cardRects = {}
local gridPress = nil
local SortMode = "人数最多"
local serverIndex = 0
local sortPingBtn = nil
local sortMostBtn = nil
local sortLeastBtn = nil
local TweenService = game:GetService("TweenService")

-- 打开列表时隐藏 WindUI 主窗口，防止透明窗口挡掉触摸；关闭时恢复
local function hideMainWindow()
    pcall(function()
        if win and win.UIElements and win.UIElements.Main then
            win.UIElements.Main.Visible = false
        end
    end)
end

local function showMainWindow()
    pcall(function()
        if win and win.UIElements and win.UIElements.Main then
            win.UIElements.Main.Visible = true
        end
    end)
end

local function clearRows()
    cardRects = {}
    for _, child in ipairs(cardGrid:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

-- 根据屏幕宽度算方形卡片尺寸（手机 3 列 / 平板 4 列 / 电脑 5 列）
local function computeCell()
    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local gap = 10
    local sidePad = 24
    local cols = viewport.X > 900 and 5 or (viewport.X > 600 and 4 or 3)
    local cell = math.clamp((viewport.X - sidePad * 2 - gap * (cols - 1)) / cols, 90, 170)
    return cell, gap, cols
end

-- 手动点击识别：按下后没滑动就抬起 = 一次点击（兼容手机执行器）
local function bindTap(gui, callback, scrollFrame)
    local press = nil
    if scrollFrame then
        scrollFrame.Scrolling:Connect(function()
            if press then
                press.moved = true
            end
        end)
    end
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            press = { input = input, time = os.clock(), moved = false }
        end
    end)
    gui.InputChanged:Connect(function(input)
        if press and input == press.input then
            local d = input.Delta
            if d and (math.abs(d.X) > 25 or math.abs(d.Y) > 25) then
                press.moved = true
            end
        end
    end)
    gui.InputEnded:Connect(function(input)
        if press and input == press.input then
            local p = press
            press = nil
            if not p.moved and (os.clock() - p.time) < 0.8 then
                callback()
            end
        end
    end)
end

local function getGameName()
    local name = game.Name
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        if info and info.Name and info.Name ~= "" then
            name = info.Name
        end
    end)
    return name
end

local function currentLine()
    local players = Players:GetPlayers()
    local lp = Players.LocalPlayer
    local pingMs = 0
    pcall(function()
        pingMs = math.floor(lp:GetNetworkPing() * 1000)
    end)
    return "本服: " .. #players .. "/" .. Players.MaxPlayers
        .. " · Ping " .. pingMs .. "ms"
        .. " · 房间ID: " .. (game.JobId or "无")
        .. " · " .. getGameName()
end

local function sortServers(list)
    table.sort(list, function(a, b)
        if SortMode == "ping最低" then
            local pa = type(a.ping) == "number" and a.ping or math.huge
            local pb = type(b.ping) == "number" and b.ping or math.huge
            return pa < pb
        elseif SortMode == "人数最少" then
            return a.playing < b.playing
        end
        return a.playing > b.playing
    end)
end

local function updateSortButtons()
    if not sortPingBtn then return end
    local activeC = Color3.fromRGB(108, 92, 231)
    local idleC = Color3.fromRGB(30, 30, 38)
    sortPingBtn.BackgroundColor3 = SortMode == "ping最低" and activeC or idleC
    sortMostBtn.BackgroundColor3 = SortMode == "人数最多" and activeC or idleC
    sortLeastBtn.BackgroundColor3 = SortMode == "人数最少" and activeC or idleC
end

local function createServerCard(server, recommended, x, y, cell)
    serverIndex = serverIndex + 1

    local card = Instance.new("TextButton")
    card.Name = "ServerCard"
    card.Size = UDim2.fromOffset(cell, cell)
    card.Position = UDim2.fromOffset(x, y)
    card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    card.BorderSizePixel = 0
    card.AutoButtonColor = false
    card.Text = ""
    card.Parent = cardGrid
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", card)
    stroke.Color = recommended and Color3.fromRGB(108, 92, 231) or Color3.fromRGB(40, 40, 50)
    stroke.Thickness = 1

    local pad = Instance.new("UIPadding", card)
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)

    -- 编号（蓝色）
    local idLabel = Instance.new("TextLabel")
    idLabel.Size = UDim2.new(1, 0, 0, 18)
    idLabel.Position = UDim2.new(0, 0, 0, 0)
    idLabel.BackgroundTransparency = 1
    idLabel.Text = "服务器" .. serverIndex .. (recommended and " ★" or "")
    idLabel.TextColor3 = Color3.fromRGB(80, 180, 255)
    idLabel.TextSize = 13
    idLabel.Font = Enum.Font.GothamBold
    idLabel.TextXAlignment = Enum.TextXAlignment.Center
    idLabel.Parent = card

    -- 人数（绿→红按满员率变色）
    local ratio = server.maxPlayers > 0 and (server.playing / server.maxPlayers) or 0
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(1, 0, 0, 34)
    countLabel.Position = UDim2.new(0, 0, 0, 18)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = server.playing .. "/" .. server.maxPlayers
    countLabel.TextColor3 = Color3.fromHSV((1 - ratio) * 0.35, 0.8, 1)
    countLabel.TextSize = 20
    countLabel.Font = Enum.Font.GothamBold
    countLabel.TextXAlignment = Enum.TextXAlignment.Center
    countLabel.Parent = card

    -- Ping（橙色）
    local pingLabel = Instance.new("TextLabel")
    pingLabel.Size = UDim2.new(1, 0, 0, 18)
    pingLabel.Position = UDim2.new(0, 0, 0, 52)
    pingLabel.BackgroundTransparency = 1
    pingLabel.Text = type(server.ping) == "number" and (math.floor(server.ping) .. "ms") or "--"
    pingLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
    pingLabel.TextSize = 13
    pingLabel.Font = Enum.Font.GothamBold
    pingLabel.TextXAlignment = Enum.TextXAlignment.Center
    pingLabel.Parent = card

    -- 底部提示（灰色）
    local regionLabel = Instance.new("TextLabel")
    regionLabel.Size = UDim2.new(1, 0, 0, 16)
    regionLabel.Position = UDim2.new(0, 0, 1, -16)
    regionLabel.BackgroundTransparency = 1
    regionLabel.Text = server.region and tostring(server.region) or "点击加入"
    regionLabel.TextColor3 = Color3.fromRGB(130, 130, 145)
    regionLabel.TextSize = 11
    regionLabel.Font = Enum.Font.Gotham
    regionLabel.TextXAlignment = Enum.TextXAlignment.Center
    regionLabel.Parent = card

    local function press(active)
        card.BackgroundColor3 = active
            and Color3.fromRGB(28, 30, 40)
            or Color3.fromRGB(20, 20, 28)
    end
    card.MouseEnter:Connect(function() press(true) end)
    card.MouseLeave:Connect(function() press(false) end)
    card.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            press(true)
        end
    end)
    card.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            press(false)
        end
    end)
    local cardInfo = { server = server, recommended = recommended, index = serverIndex }
    cardRects[#cardRects + 1] = { x = x, y = y, w = cell, h = cell, card = cardInfo }
    bindCardInputs(card, cardInfo)
end

local function updateStatusLine1()
    if not statusLabel then return end
    local line2 = ""
    local nl = statusLabel.Text:find("\n")
    if nl then
        line2 = statusLabel.Text:sub(nl + 1)
    end
    statusLabel.Text = currentLine() .. "\n" .. line2
end

local function buildList()
    clearRows()
    updateSortButtons()

    serverIndex = 0
    sortServers(browserServers)
    local query = searchBox.Text:lower()
    local shown = 0
    local recommended = nil
    for _, s in ipairs(browserServers) do
        if not recommended or s.playing < recommended.playing then
            recommended = s
        end
    end

    local cell, gap, cols = computeCell()
    for _, s in ipairs(browserServers) do
        local id = tostring(s.id):lower()
        if query == "" or id:find(query, 1, true) then
            local col = shown % cols
            local row = math.floor(shown / cols)
            pcall(createServerCard, s, #browserServers > 1 and s == recommended,
                12 + col * (cell + gap), 12 + row * (cell + gap), cell)
            shown = shown + 1
            if shown >= 300 then break end
        end
    end

    local rows = math.ceil(shown / cols)
    cardGrid.CanvasSize = UDim2.new(0, 0, 0, 12 + rows * (cell + gap) + 12)

    local line1 = currentLine()
    if #browserServers == 0 then
        statusLabel.Text = line1 .. "\n当前没有可用的公开服务器"
    elseif shown == 0 then
        statusLabel.Text = line1 .. "\n没有匹配「" .. searchBox.Text .. "」的服务器"
    else
        local suffix = ""
        if searchBox.Text ~= "" then suffix = "（筛选结果）" end
        statusLabel.Text = line1 .. "\n共 " .. #browserServers .. " 个可用服务器，显示前 " .. shown .. " 个" .. suffix
            .. " · " .. os.date("%H:%M:%S") .. " · 3秒自动刷新"
    end
end

local function listSignature(list)
    local sig = #list
    for i = 1, math.min(#list, 8) do
        sig = sig * 31 + (list[i].playing or 0)
    end
    return sig
end

local function uiRefresh()
    if refreshing then return end
    refreshing = true
    statusLabel.Text = currentLine() .. "\n正在获取服务器列表（3秒自动刷新）..."
    task.spawn(function()
        local ok, list = pcall(fetchAllServers)
        refreshing = false
        if not ok then
            statusLabel.Text = currentLine() .. "\n获取失败: " .. tostring(list)
            return
        end
        browserServers = list
        lastBrowserFetch = os.clock()
        local sig = listSignature(list)
        if sig ~= lastSig then
            lastSig = sig
            pcall(buildList)
        else
            updateStatusLine1()
        end
    end)
end

-- ===== 卡片点击：直接加入（滚动区本体命中检测，兼容手机） =====
local function startGridPress(input, cardInfo)
    if not cardInfo then return end
    gridPress = { input = input, time = os.clock(), moved = false, card = cardInfo }
end

local function finishGridPress(input)
    if not gridPress or input ~= gridPress.input then return end
    local p = gridPress
    gridPress = nil
    if p.card and not p.moved and (os.clock() - p.time) < 0.8 then
        local srv = p.card.server
        statusLabel.Text = "正在加入 服务器" .. p.card.index .. "（在线 " .. srv.playing .. "/" .. srv.maxPlayers .. "）..."
        notify("正在加入", "在线 " .. srv.playing .. "/" .. srv.maxPlayers, "arrow-right", 3)
        TeleportService:TeleportToPlaceInstance(PlaceId, srv.id)
    end
end

local function bindCardInputs(gui, cardInfo)
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            startGridPress(input, cardInfo)
        end
    end)
    gui.InputChanged:Connect(function(input)
        if gridPress and input == gridPress.input then
            local d = input.Delta
            if d and (math.abs(d.X) > 25 or math.abs(d.Y) > 25) then
                gridPress.moved = true
            end
        end
    end)
    gui.InputEnded:Connect(finishGridPress)
end

local function createServerUI()
    if ServerUI.Root then
        ServerUI.Root.Visible = true
        pcall(buildList)
        return
    end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ServerBrowserUI"
    ScreenGui.DisplayOrder = 100
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local parented = pcall(function()
        ScreenGui.Parent = game:GetService("CoreGui")
    end)
    if not parented then
        ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    -- 全屏半透明背景
    local root = Instance.new("Frame")
    root.Name = "Main"
    root.Size = UDim2.new(1, 0, 1, 0)
    root.BackgroundColor3 = Color3.fromRGB(6, 7, 10)
    root.BackgroundTransparency = 0.18
    root.BorderSizePixel = 0
    root.Parent = ScreenGui
    ServerUI.Root = root
    ServerUI.ScreenGui = ScreenGui

    -- 顶部栏
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 54)
    header.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    header.BackgroundTransparency = 0.25
    header.BorderSizePixel = 0
    header.Parent = root

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0.34, -20, 1, 0)
    titleLabel.Position = UDim2.new(0, 16, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Suture Hub · 服务器选择"
    titleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    titleLabel.TextSize = 17
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header

    searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -24, 0, 36)
    searchBox.Position = UDim2.new(0, 12, 0, 96)
    searchBox.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    searchBox.BorderSizePixel = 0
    searchBox.PlaceholderText = "搜索服务器ID...（回车）"
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

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "x"
    closeBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    closeBtn.TextSize = 15
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = header
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(200, 60, 70) }):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 30, 38) }):Play()
    end)
    bindTap(closeBtn, function()
        if ServerUI.Root then
            ServerUI.Root.Visible = false
        end
        showMainWindow()
    end)

    -- 排序按钮组
    local uiViewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local gap = 8
    local btnW = (uiViewport.X - 24 - gap * 2) / 3
    local function makeSortBtn(text, mode, x)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, btnW, 0, 34)
        btn.Position = UDim2.new(0, x, 0, 54)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(220, 220, 230)
        btn.TextSize = 13
        btn.Font = Enum.Font.GothamBold
        btn.Parent = root
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        bindTap(btn, function()
            SortMode = mode
            buildList()
        end)
        return btn
    end
    sortPingBtn = makeSortBtn("Ping最低", "ping最低", 12)
    sortMostBtn = makeSortBtn("人数最多", "人数最多", 12 + btnW + gap)
    sortLeastBtn = makeSortBtn("人数最少", "人数最少", 12 + (btnW + gap) * 2)

    -- 多列网格
    cardGrid = Instance.new("ScrollingFrame")
    cardGrid.Size = UDim2.new(1, -24, 1, -196)
    cardGrid.Position = UDim2.new(0, 12, 0, 134)
    cardGrid.BackgroundTransparency = 1
    cardGrid.BorderSizePixel = 0
    cardGrid.ScrollBarThickness = 4
    cardGrid.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    cardGrid.ScrollingDirection = Enum.ScrollingDirection.Y
    cardGrid.Parent = root

    -- 滚动区本体接收触摸：按下时按坐标命中卡片
    cardGrid.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        local pos = input.Position
        if typeof(pos) == "Vector3" then
            pos = Vector2.new(pos.X, pos.Y)
        end
        local cx = pos.X - cardGrid.AbsolutePosition.X + cardGrid.CanvasPosition.X
        local cy = pos.Y - cardGrid.AbsolutePosition.Y + cardGrid.CanvasPosition.Y
        for _, r in ipairs(cardRects) do
            if cx >= r.x and cx <= r.x + r.w and cy >= r.y and cy <= r.y + r.h then
                startGridPress(input, r.card)
                break
            end
        end
    end)
    cardGrid.InputChanged:Connect(function(input)
        if gridPress and input == gridPress.input then
            local d = input.Delta
            if d and (math.abs(d.X) > 25 or math.abs(d.Y) > 25) then
                gridPress.moved = true
            end
        end
    end)
    cardGrid.InputEnded:Connect(finishGridPress)
    cardGrid.Scrolling:Connect(function()
        if gridPress then
            gridPress.moved = true
        end
    end)

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 40)
    statusLabel.Position = UDim2.new(0, 12, 1, -46)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(120, 120, 135)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Text = "等待刷新"
    statusLabel.Parent = root

    pcall(buildList)

    -- 3 秒自动刷新（窗口可见时）
    task.spawn(function()
        while true do
            task.wait(3)
            if ServerUI.Root and ServerUI.Root.Visible then
                uiRefresh()
            end
        end
    end)
end

local function openServerBrowser()
    hideMainWindow()
    local ok, err = pcall(createServerUI)
    if not ok then
        showMainWindow()
        warn("[服务器] 列表界面创建失败:", err)
        notify("服务器列表", "创建失败: " .. tostring(err), "alert-triangle", 5)
        return
    end
    if os.clock() - lastBrowserFetch > 3 or #browserServers == 0 then
        uiRefresh()
    else
        pcall(buildList)
    end
end

Players.PlayerAdded:Connect(function()
    if ServerUI.Root and ServerUI.Root.Visible then
        updateStatusLine1()
    end
end)

Players.PlayerRemoving:Connect(function()
    if ServerUI.Root and ServerUI.Root.Visible then
        updateStatusLine1()
    end
end)

-- 全局 Esc：先关弹窗，再关列表（即使创建中途失败也能关）
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape then
        if ServerUI.Root then
            ServerUI.Root.Visible = false
            showMainWindow()
        end
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
