--[[
    Suture Hub - 服务器选择 UI（纯手搓）
    直接执行即可看到界面
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- 清理旧界面
if PlayerGui:FindFirstChild("SutureServerUI") then
    PlayerGui.SutureServerUI:Destroy()
end

-------------------------------------------------
-- 创建主界面
-------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SutureServerUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

-- 主窗口
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 520, 0, 420)
Main.Position = UDim2.new(0.5, -260, 0.5, -210)
Main.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 16)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(40, 40, 50)
MainStroke.Thickness = 1
MainStroke.Parent = Main

-------------------------------------------------
-- 顶部标题栏
-------------------------------------------------
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 48)
TopBar.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 16)
TopCorner.Parent = TopBar

-- 补丁：让顶部只有上方圆角
local TopFix = Instance.new("Frame")
TopFix.Size = UDim2.new(1, 0, 0, 20)
TopFix.Position = UDim2.new(0, 0, 1, -20)
TopFix.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
TopFix.BorderSizePixel = 0
TopFix.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Position = UDim2.new(0, 18, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Suture Hub · 服务器选择"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

-- 关闭按钮
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -16)
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
CloseBtn.TextSize = 20
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-------------------------------------------------
-- 内容区域
-------------------------------------------------
local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1, -24, 1, -64)
Content.Position = UDim2.new(0, 12, 0, 56)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 4
Content.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
Content.CanvasSize = UDim2.new(0, 0, 0, 0)
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.Parent = Main

local ListLayout = Instance.new("UIListLayout")
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 12)
ListLayout.Parent = Content

local Padding = Instance.new("UIPadding")
Padding.PaddingBottom = UDim.new(0, 12)
Padding.Parent = Content

-------------------------------------------------
-- 工具函数：创建卡片
-------------------------------------------------
local function CreateCard(titleText)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 0)
    Card.AutomaticSize = Enum.AutomaticSize.Y
    Card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    Card.BorderSizePixel = 0
    Card.Parent = Content

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 12)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    CardStroke.Color = Color3.fromRGB(38, 38, 48)
    CardStroke.Thickness = 1
    CardStroke.Parent = Card

    local CardPadding = Instance.new("UIPadding")
    CardPadding.PaddingTop = UDim.new(0, 14)
    CardPadding.PaddingBottom = UDim.new(0, 14)
    CardPadding.PaddingLeft = UDim.new(0, 16)
    CardPadding.PaddingRight = UDim.new(0, 16)
    CardPadding.Parent = Card

    local CardLayout = Instance.new("UIListLayout")
    CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CardLayout.Padding = UDim.new(0, 8)
    CardLayout.Parent = Card

    if titleText then
        local TitleLabel = Instance.new("TextLabel")
        TitleLabel.Size = UDim2.new(1, 0, 0, 20)
        TitleLabel.BackgroundTransparency = 1
        TitleLabel.Text = titleText
        TitleLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
        TitleLabel.TextSize = 12
        TitleLabel.Font = Enum.Font.GothamMedium
        TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
        TitleLabel.Parent = Card
    end

    return Card
end

-------------------------------------------------
-- 当前服务器卡片
-------------------------------------------------
local CurrentCard = CreateCard("当前服务器")

local CurrentInfo = Instance.new("TextLabel")
CurrentInfo.Size = UDim2.new(1, 0, 0, 0)
CurrentInfo.AutomaticSize = Enum.AutomaticSize.Y
CurrentInfo.BackgroundTransparency = 1
CurrentInfo.Text = "人数: 8 / 30\nPing: 45ms\nJobId: 1234-5678-abcd\n地区: 亚洲"
CurrentInfo.TextColor3 = Color3.fromRGB(220, 220, 230)
CurrentInfo.TextSize = 14
CurrentInfo.Font = Enum.Font.Gotham
CurrentInfo.TextXAlignment = Enum.TextXAlignment.Left
CurrentInfo.TextYAlignment = Enum.TextYAlignment.Top
CurrentInfo.Parent = CurrentCard

local PlayerTitle = Instance.new("TextLabel")
PlayerTitle.Size = UDim2.new(1, 0, 0, 18)
PlayerTitle.BackgroundTransparency = 1
PlayerTitle.Text = "服务器玩家"
PlayerTitle.TextColor3 = Color3.fromRGB(140, 140, 155)
PlayerTitle.TextSize = 12
PlayerTitle.Font = Enum.Font.GothamMedium
PlayerTitle.TextXAlignment = Enum.TextXAlignment.Left
PlayerTitle.Parent = CurrentCard

