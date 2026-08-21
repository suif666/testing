-- Roblox WindUI 风格 AI 聊天界面组件
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- 1. 创建 UI 根节点与样式配置
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WindUI_AIChat"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- 配色方案 (WindUI 暗色风格)
local Theme = {
    Background = Color3.fromRGB(20, 20, 24),
    Sidebar = Color3.fromRGB(26, 26, 32),
    Card = Color3.fromRGB(34, 34, 42),
    Accent = Color3.fromRGB(99, 102, 241), -- 靛蓝色主调
    UserBubble = Color3.fromRGB(79, 70, 229),
    AIBubble = Color3.fromRGB(38, 38, 48),
    Text = Color3.fromRGB(240, 240, 245),
    TextSub = Color3.fromRGB(150, 150, 165),
    Outline = Color3.fromRGB(45, 45, 55)
}

-- 主窗口
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(780, 520)
MainFrame.Position = UDim2.new(0.5, -390, 0.5, -260)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 12)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Theme.Outline
MainStroke.Thickness = 1

-- ==========================================
-- 2. 右上角控制按键与窗口状态管理
-- ==========================================
local ControlBar = Instance.new("Frame")
ControlBar.Size = UDim2.new(1, 0, 0, 40)
ControlBar.BackgroundTransparency = 1
ControlBar.Parent = MainFrame

local ControlLayout = Instance.new("UIListLayout")
ControlLayout.FillDirection = Enum.FillDirection.Horizontal
ControlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ControlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ControlLayout.Padding = UDim.new(0, 8)
ControlLayout.Parent = ControlBar

local ControlPadding = Instance.new("UIPadding", ControlBar)
ControlPadding.PaddingRight = UDim.new(0, 12)

local function CreateControlButton(color, iconText)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(28, 28)
    btn.BackgroundColor3 = Theme.Card
    btn.TextColor3 = Theme.Text
    btn.Text = iconText
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = true
    btn.Parent = ControlBar
    
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 6)
    return btn
end

local MinBtn = CreateControlButton(nil, "—")  -- 最小化
local MaxBtn = CreateControlButton(nil, "▢")  -- 全屏
local CloseBtn = CreateControlButton(nil, "✕") -- 关闭

-- 全屏与还原状态
local isMaximized = false
local defaultSize = UDim2.fromOffset(780, 520)
local defaultPos = UDim2.new(0.5, -390, 0.5, -260)

MaxBtn.MouseButton1Click:Connect(function()
    isMaximized = not isMaximized
    if isMaximized then
        MainFrame:TweenSizeAndPosition(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), "Out", "Quad", 0.2, true)
    else
        MainFrame:TweenSizeAndPosition(defaultSize, defaultPos, "Out", "Quad", 0.2, true)
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- 拖拽悬浮球 (最小化模式)
local FloatingBall = Instance.new("TextButton")
FloatingBall.Name = "FloatingBall"
FloatingBall.Size = UDim2.fromOffset(50, 50)
FloatingBall.Position = UDim2.new(0.9, -60, 0.8, -60)
FloatingBall.BackgroundColor3 = Theme.Accent
FloatingBall.Text = "AI"
FloatingBall.TextColor3 = Theme.Text
FloatingBall.TextSize = 18
FloatingBall.Font = Enum.Font.GothamBold
FloatingBall.Visible = false
FloatingBall.Parent = ScreenGui

local BallCorner = Instance.new("UICorner", FloatingBall)
BallCorner.CornerRadius = UDim.new(1, 0)

-- 悬浮球拖拽逻辑
local dragging, dragInput, dragStart, startPos
FloatingBall.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = FloatingBall.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

FloatingBall.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        FloatingBall.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

MinBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    FloatingBall.Visible = true
end)

FloatingBall.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    FloatingBall.Visible = false
end)

-- ==========================================
-- 3. 侧边栏 (对话列表与新建)
-- ==========================================
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 220, 1, 0)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local NewChatBtn = Instance.new("TextButton")
NewChatBtn.Size = UDim2.new(1, -24, 0, 38)
NewChatBtn.Position = UDim2.new(0, 12, 0, 12)
NewChatBtn.BackgroundColor3 = Theme.Accent
NewChatBtn.Text = "+ 新建对话"
NewChatBtn.TextColor3 = Theme.Text
NewChatBtn.Font = Enum.Font.GothamBold
NewChatBtn.TextSize = 14
NewChatBtn.Parent = Sidebar

