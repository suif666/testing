-- Roblox WindUI 风格 AI 聊天界面组件 (点按空白处隐藏菜单)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- 1. Tween 动画辅助函数
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

-- 2. ScreenGui 根节点
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WindUI_AIChat"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- 尺寸配置 (620 x 400)
local NormalSize = UDim2.fromOffset(620, 400)
local NormalPos = UDim2.new(0.5, -310, 0.5, -200)

-- 主窗口
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 10)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Theme.Outline
MainStroke.Thickness = 1

-- 打开动画
CreateTween(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = NormalSize,
    Position = NormalPos
})

-- ==========================================
-- 3. 右上角控制按键
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

local function AddButtonHover(btn, defaultBg, hoverBg)
    btn.MouseEnter:Connect(function()
        CreateTween(btn, TweenInfo.new(0.15), {BackgroundColor3 = hoverBg})
    end)
    btn.MouseLeave:Connect(function()
        CreateTween(btn, TweenInfo.new(0.15), {BackgroundColor3 = defaultBg})
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
    AddButtonHover(btn, btn.BackgroundColor3, hoverColor)
    return btn
end

local MinBtn = CreateControlButton("-", false)
local CloseBtn = CreateControlButton("X", true)

CloseBtn.MouseButton1Click:Connect(function()
    local t = CreateTween(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0)
    })
    t.Completed:Connect(function()
        ScreenGui:Destroy()
    end)
end)

-- ==========================================
-- 4. 悬浮球 (最小化模式)
-- ==========================================
local FloatingBall = Instance.new("TextButton")
FloatingBall.Name = "FloatingBall"
FloatingBall.Size = UDim2.fromOffset(44, 44)
FloatingBall.Position = UDim2.new(0.9, -50, 0.85, -50)
FloatingBall.BackgroundColor3 = Theme.Accent
FloatingBall.Text = "AI"
FloatingBall.TextColor3 = Theme.Text
FloatingBall.TextSize = 15
FloatingBall.Font = Enum.Font.GothamBold
FloatingBall.Visible = false
FloatingBall.AutoButtonColor = false
FloatingBall.Parent = ScreenGui

local BallCorner = Instance.new("UICorner", FloatingBall)
BallCorner.CornerRadius = UDim.new(1, 0)

AddButtonHover(FloatingBall, Theme.Accent, Theme.AccentHover)

local dragging, dragStart, startPos
FloatingBall.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = FloatingBall.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        FloatingBall.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

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

FloatingBall.MouseButton1Click:Connect(function()
    CreateTween(FloatingBall, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0)
    }).Completed:Connect(function()
        FloatingBall.Visible = false
        MainFrame.Visible = true
        MainFrame.Position = FloatingBall.Position
        CreateTween(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = NormalSize,
            Position = NormalPos
        })
    end)
end)

-- ==========================================
-- 5. 侧边栏
-- ==========================================
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 160, 1, 0)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local NewChatBtn = Instance.new("TextButton")
NewChatBtn.Size = UDim2.new(1, -16, 0, 32)
NewChatBtn.Position = UDim2.new(0, 8, 0, 8)
NewChatBtn.BackgroundColor3 = Theme.Accent
NewChatBtn.Text = "+ 新对话"
NewChatBtn.TextColor3 = Theme.Text
NewChatBtn.Font = Enum.Font.GothamBold
NewChatBtn.TextSize = 13
NewChatBtn.AutoButtonColor = false
NewChatBtn.Parent = Sidebar

local NewChatCorner = Instance.new("UICorner", NewChatBtn)
NewChatCorner.CornerRadius = UDim.new(0, 6)

AddButtonHover(NewChatBtn, Theme.Accent, Theme.AccentHover)

local ArchiveLabel = Instance.new("TextLabel")
ArchiveLabel.Size = UDim2.new(1, -16, 0, 18)
ArchiveLabel.Position = UDim2.new(0, 8, 0, 44)
ArchiveLabel.BackgroundTransparency = 1
ArchiveLabel.Text = "历史归档"
ArchiveLabel.TextColor3 = Theme.TextSub
ArchiveLabel.Font = Enum.Font.Gotham
ArchiveLabel.TextSize = 11
ArchiveLabel.TextXAlignment = Enum.TextXAlignment.Left
ArchiveLabel.Parent = Sidebar

local HistoryScroll = Instance.new("ScrollingFrame")
HistoryScroll.Size = UDim2.new(1, -10, 1, -68)
HistoryScroll.Position = UDim2.new(0, 5, 0, 64)
HistoryScroll.BackgroundTransparency = 1
HistoryScroll.ScrollBarThickness = 2
HistoryScroll.Parent = Sidebar

local HistoryLayout = Instance.new("UIListLayout")
HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
HistoryLayout.Padding = UDim.new(0, 4)
HistoryLayout.Parent = HistoryScroll

HistoryLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    HistoryScroll.CanvasSize = UDim2.new(0, 0, 0, HistoryLayout.AbsoluteContentSize.Y + 10)
end)

local function UpdateSidebarSelection(activeBtn)
    for _, child in ipairs(HistoryScroll:GetChildren()) do
        if child:IsA("TextButton") then
            if child == activeBtn then
                CreateTween(child, TweenInfo.new(0.2), {
                    BackgroundColor3 = Theme.Accent,
                    TextColor3 = Theme.Text
                })
            else
                CreateTween(child, TweenInfo.new(0.2), {
                    BackgroundColor3 = Theme.Card,
                    TextColor3 = Theme.TextSub
                })
            end
        end
    end
end

-- ==========================================
-- 6. 右侧聊天与输入区域
-- ==========================================
local ChatArea = Instance.new("Frame")
ChatArea.Size = UDim2.new(1, -160, 1, -36)
ChatArea.Position = UDim2.new(0, 160, 0, 36)
ChatArea.BackgroundTransparency = 1
ChatArea.Parent = MainFrame

local MessageScroll = Instance.new("ScrollingFrame")
MessageScroll.Size = UDim2.new(1, -16, 1, -54)
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
    MessageScroll.CanvasPosition = Vector2.new(0, 99999)
end)

local InputContainer = Instance.new("Frame")
InputContainer.Size = UDim2.new(1, -16, 0, 36)
InputContainer.Position = UDim2.new(0, 8, 1, -44)
InputContainer.BackgroundColor3 = Theme.Card
InputContainer.Parent = ChatArea

local InputCorner = Instance.new("UICorner", InputContainer)
InputCorner.CornerRadius = UDim.new(0, 6)

local InputBox = Instance.new("TextBox")
InputBox.Size = UDim2.new(1, -62, 1, 0)
InputBox.Position = UDim2.new(0, 8, 0, 0)
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
SendBtn.Size = UDim2.fromOffset(44, 26)
SendBtn.Position = UDim2.new(1, -48, 0.5, -13)
SendBtn.BackgroundColor3 = Theme.Accent
SendBtn.Text = "发送"
SendBtn.TextColor3 = Theme.Text
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextSize = 12
SendBtn.AutoButtonColor = false
SendBtn.Parent = InputContainer

local SendCorner = Instance.new("UICorner", SendBtn)
SendCorner.CornerRadius = UDim.new(0, 4)

AddButtonHover(SendBtn, Theme.Accent, Theme.AccentHover)

-- ==========================================
-- 7. 长按 / 右键 ContextMenu 浮窗 (点击空白自动消失)
-- ==========================================
local ContextMenu = Instance.new("Frame")
ContextMenu.Name = "ContextMenu"
ContextMenu.Size = UDim2.fromOffset(110, 68)
ContextMenu.BackgroundColor3 = Theme.Card
ContextMenu.BorderSizePixel = 0
ContextMenu.Visible = false
ContextMenu.ZIndex = 10
ContextMenu.Parent = ScreenGui

local ContextCorner = Instance.new("UICorner", ContextMenu)
ContextCorner.CornerRadius = UDim.new(0, 6)

local ContextStroke = Instance.new("UIStroke", ContextMenu)
ContextStroke.Color = Theme.Outline
ContextStroke.Thickness = 1

local ContextLayout = Instance.new("UIListLayout")
ContextLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContextLayout.Padding = UDim.new(0, 2)
ContextLayout.Parent = ContextMenu

local ContextPadding = Instance.new("UIPadding", ContextMenu)
ContextPadding.PaddingTop = UDim.new(0, 4)
ContextPadding.PaddingBottom = UDim.new(0, 4)
ContextPadding.PaddingLeft = UDim.new(0, 4)
ContextPadding.PaddingRight = UDim.new(0, 4)

local function CreateContextItem(text, layoutOrder)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = Theme.Card
    btn.Text = text
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.ZIndex = 11
    btn.AutoButtonColor = false
    btn.LayoutOrder = layoutOrder
    btn.Parent = ContextMenu

    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 4)

    AddButtonHover(btn, Theme.Card, Theme.CardHover)
    return btn
end

local CopyAllBtn = CreateContextItem("全选高亮", 1)
local PasteToInputBtn = CreateContextItem("填入输入框", 2)

local ActiveTargetBox = nil
local ActiveTargetText = ""

local function HideContextMenu()
    ContextMenu.Visible = false
end

-- 全局点击检测：点击菜单范围外的空白区域立即隐藏菜单
UserInputService.InputBegan:Connect(function(input)
    if ContextMenu.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        local pos = input.Position
        local guiPos = ContextMenu.AbsolutePosition
        local guiSize = ContextMenu.AbsoluteSize
        if pos.X < guiPos.X or pos.X > guiPos.X + guiSize.X or pos.Y < guiPos.Y or pos.Y > guiPos.Y + guiSize.Y then
            HideContextMenu()
        end
    end
end)