local PlayerList = Instance.new("TextLabel")
PlayerList.Size = UDim2.new(1, 0, 0, 0)
PlayerList.AutomaticSize = Enum.AutomaticSize.Y
PlayerList.BackgroundTransparency = 1
PlayerList.Text = "Player1, Player2, Player3, Player4, Player5"
PlayerList.TextColor3 = Color3.fromRGB(200, 200, 210)
PlayerList.TextSize = 13
PlayerList.Font = Enum.Font.Gotham
PlayerList.TextXAlignment = Enum.TextXAlignment.Left
PlayerList.TextWrapped = true
PlayerList.Parent = CurrentCard

-------------------------------------------------
-- 其他服务器标题
-------------------------------------------------
local OtherTitle = Instance.new("TextLabel")
OtherTitle.Size = UDim2.new(1, 0, 0, 22)
OtherTitle.BackgroundTransparency = 1
OtherTitle.Text = "其他服务器"
OtherTitle.TextColor3 = Color3.fromRGB(160, 160, 175)
OtherTitle.TextSize = 13
OtherTitle.Font = Enum.Font.GothamMedium
OtherTitle.TextXAlignment = Enum.TextXAlignment.Left
OtherTitle.Parent = Content

-------------------------------------------------
-- 创建单个服务器卡片的函数
-------------------------------------------------
local function CreateServerCard(name, players, maxPlayers, ping, recommended)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 64)
    Card.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    Card.BorderSizePixel = 0
    Card.Parent = Content

    local CardCorner = Instance.new("UICorner")
    CardCorner.CornerRadius = UDim.new(0, 12)
    CardCorner.Parent = Card

    local CardStroke = Instance.new("UIStroke")
    CardStroke.Color = recommended and Color3.fromRGB(108, 92, 231) or Color3.fromRGB(38, 38, 48)
    CardStroke.Thickness = 1
    CardStroke.Parent = Card

    -- 服务器名字
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(0.45, 0, 0, 20)
    NameLabel.Position = UDim2.new(0, 16, 0, 12)
    NameLabel.BackgroundTransparency = 1
    NameLabel.Text = name .. (recommended and "  ·  推荐" or "")
    NameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
    NameLabel.TextSize = 14
    NameLabel.Font = Enum.Font.GothamBold
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Parent = Card

    -- 人数 + Ping
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(0.45, 0, 0, 18)
    InfoLabel.Position = UDim2.new(0, 16, 0, 34)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Text = string.format("人数: %d / %d    Ping: %dms", players, maxPlayers, ping)
    InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
    InfoLabel.TextSize = 12
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Parent = Card

    -- 加入按钮
    local JoinBtn = Instance.new("TextButton")
    JoinBtn.Size = UDim2.new(0, 72, 0, 32)
    JoinBtn.Position = UDim2.new(1, -88, 0.5, -16)
    JoinBtn.BackgroundColor3 = Color3.fromRGB(108, 92, 231)
    JoinBtn.Text = "加入"
    JoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    JoinBtn.TextSize = 13
    JoinBtn.Font = Enum.Font.GothamBold
    JoinBtn.Parent = Card

    local JoinCorner = Instance.new("UICorner")
    JoinCorner.CornerRadius = UDim.new(0, 8)
    JoinCorner.Parent = JoinBtn

    -- 按钮悬停效果
    JoinBtn.MouseEnter:Connect(function()
        TweenService:Create(JoinBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(130, 110, 245)
        }):Play()
    end)
    JoinBtn.MouseLeave:Connect(function()
        TweenService:Create(JoinBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(108, 92, 231)
        }):Play()
    end)

    JoinBtn.MouseButton1Click:Connect(function()
        print("点击了加入:", name)
        -- 这里之后写传送逻辑
    end)

    return Card
end

-------------------------------------------------
-- 示例服务器卡片（空壳数据）
-------------------------------------------------
CreateServerCard("服务器 #1", 12, 30, 48, false)
CreateServerCard("服务器 #2", 7, 30, 32, true)   -- 推荐
CreateServerCard("服务器 #3", 21, 30, 67, false)
CreateServerCard("服务器 #4", 4, 30, 89, false)
CreateServerCard("服务器 #5", 15, 30, 41, false)

-------------------------------------------------
-- 拖动窗口功能
-------------------------------------------------
local dragging = false
local dragStart, startPos

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

TopBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

print("Suture Server UI 已加载")