local NewChatCorner = Instance.new("UICorner", NewChatBtn)
NewChatCorner.CornerRadius = UDim.new(0, 8)

local ArchiveLabel = Instance.new("TextLabel")
ArchiveLabel.Size = UDim2.new(1, -24, 0, 20)
ArchiveLabel.Position = UDim2.new(0, 12, 0, 60)
ArchiveLabel.BackgroundTransparency = 1
ArchiveLabel.Text = "历史归档"
ArchiveLabel.TextColor3 = Theme.TextSub
ArchiveLabel.Font = Enum.Font.Gotham
ArchiveLabel.TextSize = 12
ArchiveLabel.TextXAlignment = Enum.TextXAlignment.Left
ArchiveLabel.Parent = Sidebar

local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, -12, 1, -90)
HistoryScroll.Position = UDim2.new(0, 6, 0, 85)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.ScrollBarThickness = 2
HistoryScroll.Parent = Sidebar

local HistoryLayout = Instance.new("UIListLayout")
HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistoryLayout.Padding = UDim.new(0, 6)
HistoryLayout.Parent = HistoryScroll

-- ==========================================
-- 4. 右侧消息展示与输入区域
-- ==========================================
local ChatArea = Instance.new("Frame")
ChatArea.Size = UDim2.new(1, -220, 1, -40)
ChatArea.Position = UDim2.new(0, 220, 0, 40)
ChatArea.BackgroundTransparency = 1
ChatArea.Parent = MainFrame

local MessageScroll = Instance.new("ScrollingFrame")
MessageScroll.Size = UDim2.new(1, -24, 1, -70)
MessageScroll.Position = UDim2.new(0, 12, 0, 0)
MessageScroll.BackgroundTransparency = 1
MessageScroll.ScrollBarThickness = 4
MessageScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
MessageScroll.Parent = ChatArea

local MessageLayout = Instance.new("UIListLayout")
MessageLayout.SortOrder = Enum.SortOrder.LayoutOrder
MessageLayout.Padding = UDim.new(0, 10)
MessageLayout.Parent = MessageScroll

MessageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    MessageScroll.CanvasSize = UDim2.new(0, 0, 0, MessageLayout.AbsoluteContentSize.Y + 20)
    MessageScroll.CanvasPosition = Vector2.new(0, MessageScroll.CanvasSize.Y.Offset)
end)

-- 底部输入框
local InputContainer = Instance.new("Frame")
InputContainer.Size = UDim2.new(1, -24, 0, 44)
InputContainer.Position = UDim2.new(0, 12, 1, -54)
InputContainer.BackgroundColor3 = Theme.Card
InputContainer.Parent = ChatArea

local InputCorner = Instance.new("UICorner", InputContainer)
InputCorner.CornerRadius = UDim.new(0, 8)

local InputBox = Instance.new("TextBox")
InputBox.Size = UDim2.new(1, -60, 1, 0)
InputBox.Position = UDim2.new(0, 12, 0, 0)
InputBox.BackgroundTransparency = 1
InputBox.PlaceholderText = "给 AI 发送消息..."
InputBox.PlaceholderColor3 = Theme.TextSub
InputBox.Text = ""
InputBox.TextColor3 = Theme.Text
InputBox.Font = Enum.Font.Gotham
InputBox.TextSize = 14
InputBox.TextXAlignment = Enum.TextXAlignment.Left
InputBox.ClearTextOnFocus = false
InputBox.Parent = InputContainer

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.fromOffset(36, 30)
SendBtn.Position = UDim2.new(1, -42, 0.5, -15)
SendBtn.BackgroundColor3 = Theme.Accent
SendBtn.Text = "➔"
SendBtn.TextColor3 = Theme.Text
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextSize = 14
SendBtn.Parent = InputContainer

local SendCorner = Instance.new("UICorner", SendBtn)
SendCorner.CornerRadius = UDim.new(0, 6)