-- 全选高亮该条消息
CopyAllBtn.MouseButton1Click:Connect(function()
    if ActiveTargetBox then
        ActiveTargetBox:CaptureFocus()
        ActiveTargetBox.SelectionStart = 1
        ActiveTargetBox.CursorPosition = #ActiveTargetBox.Text + 1
    end
    HideContextMenu()
end)

-- 填入下方输入框
PasteToInputBtn.MouseButton1Click:Connect(function()
    if ActiveTargetText ~= "" then
        InputBox.Text = ActiveTargetText
        InputBox:CaptureFocus()
    end
    HideContextMenu()
end)

local function ShowContextMenuAt(pos, targetBox, text)
    ActiveTargetBox = targetBox
    ActiveTargetText = text
    ContextMenu.Position = UDim2.fromOffset(pos.X, pos.Y - 36)
    ContextMenu.Visible = true
    ContextMenu.Size = UDim2.fromOffset(110, 0)
    CreateTween(ContextMenu, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(110, 68)
    })
end

-- ==========================================
-- 8. 核心隔离逻辑 & 可选择复制消息气泡
-- ==========================================
local Sessions = {}
local CurrentSessionId = nil
local SessionCounter = 0

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

    local MsgBox = Instance.new("TextBox")
    MsgBox.Size = UDim2.new(1, -16, 1, -12)
    MsgBox.Position = UDim2.new(0, 8, 0, 6)
    MsgBox.BackgroundTransparency = 1
    MsgBox.Text = text
    MsgBox.TextColor3 = Theme.Text
    MsgBox.Font = Enum.Font.Gotham
    MsgBox.TextSize = 12
    MsgBox.TextWrapped = true
    MsgBox.TextXAlignment = Enum.TextXAlignment.Left
    MsgBox.TextYAlignment = Enum.TextYAlignment.Top
    MsgBox.TextEditable = false          -- 不可更改文本
    MsgBox.ClearTextOnFocus = false
    MsgBox.Active = true
    MsgBox.Parent = Bubble

    -- 长按/右键触发弹窗
    local holdThread = nil
    MsgBox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            ShowContextMenuAt(input.Position, MsgBox, text)
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local startPos = input.Position
            holdThread = task.delay(0.4, function()
                ShowContextMenuAt(startPos, MsgBox, text)
            end)
        end
    end)

    MsgBox.InputEnded:Connect(function(input)
        if holdThread then
            task.cancel(holdThread)
            holdThread = nil
        end
    end)

    local TextBound = TextService:GetTextSize(
        text, 12, Enum.Font.Gotham, Vector2.new(250, 2000)
    )
    
    local bubbleWidth = math.clamp(TextBound.X + 20, 50, 270)
    local bubbleHeight = TextBound.Y + 14
    
    RowFrame.Size = UDim2.new(1, 0, 0, bubbleHeight)
    local finalPosX = isUser and UDim2.new(1, -bubbleWidth, 0, 0) or UDim2.new(0, 0, 0, 0)
    
    if animate then
        Bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
        Bubble.Position = finalPosX + UDim2.fromOffset(0, 10)
        Bubble.BackgroundTransparency = 1
        MsgBox.TextTransparency = 1

        CreateTween(Bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(bubbleWidth, bubbleHeight),
            Position = finalPosX,
            BackgroundTransparency = 0
        })
        CreateTween(MsgBox, TweenInfo.new(0.2), {TextTransparency = 0})
    else
        Bubble.Size = UDim2.fromOffset(bubbleWidth, bubbleHeight)
        Bubble.Position = finalPosX
    end
end

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
        UpdateSidebarSelection(ItemBtn)
        LoadSession(id)
    end)

    UpdateSidebarSelection(ItemBtn)
    LoadSession(id)
end

local function SendMessage()
    local text = InputBox.Text
    if text:gsub("%s+", "") == "" or not CurrentSessionId then return end

    InputBox.Text = ""

    table.insert(Sessions[CurrentSessionId].Messages, {Sender = "User", Content = text})
    AddMessageBubble("User", text, true)

    task.delay(0.5, function()
        local aiReply = "【AI回复】收到: " .. text .. "\n(上下文隔离正常运作)"
        table.insert(Sessions[CurrentSessionId].Messages, {Sender = "AI", Content = aiReply})
        AddMessageBubble("AI", aiReply, true)
    end)
end

SendBtn.MouseButton1Click:Connect(SendMessage)
InputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then SendMessage() end
end)

NewChatBtn.MouseButton1Click:Connect(CreateNewSession)

-- 初始化生成第一个新对话
CreateNewSession()
