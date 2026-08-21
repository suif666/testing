-- 聊天系统 GUI - 简单好看版
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==================== 创建 GUI ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SimpleChatSystem"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- 主框架
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 400, 0, 500)
mainFrame.Position = UDim2.new(1, -420, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

-- 圆角
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

-- 边框光
local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(80, 80, 100)
mainStroke.Thickness = 1.5
mainStroke.Parent = mainFrame

-- 顶部栏
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 50)
topBar.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
topBar.Parent = mainFrame

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = topBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.new(0, 15, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🌟 聊天系统 🌟"
title.TextColor3 = Color3.fromRGB(200, 200, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = topBar

-- 关闭按钮
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -45, 0, 5)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.TextScaled = true
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = topBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = closeBtn

-- 聊天区域（左右两个）
local chatArea = Instance.new("Frame")
chatArea.Size = UDim2.new(1, 0, 1, -120)
chatArea.Position = UDim2.new(0, 0, 0, 50)
chatArea.BackgroundTransparency = 1
chatArea.Parent = mainFrame

-- 左边聊天栏
local leftChat = Instance.new("Frame")
leftChat.Size = UDim2.new(0.48, 0, 1, 0)
leftChat.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
leftChat.Parent = chatArea
local leftCorner = Instance.new("UICorner")
leftCorner.CornerRadius = UDim.new(0, 10)
leftCorner.Parent = leftChat

local leftTitle = Instance.new("TextLabel")
leftTitle.Size = UDim2.new(1, 0, 0, 30)
leftTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
leftTitle.Text = "💬 群聊"
leftTitle.TextColor3 = Color3.fromRGB(180, 180, 255)
leftTitle.TextScaled = true
leftTitle.Font = Enum.Font.GothamSemibold
leftTitle.Parent = leftChat

local leftList = Instance.new("ScrollingFrame")
leftList.Size = UDim2.new(1, -10, 1, -50)
leftList.Position = UDim2.new(0, 5, 0, 35)
leftList.BackgroundTransparency = 1
leftList.ScrollBarThickness = 4
leftList.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
leftList.Parent = leftChat

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 8)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftList

local leftPadding = Instance.new("UIPadding")
leftPadding.PaddingBottom = UDim.new(0, 10)
leftPadding.PaddingTop = UDim.new(0, 10)
leftPadding.Parent = leftList

-- 右边聊天栏（私聊）
local rightChat = Instance.new("Frame")
rightChat.Size = UDim2.new(0.48, 0, 1, 0)
rightChat.Position = UDim2.new(0.52, 0, 0, 0)
rightChat.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
rightChat.Parent = chatArea
local rightCorner = Instance.new("UICorner")
rightCorner.CornerRadius = UDim.new(0, 10)
rightCorner.Parent = rightChat

local rightTitle = Instance.new("TextLabel")
rightTitle.Size = UDim2.new(1, 0, 0, 30)
rightTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
rightTitle.Text = "👤 私聊"
rightTitle.TextColor3 = Color3.fromRGB(180, 180, 255)
rightTitle.TextScaled = true
rightTitle.Font = Enum.Font.GothamSemibold
rightTitle.Parent = rightChat

local rightList = Instance.new("ScrollingFrame")
rightList.Size = UDim2.new(1, -10, 1, -50)
rightList.Position = UDim2.new(0, 5, 0, 35)
rightList.BackgroundTransparency = 1
rightList.ScrollBarThickness = 4
rightList.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 150)
rightList.Parent = rightChat
local rightLayout = Instance.new("UIListLayout")
rightLayout.Padding = UDim.new(0, 8)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightList
local rightPadding = Instance.new("UIPadding")
rightPadding.PaddingBottom = UDim.new(0, 10)
rightPadding.PaddingTop = UDim.new(0, 10)
rightPadding.Parent = rightList

-- 输入框
local inputFrame = Instance.new("Frame")
inputFrame.Size = UDim2.new(1, 0, 0, 70)
inputFrame.Position = UDim2.new(0, 0, 1, -70)
inputFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
inputFrame.Parent = mainFrame
local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 12)
inputCorner.Parent = inputFrame

local input = Instance.new("TextBox")
input.Size = UDim2.new(0.85, -20, 0.7, 0)
input.Position = UDim2.new(0, 10, 0, 10)
input.PlaceholderText = "输入消息..."
input.Text = ""
input.TextColor3 = Color3.fromRGB(255, 255, 255)
input.PlaceholderColor3 = Color3.fromRGB(150, 150, 170)
input.BackgroundTransparency = 1
input.TextScaled = true
input.Font = Enum.Font.Gotham
input.ClearTextOnFocus = false
input.Parent = inputFrame

-- 发送按钮
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(0.13, 0, 0.7, 0)
sendBtn.Position = UDim2.new(0.88, 0, 0, 10)
sendBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 255)
sendBtn.Text = "发送"
sendBtn.TextColor3 = Color3.new(1, 1, 1)
sendBtn.TextScaled = true
sendBtn.Font = Enum.Font.GothamBold
sendBtn.Parent = inputFrame
local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 8)
sendCorner.Parent = sendBtn

-- ==================== 聊天函数 ====================
local function addChatMessage(text, color, side)
    local chatFrame = side == "left" and leftList or rightList
    local isPlayer = side == "left"
    
    local msg = Instance.new("Frame")
    msg.Size = UDim2.new(1, 0, 0, 35)
    msg.BackgroundColor3 = isPlayer and Color3.fromRGB(50, 80, 130) or Color3.fromRGB(40, 40, 50)
    msg.BackgroundTransparency = 0.3
    msg.Parent = chatFrame
    
    local msgCorner = Instance.new("UICorner")
    msgCorner.CornerRadius = UDim.new(0, 6)
    msgCorner.Parent = msg
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -10, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = msg
end

-- ==================== 发送逻辑（现在只是打印，AI等会加） ====================
sendBtn.MouseButton1Click:Connect(function()
    local msg = input.Text
    if msg == "" then return end
    
    -- 显示消息
    addChatMessage("你: " .. msg, Color3.fromRGB(255, 255, 200), "left")
    input.Text = ""
    
    -- 打印给控制台（你可以自己加 AI 逻辑）
    print("[你发送] " .. msg)
    
    -- TODO: 这里等你给令牌后我再加 AI 转发
end)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

-- ==================== 预设消息（可选好看） ====================
local function sendDemoMessage()
    addChatMessage("系统: 欢迎来到聊天系统！", Color3.fromRGB(100, 255, 100), "left")
end

-- 启动时显示欢迎
sendDemoMessage()

-- 让滚动条自动滚到底
RunService.Heartbeat:Connect(function()
    leftList.CanvasPosition = Vector2.new(0, leftList.AbsoluteContentSize.Y)
    rightList.CanvasPosition = Vector2.new(0, rightList.AbsoluteContentSize.Y)
end)

print("✅ 聊天系统 GUI 已加载！（等你给令牌我加 AI 功能）")