-- ==========================================
-- 5. 对话数据隔离与核心逻辑
-- ==========================================
local Sessions = {}
local CurrentSessionId = nil
local SessionCounter = 0

-- 气泡渲染逻辑
local function AddMessageBubble(sender, text)
    local isUser = (sender == "User")
    
    local RowFrame = Instance.new("Frame")
    RowFrame.Size = UDim2.new(1, 0, 0, 0)
    RowFrame.BackgroundTransparency = 1
    RowFrame.Parent = MessageScroll

    local Bubble = Instance.new("Frame")
    Bubble.BackgroundColor3 = isUser and Theme.UserBubble or Theme.AIBubble
    Bubble.Parent = RowFrame

    local BubbleCorner = Instance.new("UICorner", Bubble)
    BubbleCorner.CornerRadius = UDim.new(0, 10)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -20, 1, -16)
    Label.Position = UDim2.new(0, 10, 0, 8)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 13
    Label.TextWrapped = true
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Bubble

    -- 动态计算气泡尺寸
    local TextBound = game:GetService("TextService"):GetTextSize(
        text, 13, Enum.Font.Gotham, Vector2.new(320, 2000)
    )
    
    local bubbleWidth = math.max(TextBound.X + 24, 60)
    local bubbleHeight = TextBound.Y + 18
    
    Bubble.Size = UDim2.fromOffset(bubbleWidth, bubbleHeight)
    RowFrame.Size = UDim2.new(1, 0, 0, bubbleHeight)

    if isUser then
        Bubble.Position = UDim2.new(1, -bubbleWidth, 0, 0)
    else
        Bubble.Position = UDim2.new(0, 0, 0, 0)
    end
end

-- 加载指定对话
local function LoadSession(sessionId)
    CurrentSessionId = sessionId
    
    -- 清空界面旧气泡
    for _, child in ipairs(MessageScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    -- 恢复该 Session 的历史记录
    local session = Sessions[sessionId]
    if session then
        for _, msg in ipairs(session.Messages) do
            AddMessageBubble(msg.Sender, msg.Content)
        end
    end
end

-- 创建新对话 (隔离上下文)
local function CreateNewSession()
    SessionCounter = SessionCounter + 1
    local id = "Session_" .. SessionCounter
    
    Sessions[id] = {
        Title = "对话 " .. SessionCounter,
        Messages = {} -- 隔离的消息上下文
    }

    -- 添加到侧边栏归档
    local ItemBtn = Instance.new("TextButton")
    ItemBtn.Size = UDim2.new(1, -8, 0, 32)
    ItemBtn.BackgroundColor3 = Theme.Card
    ItemBtn.Text = "  " .. Sessions[id].Title
    ItemBtn.TextColor3 = Theme.TextSub
    ItemBtn.Font = Enum.Font.Gotham
    ItemBtn.TextSize = 13
    ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
    ItemBtn.Parent = HistoryScroll

    local ItemCorner = Instance.new("UICorner", ItemBtn)
    ItemCorner.CornerRadius = UDim.new(0, 6)

    ItemBtn.MouseButton1Click:Connect(function()
        LoadSession(id)
    end)

    LoadSession(id)
end

-- 发送消息与模拟 AI 回复
local function SendMessage()
    local text = InputBox.Text
    if text:gsub("%s+", "") == "" or not CurrentSessionId then return end

    InputBox.Text = ""

    -- 1. 保存并渲染玩家消息
    table.insert(Sessions[CurrentSessionId].Messages, {Sender = "User", Content = text})
    AddMessageBubble("User", text)

    -- 2. 模拟 AI 响应 (独立上下文)
    task.delay(0.6, function()
        local aiReply = "【AI 回复】收到你的消息: " .. text .. "\n(当前对话上下文与其它对话完全独立)"
        table.insert(Sessions[CurrentSessionId].Messages, {Sender = "AI", Content = aiReply})
        AddMessageBubble("AI", aiReply)
    end)
end

SendBtn.MouseButton1Click:Connect(SendMessage)
InputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then SendMessage() end
end)

NewChatBtn.MouseButton1Click:Connect(CreateNewSession)

-- 默认初始化第一个对话
CreateNewSession()
