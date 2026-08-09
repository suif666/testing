-- 连点器 v1 —— 独立脚本（UI 风格沿用 UI 文本提取器）
-- 用法：
--  ＋ 添加一个点击按钮　－ 删除最后一个点击按钮
--  长按某个点击按钮可设置它的每秒点击次数
--  开启连点后按 1,2,3,1,2,3... 顺序循环点击所有按钮
--  可见性按钮可隐藏/显示按钮，隐藏时照常连点

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VIM = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local function getHui()
    local ok, hui = pcall(function()
        if gethui then return gethui() end
        return nil
    end)
    return ok and hui or nil
end

-- 清理旧 UI
pcall(function()
    local old = CoreGui:FindFirstChild("AutoClickerUI")
    if old then old:Destroy() end
end)
pcall(function()
    local old = PlayerGui:FindFirstChild("AutoClickerUI")
    if old then old:Destroy() end
end)
pcall(function()
    local hui = getHui()
    if hui then
        local old = hui:FindFirstChild("AutoClickerUI")
        if old then old:Destroy() end
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoClickerUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true

local hui = getHui()
if hui then
    ScreenGui.Parent = hui
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = CoreGui
else
    ScreenGui.Parent = PlayerGui
end

local function New(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

local function Corner(obj, r)
    return New("UICorner", {CornerRadius = UDim.new(0, r or 8)}, obj)
end

local function Stroke(obj, color, t, tr)
    return New("UIStroke", {Color = color or Color3.fromRGB(70, 78, 96), Thickness = t or 1, Transparency = tr or 0.35}, obj)
end

local Theme = {
    Panel = Color3.fromRGB(15, 18, 25),
    Panel2 = Color3.fromRGB(21, 25, 34),
    Card = Color3.fromRGB(27, 32, 43),
    Card2 = Color3.fromRGB(32, 38, 51),
    Text = Color3.fromRGB(235, 238, 245),
    Muted = Color3.fromRGB(155, 165, 185),
    Stroke = Color3.fromRGB(58, 67, 84),
    Accent = Color3.fromRGB(82, 145, 245),
    Green = Color3.fromRGB(70, 150, 105),
    Red = Color3.fromRGB(180, 72, 78),
    Yellow = Color3.fromRGB(135, 105, 56),
}

local function Tween(obj, props, duration, style, dir, callback)
    local info = TweenInfo.new(duration or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    if callback then
        tw.Completed:Connect(callback)
    end
    tw:Play()
    return tw
end

local function StyleButton(btn, color)
    btn.BackgroundColor3 = color or Theme.Card
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    Corner(btn, 8)
    Stroke(btn, Theme.Stroke, 1, 0.55)
end

-- ==================== 主窗口 ====================
local Main = New("Frame", {
    Size = UDim2.new(0, 420, 0, 320),
    Position = UDim2.new(0.5, -210, 0.5, -160),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Active = true,
    Draggable = true,
}, ScreenGui)
Corner(Main, 18)
Stroke(Main, Theme.Stroke, 1, 0.36)

local Title = New("TextLabel", {
    BackgroundTransparency = 1,
    Text = "连点器",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextSize = 17
}, Main)

local MinBtn = New("TextButton", {
    Text = "-",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    BackgroundColor3 = Theme.Card2,
    TextSize = 18
}, Main)
StyleButton(MinBtn, Theme.Card2)

local CloseBtn = New("TextButton", {
    Text = "X",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    BackgroundColor3 = Theme.Red,
    TextSize = 16
}, Main)
StyleButton(CloseBtn, Theme.Red)

-- 左侧功能区
local LeftPanel = New("Frame", {
    BackgroundColor3 = Theme.Panel2,
    BorderSizePixel = 0,
    ClipsDescendants = true
}, Main)
Corner(LeftPanel, 8)
Stroke(LeftPanel, Theme.Stroke, 1, 0.38)

local AddBtn = New("TextButton", {Text = "＋ 添加", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.SourceSansBold, BackgroundColor3 = Theme.Green, TextSize = 13}, LeftPanel)
local DelBtn = New("TextButton", {Text = "－ 删除", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.SourceSansBold, BackgroundColor3 = Theme.Red, TextSize = 13}, LeftPanel)
local VisBtn = New("TextButton", {Text = "隐藏按钮", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.SourceSansBold, BackgroundColor3 = Theme.Yellow, TextSize = 13}, LeftPanel)
local StartBtn = New("TextButton", {Text = "开始连点", TextColor3 = Color3.new(1,1,1), Font = Enum.Font.SourceSansBold, BackgroundColor3 = Theme.Green, TextSize = 13}, LeftPanel)

for _, b in ipairs({AddBtn, DelBtn, VisBtn, StartBtn}) do
    StyleButton(b, b.BackgroundColor3)
end

-- 右侧：状态 + 点击按钮列表
local StatusLabel = New("TextLabel", {
    BackgroundTransparency = 1,
    Text = "已停止 ｜ 按钮 1 个",
    TextColor3 = Color3.fromRGB(200,200,205),
    Font = Enum.Font.SourceSans,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextSize = 12
}, Main)

local RightScroll = New("ScrollingFrame", {
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(0,0,0,0),
    ScrollBarThickness = 8,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    VerticalScrollBarInset = Enum.ScrollBarInset.Always,
    ScrollBarImageColor3 = Color3.fromRGB(170,170,175),
    ClipsDescendants = true
}, Main)
Corner(RightScroll, 8)
Stroke(RightScroll, Theme.Stroke, 1, 0.38)

local ListLayout = New("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
}, RightScroll)

local ResizeHandle = New("TextButton", {
    Size = UDim2.new(0, 22, 0, 22),
    AnchorPoint = Vector2.new(1,1),
    Position = UDim2.new(1, -3, 1, -3),
    Text = "↘",
    TextColor3 = Color3.new(1,1,1),
    TextSize = 14,
    Font = Enum.Font.SourceSansBold,
    BackgroundColor3 = Theme.Stroke,
    ZIndex = 10
}, Main)
StyleButton(ResizeHandle, Theme.Stroke)

-- ==================== 最小化悬浮圆点 ====================
local MiniCircle = New("TextButton", {
    Name = "MiniCircle",
    Size = UDim2.new(0, 54, 0, 54),
    Position = UDim2.new(0.5, -27, 0.5, -27),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Text = "点",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    TextSize = 14,
    AutoButtonColor = true,
    Active = true,
    Draggable = true,
    Visible = false,
    ZIndex = 20,
}, ScreenGui)
Corner(MiniCircle, 27)
Stroke(MiniCircle, Theme.Stroke, 1.5, 0.2)

-- ==================== 状态与数据 ====================
local ClickButtons = {}
local MAX_BUTTONS = 15
local Enabled = false
local ButtonsVisible = true
local SettingsOpen = false
local SettingsBtn = nil
local Minimized = false
local Animating = false
local LastNormalSize = Vector2.new(420, 320)
local LastNormalPosition = nil
local LastCirclePosition = nil

-- ==================== 设置弹窗 ====================
local SettingsFrame = New("Frame", {
    Size = UDim2.new(0, 300, 0, 180),
    Position = UDim2.new(0.5, -150, 0.5, -90),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
    ZIndex = 40,
}, ScreenGui)
Corner(SettingsFrame, 12)
Stroke(SettingsFrame, Theme.Stroke, 1, 0.2)

local SettingsTitle = New("TextLabel", {
    Size = UDim2.new(1, -20, 0, 34),
    Position = UDim2.new(0, 10, 0, 6),
    BackgroundTransparency = 1,
    Text = "按钮设置",
    TextColor3 = Color3.new(1,1,1),
    TextSize = 16,
    Font = Enum.Font.SourceSansBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, SettingsFrame)

local CpsHint = New("TextLabel", {
    Size = UDim2.new(1, -20, 0, 20),
    Position = UDim2.new(0, 10, 0, 44),
    BackgroundTransparency = 1,
    Text = "每秒点击次数（1 ~ 50，整数）",
    TextColor3 = Color3.fromRGB(200,200,205),
    TextSize = 12,
    Font = Enum.Font.SourceSans,
    TextXAlignment = Enum.TextXAlignment.Left
}, SettingsFrame)

local CpsInput = New("TextBox", {
    Size = UDim2.new(1, -20, 0, 36),
    Position = UDim2.new(0, 10, 0, 68),
    BackgroundColor3 = Theme.Card,
    Text = "5",
    TextColor3 = Color3.new(1,1,1),
    PlaceholderText = "每秒次数",
    PlaceholderColor3 = Color3.fromRGB(155,155,160),
    Font = Enum.Font.SourceSansBold,
    TextSize = 16,
    ClearTextOnFocus = false
}, SettingsFrame)
Corner(CpsInput, 8)
Stroke(CpsInput, Theme.Stroke, 1, 0.38)

local SettingsOk = New("TextButton", {
    Size = UDim2.new(0.5, -6, 0, 34),
    Position = UDim2.new(0, 10, 1, -46),
    Text = "确定",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    TextSize = 14,
    BackgroundColor3 = Theme.Green
}, SettingsFrame)
StyleButton(SettingsOk, SettingsOk.BackgroundColor3)

local SettingsCancel = New("TextButton", {
    Size = UDim2.new(0.5, -6, 0, 34),
    Position = UDim2.new(0.5, 6, 1, -46),
    Text = "取消",
    TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.SourceSansBold,
    TextSize = 14,
    BackgroundColor3 = Theme.Card2
}, SettingsFrame)
StyleButton(SettingsCancel, SettingsCancel.BackgroundColor3)

local function CloseSettings()
    SettingsOpen = false
    SettingsBtn = nil
    if SettingsFrame then SettingsFrame.Visible = false end
end

local function OpenSettings(btn)
    if SettingsOpen or not btn or not btn.Parent then return end
    SettingsOpen = true
    SettingsBtn = btn
    local idx = 1
    for i, b in ipairs(ClickButtons) do
        if b == btn then idx = i; break end
    end
    SettingsTitle.Text = "按钮 "..idx.." 设置"
    CpsInput.Text = tostring(btn:GetAttribute("CPS") or 5)
    SettingsFrame.Visible = true
end

-- ==================== 点击按钮管理 ====================
local function ResizeCanvas()
    task.defer(function()
        task.wait()
        if RightScroll and ListLayout then
            RightScroll.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
        end
    end)
end

local function RefreshButtonLabels()
    for i, btn in ipairs(ClickButtons) do
        btn.LayoutOrder = i
        btn.Text = "按钮 "..i.."\n"..tostring(btn:GetAttribute("CPS") or 5).." 次/秒"
    end
end

local function UpdateStatus(msg)
    local state = Enabled and "运行中" or "已停止"
    if msg then
        StatusLabel.Text = state.." ｜ 按钮 "..#ClickButtons.." 个 ｜ "..msg
    else
        StatusLabel.Text = state.." ｜ 按钮 "..#ClickButtons.." 个"
    end
end

SettingsOk.MouseButton1Click:Connect(function()
    local v = tonumber(CpsInput.Text) or 5
    v = math.clamp(math.round(v), 1, 50)
    if SettingsBtn then
        SettingsBtn:SetAttribute("CPS", v)
        RefreshButtonLabels()
    end
    CloseSettings()
end)

SettingsCancel.MouseButton1Click:Connect(function()
    CloseSettings()
end)

local function MakeClickButton(index)
    local btn = New("TextButton", {
        Name = "ClickBtn",
        Size = UDim2.new(1, -12, 0, 54),
        BackgroundColor3 = Theme.Card2,
        BorderSizePixel = 0,
        Text = "按钮 "..index.."\n5 次/秒",
        TextColor3 = Color3.new(1,1,1),
        TextSize = 16,
        Font = Enum.Font.SourceSansBold,
        AutoButtonColor = true,
        Active = true,
        LayoutOrder = index,
    }, RightScroll)
    Corner(btn, 10)
    Stroke(btn, Theme.Stroke, 1, 0.45)
    btn:SetAttribute("CPS", 5)

    -- 长按 0.5 秒打开设置
    local holding = false
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            holding = true
            task.spawn(function()
                task.wait(0.5)
                if holding and btn.Parent and not SettingsOpen then
                    OpenSettings(btn)
                end
            end)
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            holding = false
        end
    end)

    table.insert(ClickButtons, btn)
    return btn
end

local function AddClickButton()
    if #ClickButtons >= MAX_BUTTONS then
        UpdateStatus("最多 "..MAX_BUTTONS.." 个按钮")
        return
    end
    local btn = MakeClickButton(#ClickButtons + 1)
    if not ButtonsVisible then btn.Visible = false end
    RefreshButtonLabels()
    ResizeCanvas()
    UpdateStatus("已添加")
end

local function RemoveLastButton()
    local btn = table.remove(ClickButtons)
    if not btn then
        UpdateStatus("没有按钮可删除")
        return
    end
    if SettingsBtn == btn then CloseSettings() end
    btn:Destroy()
    RefreshButtonLabels()
    ResizeCanvas()
    UpdateStatus("已删除")
end

local function SetButtonsVisible(v)
    ButtonsVisible = v
    for _, btn in ipairs(ClickButtons) do
        btn.Visible = v
    end
    VisBtn.Text = v and "隐藏按钮" or "显示按钮"
    UpdateStatus(v and "按钮已显示" or "按钮已隐藏，照常连点")
end

local function SetEnabled(v)
    Enabled = v
    StartBtn.Text = v and "停止连点" or "开始连点"
    StartBtn.BackgroundColor3 = v and Theme.Red or Theme.Green
    UpdateStatus()
end

-- ==================== 连点引擎 ====================
local function SendClickAt(x, y)
    if UserInputService.TouchEnabled then
        local id = math.random(10000, 99999)
        VIM:SendTouchEvent(id, x, y, Enum.UserInputState.Begin)
        task.wait(0.012)
        VIM:SendTouchEvent(id, x, y, Enum.UserInputState.End)
    else
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.012)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end
end

local function ClickButton(btn)
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then return end
    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2
    SendClickAt(x, y)
end

-- 主循环：按 1,2,3,1,2,3... 顺序循环点击
task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        if Enabled and not SettingsOpen then
            for _, btn in ipairs(ClickButtons) do
                if not Enabled then break end
                if btn.Parent then
                    ClickButton(btn)
                    local cps = math.clamp(btn:GetAttribute("CPS") or 5, 1, 50)
                    task.wait(1 / cps)
                end
            end
        else
            task.wait(0.1)
        end
    end
end)

-- ==================== 响应式布局 ====================
local function LayoutUI()
    if Minimized or Animating then return end

    local w, h = Main.AbsoluteSize.X, Main.AbsoluteSize.Y
    if w <= 0 then w = 420 end
    if h <= 0 then h = 320 end

    local scale = math.clamp(math.sqrt((w / 420) * (h / 320)), 0.72, 1.7)
    local pad = math.floor(math.clamp(8 * scale, 6, 14))
    local titleH = math.floor(math.clamp(32 * scale, 26, 48))
    local sideW = math.floor(math.clamp(118 * scale, 96, 190))
    local btnH = math.floor(math.clamp(40 * scale, 30, 60))
    local gap = math.floor(math.clamp(6 * scale, 4, 10))
    local topBtnSize = math.floor(math.clamp(28 * scale, 22, 40))
    local statusH = math.floor(math.clamp(22 * scale, 16, 30))

    Title.Size = UDim2.new(1, -math.floor(80*scale), 0, titleH)
    Title.Position = UDim2.new(0, pad, 0, 0)
    Title.TextSize = math.floor(math.clamp(17 * scale, 13, 24))

    MinBtn.Size = UDim2.new(0, topBtnSize, 0, topBtnSize)
    MinBtn.Position = UDim2.new(1, -(topBtnSize*2 + 4), 0, 2)
    MinBtn.TextSize = math.floor(math.clamp(18 * scale, 14, 24))

    CloseBtn.Size = UDim2.new(0, topBtnSize, 0, topBtnSize)
    CloseBtn.Position = UDim2.new(1, -(topBtnSize + 2), 0, 2)
    CloseBtn.TextSize = math.floor(math.clamp(16 * scale, 12, 22))

    -- 左侧功能区
    LeftPanel.Size = UDim2.new(0, sideW, 1, -titleH - pad*2)
    LeftPanel.Position = UDim2.new(0, pad, 0, titleH + pad)

    local btns = {AddBtn, DelBtn, VisBtn, StartBtn}
    local btnTextSize = math.floor(math.clamp(13 * scale, 10, 18))
    for i, b in ipairs(btns) do
        b.Size = UDim2.new(1, -pad, 0, btnH)
        b.Position = UDim2.new(0, math.floor(pad/2), 0, gap + (i-1) * (btnH + gap))
        b.TextSize = btnTextSize
    end

    -- 右侧：状态栏 + 点击按钮列表
    local listX = pad * 2 + sideW
    local rightW = math.max(120, w - listX - pad)

    StatusLabel.Size = UDim2.new(0, rightW, 0, statusH)
    StatusLabel.Position = UDim2.new(0, listX, 0, pad)
    StatusLabel.TextSize = math.floor(math.clamp(12 * scale, 10, 17))

    RightScroll.Size = UDim2.new(0, rightW, 1, -statusH - pad*2 - gap)
    RightScroll.Position = UDim2.new(0, listX, 0, statusH + pad + gap)

    for _, btn in ipairs(ClickButtons) do
        btn.TextSize = math.floor(math.clamp(16 * scale, 12, 22))
    end

    ResizeHandle.Visible = true
    ResizeCanvas()
end

-- ==================== 最小化 <-> 悬浮圆点 ====================
local MIN_ANIM_TIME = 0.22

local function GetCircleTargetPosition()
    if LastCirclePosition then return LastCirclePosition end
    local vw, vh = 800, 600
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y end
    end)
    local x = math.clamp(16, 10, math.max(10, vw - 64))
    local y = math.clamp(math.floor(vh / 2 - 80), 10, math.max(10, vh - 64))
    return UDim2.new(0, x, 0, y)
