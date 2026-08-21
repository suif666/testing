-- Roblox WindUI 风格 AI 聊天界面组件 (动画精简版)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- 1. 动画通用配置与辅助函数
-- ==========================================
local function CreateTween(instance, tweenInfoProps, goalProps)
    local tween = TweenService:Create(instance, tweenInfoProps, goalProps)
    tween:Play()
    return tween
end

-- 配色方案 (WindUI 暗色风格)
local Theme = {
    Background = Color3.fromRGB(20, 20, 24),
    Sidebar = Color3.fromRGB(26, 26, 32),
    Card = Color3.fromRGB(34, 34, 42),
    CardHover = Color3.fromRGB(44, 44, 54),
    Accent = Color3.fromRGB(99, 102, 241),
    AccentHover = Color3.fromRGB(120, 123, 255),
    UserBubble = Color3.fromRGB(79, 70, 229),
    AIBubble = Color3.fromRGB(38, 38, 48),
    Text = Color3.fromRGB(240, 240, 245),
    TextSub = Color3.fromRGB(150, 150, 165),
    Outline = Color3.fromRGB(45, 45, 55)
}

-- 2. UI 根节点
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WindUI_AIChat"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- 主窗口 (缩小尺寸: 620 x 400)
local NormalSize = UDim2.fromOffset(620, 400)
local NormalPos = UDim2.new(0.5, -310, 0.5, -200)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = NormalSize
MainFrame.Position = NormalPos
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Theme.Outline
MainStroke.Thickness = 1

-- 入场打开动画
MainFrame.ScaleScale = 0.8
MainFrame.Size = UDim2.fromOffset(0, 0)
CreateTween(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = NormalSize
})

-- ==========================================
-- 3. 右上角控制按键与动画 (修复乱码问题)
-- ==========================================
local ControlBar = Instance.new("Frame")
ControlBar.Size = UDim2.new(1, 0, 0, 36)
ControlBar.BackgroundTransparency = 1
ControlBar.Parent = MainFrame

local ControlLayout = Instance.new("UIListLayout")
ControlLayout.FillDirection = Enum.FillDirection.Horizontal
ControlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ControlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ControlLayout.Padding = UDim.new(0, 6)
ControlLayout.Parent = ControlBar

local ControlPadding = Instance.new("UIPadding", ControlBar)
ControlPadding.PaddingRight = UDim.new(0, 10)

local function AddButtonAnimation(btn, defaultBg, hoverBg)
    btn.MouseEnter:Connect(function()
        CreateTween(btn, TweenInfo.new(0.2), {BackgroundColor3 = hoverBg, Size = UDim2.fromOffset(26, 26)})
    end)
    btn.MouseLeave:Connect(function()
        CreateTween(btn, TweenInfo.new(0.2), {BackgroundColor3 = defaultBg, Size = UDim2.fromOffset(24, 24)})
    end)
    btn.MouseButton1Down:Connect(function()
        CreateTween(btn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(22, 22)})
    end)
    btn.MouseButton1Up:Connect(function()
        CreateTween(btn, TweenInfo.new(0.1), {Size = UDim2.fromOffset(26, 26)})
    end)
end

local function CreateControlButton(iconText, isClose)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(24, 24)
    btn.BackgroundColor3 = isClose and Color3.fromRGB(180, 50, 50) or Theme.Card
    btn.TextColor3 = Theme.Text
    btn.Text = iconText
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.Parent = ControlBar
    
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 6)

    local hoverColor = isClose and Color3.fromRGB(220, 60, 60) or Theme.CardHover
    AddButtonAnimation(btn, btn.BackgroundColor3, hoverColor)
    return btn
end

-- 使用 100% 兼容的通用字符，绝不显示为“口”
local MinBtn = CreateControlButton("-", false)  -- 最小化
local MaxBtn = CreateControlButton("[]", false) -- 全屏
local CloseBtn = CreateControlButton("X", true)  -- 关闭

-- 全屏切换逻辑与动画
local isMaximized = false
MaxBtn.MouseButton1Click:Connect(function()
    isMaximized = not isMaximized
    local targetSize = isMaximized and UDim2.new(1, 0, 1, 0) or NormalSize
    local targetPos = isMaximized and UDim2.new(0, 0, 0, 0) or NormalPos
    
    CreateTween(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = targetSize,
        Position = targetPos
    })
end)

