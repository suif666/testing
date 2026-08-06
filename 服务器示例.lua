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

-- ===== 自定义服务器列表界面 =====
local function rebuildServerList()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local query = searchBox.Text:lower()
    local shown = 0
    for _, s in ipairs(browserServers) do
        local id = tostring(s.id):lower()
        if query == "" or id:find(query, 1, true) then
            local row = Instance.new("TextButton")
            row.Name = "Server"
            row.Size = UDim2.new(1, 0, 0, 34)
            row.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
            row.BorderSizePixel = 0
            row.Font = Enum.Font.Gotham
            row.TextSize = 14
            row.TextColor3 = Color3.fromRGB(230, 230, 235)
            row.Text = s.playing .. "/" .. s.maxPlayers .. "   |   " .. tostring(s.id):sub(1, 8)
            row.Parent = listFrame
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
            row.MouseEnter:Connect(function()
                row.BackgroundColor3 = Color3.fromRGB(54, 54, 74)
            end)
            row.MouseLeave:Connect(function()
                row.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
            end)
            row.Activated:Connect(function()
                statusLabel.Text = "正在加入 " .. tostring(s.id) .. "（在线 " .. s.playing .. "/" .. s.maxPlayers .. "）..."
                notify("正在加入", "在线 " .. s.playing .. "/" .. s.maxPlayers, "arrow-right", 3)
                TeleportService:TeleportToPlaceInstance(PlaceId, s.id)
            end)
            shown = shown + 1
            if shown >= 800 then break end
        end
    end

    listFrame.CanvasSize = UDim2.new(0, 0, 0, shown * 40 + 4)

    if #browserServers == 0 then
        statusLabel.Text = "当前没有可用的公开服务器"
    elseif shown == 0 then
        statusLabel.Text = "没有匹配「" .. searchBox.Text .. "」的服务器"
    else
        local suffix = ""
        if searchBox.Text ~= "" then suffix = "（筛选结果）" end
        statusLabel.Text = "共 " .. #browserServers .. " 个可用服务器，显示前 " .. shown .. " 个" .. suffix .. " · " .. os.date("%H:%M:%S")
    end
end

local function uiRefresh()
    if not refreshBtn then return end
    refreshBtn.Text = "获取中..."
    statusLabel.Text = "正在获取服务器列表..."
    task.spawn(function()
        local ok, list = pcall(fetchAllServers)
        refreshBtn.Text = "刷新"
        if not ok then
            statusLabel.Text = "获取失败: " .. tostring(list)
            return
        end
        browserServers = list
        lastBrowserFetch = os.clock()
        rebuildServerList()
        notify("服务器列表", "找到 " .. #list .. " 个可用服务器", "check", 3)
    end)
end

local function createServerUI()
    if ServerUI.Root then
        ServerUI.Root.Visible = true
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

    local root = Instance.new("Frame")
    root.Name = "Main"
    root.Size = UDim2.fromOffset(460, 600)
    root.Position = UDim2.new(0.5, -230, 0.5, -300)
    root.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    root.BorderSizePixel = 0
    root.Parent = ScreenGui
    Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", root)
    stroke.Color = Color3.fromRGB(80, 80, 100)
    stroke.Thickness = 1

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 38)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = root
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -120, 1, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 16
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Text = "服务器列表"
    titleLabel.Parent = titleBar

    refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 64, 0, 26)
    refreshBtn.Position = UDim2.new(1, -110, 0.5, -13)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 220)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Font = Enum.Font.Gotham
    refreshBtn.TextSize = 14
    refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshBtn.Text = "刷新"
    refreshBtn.Parent = titleBar
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)
    refreshBtn.Activated:Connect(uiRefresh)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 34, 0, 26)
    closeBtn.Position = UDim2.new(1, -44, 0.5, -13)
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
    closeBtn.BorderSizePixel = 0
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Text = "✕"
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
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
            dragOffset = input.Position - root.AbsolutePosition
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            local newPos = input.Position - dragOffset
            root.Position = UDim2.fromOffset(
                math.clamp(newPos.X, -root.AbsoluteSize.X + 60, vp.X - 60),
                math.clamp(newPos.Y, 0, vp.Y - 40)
            )
        end
    end)

    searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -24, 0, 32)
    searchBox.Position = UDim2.new(0, 12, 0, 46)
    searchBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    searchBox.BorderSizePixel = 0
    searchBox.PlaceholderText = "搜索服务器ID...（回车应用）"
    searchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 145)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 14
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = root
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)
    searchBox.FocusLost:Connect(function()
        rebuildServerList()
    end)

    listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, -24, 1, -156)
    listFrame.Position = UDim2.new(0, 12, 0, 88)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 6
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.Parent = root
    local layout = Instance.new("UIListLayout", listFrame)
    layout.Padding = UDim.new(0, 6)

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 24)
    statusLabel.Position = UDim2.new(0, 12, 1, -30)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = "等待刷新"
    statusLabel.Parent = root

    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Escape and ServerUI.Root and ServerUI.Root.Visible then
            ServerUI.Root.Visible = false
        end
    end)

    ServerUI.Root = root
end

local function openServerBrowser()
    createServerUI()
    if os.clock() - lastBrowserFetch > 30 or #browserServers == 0 then
        uiRefresh()
    else
        rebuildServerList()
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