end

local function MinimizeToCircle()
    if Animating then return end
    Animating = true
    Minimized = true

    LastNormalSize = Vector2.new(Main.AbsoluteSize.X, Main.AbsoluteSize.Y)
    LastNormalPosition = Main.Position

    local target = GetCircleTargetPosition()
    Tween(Main, {
        Size = UDim2.new(0, 40, 0, 40),
        Position = target,
        BackgroundTransparency = 1,
    }, MIN_ANIM_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    task.delay(MIN_ANIM_TIME, function()
        Main.Visible = false
        Main.Size = UDim2.new(0, LastNormalSize.X, 0, LastNormalSize.Y)
        Main.Position = LastNormalPosition

        MiniCircle.Position = target
        MiniCircle.Size = UDim2.new(0, 10, 0, 10)
        MiniCircle.BackgroundTransparency = 1
        MiniCircle.Visible = true
        Tween(MiniCircle, {
            Size = UDim2.new(0, 54, 0, 54),
            BackgroundTransparency = 0,
        }, MIN_ANIM_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        Animating = false
    end)
end

local function RestoreFromCircle()
    if Animating then return end
    Animating = true
    Minimized = false

    LastCirclePosition = MiniCircle.Position

    Tween(MiniCircle, {
        Size = UDim2.new(0, 10, 0, 10),
        BackgroundTransparency = 1,
    }, MIN_ANIM_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    task.delay(MIN_ANIM_TIME, function()
        MiniCircle.Visible = false

        Main.Position = LastCirclePosition or MiniCircle.Position
        Main.Size = UDim2.new(0, 40, 0, 40)
        Main.BackgroundTransparency = 1
        Main.Visible = true

        Tween(Main, {
            Size = UDim2.new(0, LastNormalSize.X, 0, LastNormalSize.Y),
            Position = LastNormalPosition or UDim2.new(0.5, -LastNormalSize.X/2, 0.5, -LastNormalSize.Y/2),
            BackgroundTransparency = 0,
        }, MIN_ANIM_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

        task.delay(MIN_ANIM_TIME, function()
            LayoutUI()
            Animating = false
        end)
    end)
end

-- ==================== 事件连接 ====================
AddBtn.MouseButton1Click:Connect(function() AddClickButton() end)
DelBtn.MouseButton1Click:Connect(function() RemoveLastButton() end)
VisBtn.MouseButton1Click:Connect(function() SetButtonsVisible(not ButtonsVisible) end)
StartBtn.MouseButton1Click:Connect(function() SetEnabled(not Enabled) end)

CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

MinBtn.MouseButton1Click:Connect(function()
    if Minimized then RestoreFromCircle() else MinimizeToCircle() end
end)

MiniCircle.MouseButton1Click:Connect(function()
    RestoreFromCircle()
end)

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() ResizeCanvas() end)

Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if not Minimized then LayoutUI() end
end)

-- 缩放手柄
local resizing = false
local resizeStartPos, resizeStartSize
ResizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing = true
        resizeStartPos = input.Position
        resizeStartSize = Main.AbsoluteSize
        Main.Draggable = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not resizing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local delta = input.Position - resizeStartPos
    local newW = math.clamp(resizeStartSize.X + delta.X, 360, 720)
    local newH = math.clamp(resizeStartSize.Y + delta.Y, 260, 540)
    Main.Size = UDim2.new(0, newW, 0, newH)
    LastNormalSize = Vector2.new(newW, newH)
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        resizing = false
        Main.Draggable = true
    end
end)

-- ==================== 初始化 ====================
LayoutUI()
AddClickButton()
UpdateStatus()

print("[连点器] 已加载 | 长按按钮设置次数 | 1,2,3 顺序连点")