-- 关闭动画
CloseBtn.MouseButton1Click:Connect(function()
    local t = CreateTween(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0),
        Position = UDim2.new(MainFrame.Position.X.Scale, MainFrame.Position.X.Offset + MainFrame.AbsoluteSize.X/2, MainFrame.Position.Y.Scale, MainFrame.Position.Y.Offset + MainFrame.AbsoluteSize.Y/2)
    })
    t.Completed:Connect(function()
        ScreenGui:Destroy()
    end)
end)

-- 4. 悬浮球 (最小化模式及动画)
local FloatingBall = Instance.new("TextButton")
FloatingBall.Name = "FloatingBall"
FloatingBall.Size = UDim2.fromOffset(0, 0)
FloatingBall.Position = UDim2.new(0.9, -50, 0.85, -50)
FloatingBall.BackgroundColor3 = Theme.Accent
FloatingBall.Text = "AI"
FloatingBall.TextColor3 = Theme.Text
FloatingBall.TextSize = 16
FloatingBall.Font = Enum.Font.GothamBold
FloatingBall.Visible = false
FloatingBall.AutoButtonColor = false
FloatingBall.Parent = ScreenGui

local BallCorner = Instance.new("UICorner", FloatingBall)
BallCorner.CornerRadius = UDim.new(1, 0)

-- 悬浮球 Hover 动效
FloatingBall.MouseEnter:Connect(function()
    CreateTween(FloatingBall, TweenInfo.new(0.2), {BackgroundColor3 = Theme.AccentHover, Size = UDim2.fromOffset(50, 50)})
end)
FloatingBall.MouseLeave:Connect(function()
    CreateTween(FloatingBall, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Accent, Size = UDim2.fromOffset(44, 44)})
end)

-- 拖拽逻辑
local dragging, dragInput, dragStart, startPos
FloatingBall.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = FloatingBall.Position
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

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- 最小化动画
MinBtn.MouseButton1Click:Connect(function()
    local t = CreateTween(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0),
        Position = FloatingBall.Position
    })
    t.Completed:Connect(function()
        MainFrame.Visible = false
        FloatingBall.Visible = true
        FloatingBall.Size = UDim2.fromOffset(0, 0)
        CreateTween(FloatingBall, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(44, 44)
        })
    end)
end)

-- 恢复主界面动画
FloatingBall.MouseButton1Click:Connect(function()
    CreateTween(FloatingBall, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0)
    }).Completed:Connect(function()
        FloatingBall.Visible = false
        MainFrame.Visible = true
        MainFrame.Position = FloatingBall.Position
        CreateTween(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = isMaximized and UDim2.new(1, 0, 1, 0) or NormalSize,
            Position = isMaximized and UDim2.new(0, 0, 0, 0) or NormalPos
        })
    end)
end)

-- ==========================================
-- 5. 侧边栏 (对话列表与新建)
-- ==========================================
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 170, 1, 0)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local NewChatBtn = Instance.new("TextButton")
NewChatBtn.Size = UDim2.new(1, -20, 0, 32)
NewChatBtn.Position = UDim2.new(0, 10, 0, 10)
NewChatBtn.BackgroundColor3 = Theme.Accent
NewChatBtn.Text = "+ 新对话"
NewChatBtn.TextColor3 = Theme.Text
NewChatBtn.Font = Enum.Font.GothamBold
NewChatBtn.TextSize = 13
NewChatBtn.AutoButtonColor = false
NewChatBtn.Parent = Sidebar

local NewChatCorner = Instance.new("UICorner", NewChatBtn)
NewChatCorner.CornerRadius = UDim.new(0, 6)

AddButtonAnimation(NewChatBtn, Theme.Accent, Theme.AccentHover)

local ArchiveLabel = Instance.new("TextLabel")
ArchiveLabel.Size = UDim2.new(1, -20, 0, 18)
ArchiveLabel.Position = UDim2.new(0, 10, 0, 48)
ArchiveLabel.BackgroundTransparency = 1
ArchiveLabel.Text = "历史归档"
ArchiveLabel.TextColor3 = Theme.TextSub
ArchiveLabel.Font = Enum.Font.Gotham
ArchiveLabel.TextSize = 11
ArchiveLabel.TextXAlignment = Enum.TextXAlignment.Left
ArchiveLabel.Parent = Sidebar

