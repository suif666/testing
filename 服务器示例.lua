-- 服务器类 远程脚本（依赖主脚本提供 ServerTab 和 getgenv().WindUI）
if getgenv().__SUTURE_SERVER_LOADED then
    return
end
getgenv().__SUTURE_SERVER_LOADED = true

local WindUI = getgenv().WindUI
local Tab = (getgenv().Tabs and getgenv().Tabs.ServerTab) or getgenv().SutureServerTab
if not Tab or not WindUI then
    warn("[服务器] 未找到 ServerTab / WindUI，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local PlaceId = game.PlaceId
local CurrentJob = game.JobId

-- ===== 配置 =====
local defaultServerConfig = {
    Mode = "随机",
    AutoEnabled = false,
    AutoInterval = 60,
    AdminEnabled = false,
    AdminInterval = 10,
    KeywordCheck = false,
}
getgenv().SutureServerConfig = getgenv().SutureServerConfig or {}
for k, v in pairs(defaultServerConfig) do
    if getgenv().SutureServerConfig[k] == nil then
        getgenv().SutureServerConfig[k] = v
    end
end
local ServerConfig = getgenv().SutureServerConfig

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
            -- 浏览器模式：只排除当前服务器，已满的也显示（排最后，标已满）
            if s.id and s.id ~= CurrentJob then
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
local Filter = { PingLow = false, Most = true, Least = false }
local sortPingBtn = nil
local sortMostBtn = nil
local sortLeastBtn = nil
local bindCardInputs = nil -- 前向声明：createServerCard 会调用它
local uiTitleLabel = nil
local pageIndex = 1
local currentPageCount = 1
local PageSize = 12
local pageButtons = {}
local pageColumn = nil
local size12Btn = nil
local size24Btn = nil
local size36Btn = nil
local TweenService = game:GetService("TweenService")

-- 打开列表时隐藏 WindUI 主窗口，防止透明窗口挡掉触摸；关闭时恢复
local function hideMainWindow()
    pcall(function()
        local w = getgenv().SutureMainWindow
        if w and w.UIElements and w.UIElements.Main then
            w.UIElements.Main.Visible = false
        end
    end)
end

local function showMainWindow()
    pcall(function()
        local w = getgenv().SutureMainWindow
        if w and w.UIElements and w.UIElements.Main then
            w.UIElements.Main.Visible = true
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

local function toV2(p)
    if typeof(p) == "Vector3" then
        return Vector2.new(p.X, p.Y)
    end
    return p
end

local function posDelta(p1, p2)
    if not p1 or not p2 then return 0 end
    return (p1 - p2).Magnitude
end

-- 累计位移超过 25px 或按住超过 0.8 秒就不算点击（防误触）
local function isTap(press, input)
    if not press or press.moved then return false end
    if (os.clock() - press.time) >= 0.8 then return false end
    if posDelta(toV2(input.Position), press.pos) > 25 then return false end
    return true
end

-- 手动点击识别：按下后没滑动就抬起 = 一次点击（兼容手机执行器）
local function bindTap(gui, callback)
    local press = nil
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            press = { input = input, pos = toV2(input.Position), time = os.clock(), moved = false }
        end
    end)
    gui.InputChanged:Connect(function(input)
        if press and input == press.input then
            if posDelta(toV2(input.Position), press.pos) > 25 then
                press.moved = true
            end
        end
    end)
    gui.InputEnded:Connect(function(input)
        if press and input == press.input then
            local p = press
            press = nil
            if isTap(p, input) then
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
    local usePing = Filter.PingLow
    local useMost = Filter.Most
    local useLeast = Filter.Least
    if not usePing and not useMost and not useLeast then
        useMost = true
    end
    table.sort(list, function(a, b)
        local pa = type(a.ping) == "number" and a.ping or math.huge
        local pb = type(b.ping) == "number" and b.ping or math.huge
        if useMost then
            if a.playing ~= b.playing then
                return a.playing > b.playing
            end
            if usePing and pa ~= pb then
                return pa < pb
            end
            return false
        elseif useLeast then
            if a.playing ~= b.playing then
                return a.playing < b.playing
            end
            if usePing and pa ~= pb then
                return pa < pb
            end
            return false
        elseif usePing then
            return pa < pb
        end
        return false
    end)
end

local function updateSortButtons()
    if not sortPingBtn then return end
    local activeC = Color3.fromRGB(108, 92, 231)
    local idleC = Color3.fromRGB(30, 30, 38)
    sortPingBtn.BackgroundColor3 = Filter.PingLow and activeC or idleC
    sortMostBtn.BackgroundColor3 = Filter.Most and activeC or idleC
    sortLeastBtn.BackgroundColor3 = Filter.Least and activeC or idleC
end

local function updateSizeButtons()
    if not size12Btn then return end
    local activeC = Color3.fromRGB(108, 92, 231)
    local idleC = Color3.fromRGB(30, 30, 38)
    size12Btn.BackgroundColor3 = PageSize == 12 and activeC or idleC
    size24Btn.BackgroundColor3 = PageSize == 24 and activeC or idleC
    size36Btn.BackgroundColor3 = PageSize == 36 and activeC or idleC
end

local function createServerCard(server, recommended, index, x, y, cell, full)
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
    stroke.Color = full
        and Color3.fromRGB(220, 70, 70)
        or (recommended and Color3.fromRGB(108, 92, 231) or Color3.fromRGB(40, 40, 50))
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
    idLabel.Text = "服务器" .. index .. (recommended and " ★" or "")
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
    local pingText = type(server.ping) == "number" and (math.floor(server.ping) .. "ms") or "--"
    local pingLabel = Instance.new("TextLabel")
    pingLabel.Size = UDim2.new(1, 0, 0, 18)
    pingLabel.Position = UDim2.new(0, 0, 0, 52)
    pingLabel.BackgroundTransparency = 1
    pingLabel.Text = pingText
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
    regionLabel.Text = full and "已满" or (server.region and tostring(server.region) or "")
    regionLabel.TextColor3 = full and Color3.fromRGB(240, 110, 110) or Color3.fromRGB(130, 130, 145)
    regionLabel.TextSize = 11
    regionLabel.Font = Enum.Font.Gotham
    regionLabel.TextXAlignment = Enum.TextXAlignment.Center
    regionLabel.Parent = card

    -- 根据卡片大小自适应排版，避免文字溢出到相邻卡片
    if cell >= 90 then
        idLabel.Size = UDim2.new(1, 0, 0, 18)
        idLabel.Position = UDim2.new(0, 0, 0, 0)
        idLabel.TextSize = 13
        countLabel.Size = UDim2.new(1, 0, 0, 34)
        countLabel.Position = UDim2.new(0, 0, 0, 18)
        countLabel.TextSize = 20
        pingLabel.Size = UDim2.new(1, 0, 0, 18)
        pingLabel.Position = UDim2.new(0, 0, 0, 52)
        pingLabel.TextSize = 13
        pingLabel.Text = "参考 " .. pingText
        regionLabel.Visible = true
    elseif cell >= 70 then
        idLabel.Size = UDim2.new(1, 0, 0, 16)
        idLabel.Position = UDim2.new(0, 0, 0, 2)
        idLabel.TextSize = 12
        countLabel.Size = UDim2.new(1, 0, 0, 24)
        countLabel.Position = UDim2.new(0, 0, 0, 18)
        countLabel.TextSize = 16
        pingLabel.Size = UDim2.new(1, 0, 0, 16)
        pingLabel.Position = UDim2.new(0, 0, 0, 42)
        pingLabel.TextSize = 11
        pingLabel.Text = "参考" .. pingText
        regionLabel.Visible = false
    else
        idLabel.Size = UDim2.new(1, 0, 0, 14)
        idLabel.Position = UDim2.new(0, 0, 0, 1)
        idLabel.TextSize = 11
        countLabel.Size = UDim2.new(1, 0, 0, 20)
        countLabel.Position = UDim2.new(0, 0, 0, 15)
        countLabel.TextSize = 14
        pingLabel.Size = UDim2.new(1, 0, 0, 14)
        pingLabel.Position = UDim2.new(0, 0, 0, 35)
        pingLabel.TextSize = 10
        pingLabel.Text = "~" .. pingText
        regionLabel.Visible = false
    end

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
    local cardInfo = { server = server, recommended = recommended, index = index, full = full }
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

-- 右侧页码（纯数字，页数多时可上下拖动）
local PAGE_PITCH = 33
local function updatePageButtons(pageCount)
    if not pageColumn then return end
    currentPageCount = pageCount

    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    pageColumn.CanvasSize = UDim2.new(0, 0, 0, math.max(viewport.Y - 196, pageCount * PAGE_PITCH))

    for i = 1, pageCount do
        local lbl = pageButtons[i]
        if not lbl then
            lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(0, 34, 0, 28)
            lbl.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
            lbl.BorderSizePixel = 0
            lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
            lbl.TextSize = 12
            lbl.Font = Enum.Font.GothamBold
            lbl.Parent = pageColumn
            Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 7)
            pageButtons[i] = lbl
        end
        lbl.Visible = true
        lbl.Text = tostring(i)
        lbl.BackgroundColor3 = (i == pageIndex)
            and Color3.fromRGB(108, 92, 231)
            or Color3.fromRGB(30, 30, 38)
    end
    for i = pageCount + 1, #pageButtons do
        if pageButtons[i] then
            pageButtons[i].Visible = false
        end
    end
end

local function buildList()
    if not statusLabel or not searchBox then return end
    clearRows()
    updateSortButtons()
    updateSizeButtons()

    sortServers(browserServers)
    local query = searchBox.Text:lower()
    local recommended = nil
    for _, s in ipairs(browserServers) do
        if not recommended or s.playing < recommended.playing then
            recommended = s
        end
    end

    local filtered = {}
    local fullList = {}
    local fullCount = 0
    for _, s in ipairs(browserServers) do
        local id = tostring(s.id):lower()
        if query == "" or id:find(query, 1, true) then
            if s.playing >= s.maxPlayers then
                fullCount = fullCount + 1
                table.insert(fullList, s)
            else
                table.insert(filtered, s)
            end
        end
    end
    for _, s in ipairs(fullList) do
        table.insert(filtered, s)
    end

    if uiTitleLabel then
        uiTitleLabel.Text = "Suture Hub · 服务器选择（共 " .. #browserServers .. " 个）"
    end

    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local gridW = cardGrid.AbsoluteSize.X
    local gridH = cardGrid.AbsoluteSize.Y
    if gridW <= 0 then gridW = viewport.X - 72 end
    if gridH <= 0 then gridH = viewport.Y - 196 end
    local gap = 10
    local minCell = 56

    -- 尝试 2-8 列，选出能把 PageSize 个完整放下且卡片最大的方案
    local cols = 3
    local rows = 1
    local cell = minCell
    local bestCell = 0
    for testCols = 2, 8 do
        local testRows = math.max(1, math.ceil(PageSize / testCols))
        local cw = (gridW - gap * (testCols - 1)) / testCols
        local ch = (gridH - 12) / testRows - gap
        local c = math.min(cw, ch)
        if c >= minCell and c > bestCell then
            bestCell = c
            cols = testCols
            rows = testRows
            cell = math.min(c, 165)
        end
    end
    if bestCell == 0 then
        cols = math.max(1, math.floor((gridW + gap) / (minCell + gap)))
        rows = math.max(1, math.floor((gridH - 12) / (minCell + gap)))
        cell = minCell
    end

    local cap = PageSize
    if bestCell == 0 then
        cap = math.min(PageSize, rows * cols)
    end
    local pageCount = math.max(1, math.ceil(#filtered / cap))
    if pageIndex > pageCount then
        pageIndex = pageCount
    end
    updatePageButtons(pageCount)

    -- 整行居中，避免卡片挤在左边
    local totalRowW = cols * cell + (cols - 1) * gap
    local startX = math.max(0, math.floor((gridW - totalRowW) / 2))

    local startIdx = (pageIndex - 1) * cap + 1
    local endIdx = math.min(pageIndex * cap, #filtered)
    local cardErr = nil
    for i = startIdx, endIdx do
        local s = filtered[i]
        local idxInPage = i - (pageIndex - 1) * cap
        local col = (idxInPage - 1) % cols
        local row = math.floor((idxInPage - 1) / cols)
        local okc, errc = pcall(createServerCard, s, #filtered > 1 and s == recommended, i,
            startX + col * (cell + gap), 12 + row * (cell + gap), cell, s.playing >= s.maxPlayers)
        if not okc and not cardErr then
            cardErr = tostring(errc)
        end
    end

    cardGrid.CanvasSize = UDim2.new(0, 0, 0, rows * (cell + gap) + 24)

    local line1 = currentLine()
    if cardErr then
        statusLabel.Text = line1 .. "\n卡片创建出错: " .. cardErr
        warn("[服务器] 卡片创建出错:", cardErr)
    elseif #filtered == 0 then
        statusLabel.Text = line1 .. "\n没有匹配「" .. searchBox.Text .. "」的服务器"
    else
        local suffix = ""
        if searchBox.Text ~= "" then suffix = "（筛选结果）" end
        local fullText = fullCount > 0 and ("（含已满 " .. fullCount .. " 个）") or ""
        statusLabel.Text = line1 .. "\n共 " .. #filtered .. " 个服务器" .. fullText
            .. " · 第 " .. pageIndex .. "/" .. pageCount .. " 页" .. suffix
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
    gridPress = { input = input, pos = toV2(input.Position), time = os.clock(), moved = false, card = cardInfo }
end

local function finishGridPress(input)
    if not gridPress or input ~= gridPress.input then return end
    local p = gridPress
    gridPress = nil
    if p.card and isTap(p, input) then
        local srv = p.card.server
        if p.card.full then
            statusLabel.Text = "服务器" .. p.card.index .. " 已满，无法加入"
            notify("无法加入", "该服务器已满", "alert-triangle", 3)
            return
        end
        statusLabel.Text = "正在加入 服务器" .. p.card.index .. "（在线 " .. srv.playing .. "/" .. srv.maxPlayers .. "）..."
        notify("正在加入", "在线 " .. srv.playing .. "/" .. srv.maxPlayers, "arrow-right", 3)
        TeleportService:TeleportToPlaceInstance(PlaceId, srv.id)
    end
end

function bindCardInputs(gui, cardInfo)
    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            startGridPress(input, cardInfo)
        end
    end)
    gui.InputChanged:Connect(function(input)
        if gridPress and input == gridPress.input then
            if posDelta(toV2(input.Position), gridPress.pos) > 25 then
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

    uiTitleLabel = Instance.new("TextLabel")
    uiTitleLabel.Size = UDim2.new(0.34, -20, 1, 0)
    uiTitleLabel.Position = UDim2.new(0, 16, 0, 0)
    uiTitleLabel.BackgroundTransparency = 1
    uiTitleLabel.Text = "Suture Hub · 服务器选择（获取中...）"
    uiTitleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    uiTitleLabel.TextSize = 17
    uiTitleLabel.Font = Enum.Font.GothamBold
    uiTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    uiTitleLabel.Parent = header

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

    -- 筛选按钮组（左）+ 每页数量（右）
    local uiViewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local availW = uiViewport.X - 24
    local filterW = math.floor(availW * 0.55)
    local sizeGroupW = availW - filterW - 8
    local filterGap = 6
    local sizeGap = 4
    local filterBtnW = math.floor((filterW - filterGap * 2) / 3)
    local sizeBtnW = math.floor((sizeGroupW - 34 - sizeGap * 2) / 3)
    local sizeLabelX = 12 + filterW + 8
    local sizeBtnX = sizeLabelX + 34

    local function makeSortBtn(text, mode, x, w)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, w, 0, 34)
        btn.Position = UDim2.new(0, x, 0, 54)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(220, 220, 230)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.Parent = root
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        bindTap(btn, function()
            if mode == "ping" then
                Filter.PingLow = not Filter.PingLow
            elseif mode == "most" then
                Filter.Most = not Filter.Most
                if Filter.Most then Filter.Least = false end
            elseif mode == "least" then
                Filter.Least = not Filter.Least
                if Filter.Least then Filter.Most = false end
            end
            buildList()
        end)
        return btn
    end
    sortPingBtn = makeSortBtn("参考Ping低", "ping", 12, filterBtnW)
    sortMostBtn = makeSortBtn("人数最多", "most", 12 + filterBtnW + filterGap, filterBtnW)
    sortLeastBtn = makeSortBtn("人数最少", "least", 12 + (filterBtnW + filterGap) * 2, filterBtnW)

    local sizeLabel = Instance.new("TextLabel")
    sizeLabel.Size = UDim2.new(0, 34, 0, 34)
    sizeLabel.Position = UDim2.new(0, sizeLabelX, 0, 54)
    sizeLabel.BackgroundTransparency = 1
    sizeLabel.Text = "每页"
    sizeLabel.TextColor3 = Color3.fromRGB(140, 140, 155)
    sizeLabel.TextSize = 12
    sizeLabel.Font = Enum.Font.Gotham
    sizeLabel.TextXAlignment = Enum.TextXAlignment.Center
    sizeLabel.Parent = root

    local function makeSizeBtn(text, value, x, w)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, w, 0, 34)
        btn.Position = UDim2.new(0, x, 0, 54)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(220, 220, 230)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.Parent = root
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        bindTap(btn, function()
            PageSize = value
            buildList()
        end)
        return btn
    end
    size12Btn = makeSizeBtn("12", 12, sizeBtnX, sizeBtnW)
    size24Btn = makeSizeBtn("24", 24, sizeBtnX + sizeBtnW + sizeGap, sizeBtnW)
    size36Btn = makeSizeBtn("36", 36, sizeBtnX + (sizeBtnW + sizeGap) * 2, sizeBtnW)

    -- 多列网格
    cardGrid = Instance.new("ScrollingFrame")
    cardGrid.Size = UDim2.new(1, -72, 1, -196)
    cardGrid.Position = UDim2.new(0, 12, 0, 134)
    cardGrid.BackgroundTransparency = 1
    cardGrid.BorderSizePixel = 0
    cardGrid.ScrollBarThickness = 4
    cardGrid.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    cardGrid.ScrollingEnabled = false
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
            if posDelta(toV2(input.Position), gridPress.pos) > 25 then
                gridPress.moved = true
            end
        end
    end)
    cardGrid.InputEnded:Connect(finishGridPress)
    cardGrid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if gridPress then
            gridPress.moved = true
        end
    end)

    -- 右侧页数栏（可上下拖动，点击数字翻页）
    pageColumn = Instance.new("ScrollingFrame")
    pageColumn.Name = "PageColumn"
    pageColumn.Size = UDim2.new(0, 40, 1, -196)
    pageColumn.Position = UDim2.new(1, -54, 0, 134)
    pageColumn.BackgroundTransparency = 1
    pageColumn.BorderSizePixel = 0
    pageColumn.ScrollBarThickness = 4
    pageColumn.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
    pageColumn.ScrollingDirection = Enum.ScrollingDirection.Y
    pageColumn.Parent = root
    local pageLayout = Instance.new("UIListLayout", pageColumn)
    pageLayout.Padding = UDim.new(0, 5)
    pageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    -- 点页码：按触摸坐标命中第几个数字（不依赖子按钮接收触摸）
    local pagePress = nil
    pageColumn.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        local pos = input.Position
        if typeof(pos) == "Vector3" then
            pos = Vector2.new(pos.X, pos.Y)
        end
        local cy = pos.Y - pageColumn.AbsolutePosition.Y + pageColumn.CanvasPosition.Y
        local pg = math.floor(cy / PAGE_PITCH) + 1
        if pg >= 1 and pg <= currentPageCount then
            pagePress = { input = input, pos = toV2(input.Position), time = os.clock(), moved = false, page = pg }
        end
    end)
    pageColumn.InputChanged:Connect(function(input)
        if pagePress and input == pagePress.input then
            if posDelta(toV2(input.Position), pagePress.pos) > 25 then
                pagePress.moved = true
            end
        end
    end)
    pageColumn.InputEnded:Connect(function(input)
        if pagePress and input == pagePress.input then
            local p = pagePress
            pagePress = nil
            if isTap(p, input) then
                pageIndex = p.page
                buildList()
            end
        end
    end)
    pageColumn:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if pagePress then
            pagePress.moved = true
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
        pcall(function()
            if ServerUI.ScreenGui then
                ServerUI.ScreenGui:Destroy()
            end
            ServerUI.Root = nil
            ServerUI.ScreenGui = nil
        end)
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