local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, -10, 1, -72)
HistoryScroll.Position = UDim2.new(0, 5, 0, 68)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.ScrollBarThickness = 2
HistoryScroll.Parent = Sidebar

local HistoryLayout = Instance.new("UIListLayout")
HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistoryLayout.Padding = UDim.new(0, 4)
HistoryLayout.Parent = HistoryScroll

-- ==========================================
-- 6. 右侧聊天区域与输入框
-- ==========================================
local ChatArea = Instance.new("Frame")
ChatArea.Size = UDim2.new(1, -170, 1, -36)
ChatArea.Position = UDim2.new(0, 170, 0, 36)
ChatArea.BackgroundTransparency = 1
ChatArea.Parent = MainFrame

local MessageScroll = Instance.new("ScrollingFrame")
MessageScroll.Size = UDim2.new(1, -16, 1, -56)
MessageScroll.Position = UDim2.new(0, 8, 0, 0)
MessageScroll.BackgroundTransparency = 1
MessageScroll.ScrollBarThickness = 3
MessageScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
MessageScroll.Parent = ChatArea

local MessageLayout = Instance.new("UIListLayout")
MessageLayout.SortOrder = Enum.SortOrder.LayoutOrder
MessageLayout.Padding = UDim.new(0, 8)
MessageLayout.Parent = MessageScroll

MessageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    MessageScroll.CanvasSize = UDim2.new(0, 0, 0, MessageLayout.AbsoluteContentSize.Y + 12)
    MessageScroll.CanvasPosition = Vector2.new(0, MessageScroll.CanvasSize.Y.Offset)
end)

-- 输入框
local InputContainer = Instance.new("Frame")
InputContainer.Size = UDim2.new(1, -16, 0, 38)
InputContainer.Position = UDim2.new(0, 8, 1, -46)
InputContainer.BackgroundColor3 = Theme.Card
InputContainer.Parent = ChatArea

local InputCorner = Instance.new("UICorner", InputContainer)
InputCorner.CornerRadius = UDim.new(0, 6)

local InputBox = Instance.new("TextBox")
InputBox.Size = UDim2.new(1, -48, 1, 0)
InputBox.Position = UDim2.new(0, 10, 0, 0)
InputBox.BackgroundTransparency = 1
InputBox.PlaceholderText = "发送消息给 AI..."
InputBox.PlaceholderColor3 = Theme.TextSub
InputBox.Text = ""
InputBox.TextColor3 = Theme.Text
InputBox.Font = Enum.Font.Gotham
InputBox.TextSize = 13
InputBox.TextXAlignment = Enum.TextXAlignment.Left
InputBox.ClearTextOnFocus = false
InputBox.Parent = InputContainer

local SendBtn = Instance.new("TextButton")
SendBtn.Size = UDim2.fromOffset(28, 26)
SendBtn.Position = UDim2.new(1, -34, 0.5, -13)
SendBtn.BackgroundColor3 = Theme.Accent
SendBtn.Text = ">" -- 标准高兼容字符
SendBtn.TextColor3 = Theme.Text
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextSize = 13
SendBtn.AutoButtonColor = false
SendBtn.Parent = InputContainer

local SendCorner = Instance.new("UICorner", SendBtn)
SendCorner.CornerRadius = UDim.new(0, 4)

AddButtonAnimation(SendBtn, Theme.Accent, Theme.AccentHover)

-- ==========================================
-- 7. 核心隔离逻辑 & 消息气泡动画
-- ==========================================
local Sessions = {}
local CurrentSessionId = nil
local SessionCounter = 0

-- 带有弹出动效的气泡创建函数
local function AddMessageBubble(sender, text, animate)
    local isUser = (sender == "User")
    
    local RowFrame = Instance.new("Frame")
    RowFrame.Size = UDim2.new(1, 0, 0, 0)
    RowFrame.BackgroundTransparency = 1
    RowFrame.Parent = MessageScroll

    local Bubble = Instance.new("Frame")
    Bubble.BackgroundColor3 = isUser and Theme.UserBubble or Theme.AIBubble
    Bubble.Parent = RowFrame

    local BubbleCorner = Instance.new("UICorner", Bubble)
    BubbleCorner.CornerRadius = UDim.new(0, 8)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -16, 1, -12)
    Label.Position = UDim2.new(0, 8, 0, 6)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 12
    Label.TextWrapped = true
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Bubble

    -- 计算文本占用高度与宽度
    local TextBound = game:GetService("TextService"):GetTextSize(
        text, 12, Enum.Font.Gotham, Vector2.new(260, 2000)
    )
    
    local bubbleWidth = math.clamp(TextBound.X + 20, 50, 280)
    local bubbleHeight = TextBound.Y + 14
    
    RowFrame.Size = UDim2.new(1, 0, 0, bubbleHeight)

    local finalPosX = isUser and UDim2.new(1, -bubbleWidth, 0, 0) or UDim2.new(0, 0, 0, 0)
    
    if animate then
        -- 初始状态（下偏+透明）
        Bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
        Bubble.Position = finalPosX + UDim2.fromOffset(0, 10)
        Bubble.BackgroundTransparency = 1
        Label.TextTransparency = 1

        -- 淡入+上浮弹出动画
        CreateTween(Bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(bubbleWidth, bubbleHeight),
            Position = finalPosX,
            BackgroundTransparency = 0
        })
        CreateTween(Label, TweenInfo.new(0.2), {TextTransparency = 0})
    else
        Bubble.Size = UDim2.fromOffset(bubbleWidth, bubbleHeight)
        Bubble.Position = finalPosX
    end
end

-- 加载选中的对话
local function LoadSession(sessionId)
    CurrentSessionId = sessionId
    
    for _, child in ipairs(MessageScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local session = Sessions[sessionId]
    if session then
        for _, msg in ipairs(session.Messages) do
            AddMessageBubble(msg.Sender, msg.Content, false)
        end
    end
end

-- 创建新对话
local function CreateNewSession()
    SessionCounter = SessionCounter + 1
    local id = "Session_" .. SessionCounter
    
    Sessions[id] = {
        Title = "对话 " .. SessionCounter,
        Messages = {}
    }

    local ItemBtn = Instance.new("TextButton")
    ItemBtn.Size = UDim2.new(1, -4, 0, 28)
    ItemBtn.BackgroundColor3 = Theme.Card
    ItemBtn.Text = "  " .. Sessions[id].Title
    ItemBtn.TextColor3 = Theme.TextSub
    ItemBtn.Font = Enum.Font.Gotham
    ItemBtn.TextSize = 12
    ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
    ItemBtn.AutoButtonColor = false
    ItemBtn.Parent = HistoryScroll

    local ItemCorner = Instance.new("UICorner", ItemBtn)
    ItemCorner.CornerRadius = UDim.new(0, 5)

    -- 点击侧边栏按钮交互动效
    ItemBtn.MouseEnter:Connect(function()
        if CurrentSessionId ~= id then
            CreateTween(ItemBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.CardHover})
        end
    end)
    ItemBtn.MouseLeave:Connect(function()
        if CurrentSessionId ~= id then
            CreateTween(ItemBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.Card})
        end
    end)

    ItemBtn.MouseButton1Click:Connect(function()
        -- 恢复其他按钮颜色
        for _, btn in ipairs(HistoryScroll:GetChildren()) do
            if btn:IsA("TextButton") then
                CreateTween(btn, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Card, TextColor3 = Theme.TextSub})
            end
        end
        -- 高亮选中按钮
        CreateTween(ItemBtn, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Accent, TextColor3 = Theme.Text})
        LoadSession(id)
    end)

    -- 自动切到新建立的对话
    ItemBtn.BackgroundColor3 = Theme.Accent
    ItemBtn.TextColor3 = Theme.Text
    LoadSession(id)
end

-- 发送消息
local function SendMessage()
    local text = InputBox.Text
    if text:gsub("%s+", "") == "" or not CurrentSessionId then return end

    InputBox.Text = ""

    -- 保存并带动画追加用户消息
    table.insert(Sessions[CurrentSessionId].Messages, {Sender = "User", Content = text})
    AddMessageBubble("User", text, true)

    -- 模拟 AI 异步延迟回复
    task.delay(0.5, function()
        local aiReply = "【AI回复】已接收: " .. text .. "\n(上下文隔离正常运作)"
        table.insert(Sessions[CurrentSessionId].Messages, {Sender = "AI", Content = aiReply})
        AddMessageBubble("AI", aiReply, true)
    end)
end

SendBtn.MouseButton1Click:Connect(SendMessage)
InputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then SendMessage() end
end)

NewChatBtn.MouseButton1Click:Connect(CreateNewSession)

-- 默认进入第一个新对话
CreateNewSession()
