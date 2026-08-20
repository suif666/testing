--[[
    【游戏内 AI 聊天助手】 by suif
    基于 Agnes AI API（OpenAI 兼容），模型 agnes-2.5-flash（支持对话 + 图像理解）

    使用方法：
      1. 把下面的 KEY 换成你自己的 key（platform.agnes-ai.com 获取）
      2. 在注入器里加载本脚本
      3. 按 RightAlt 打开/关闭聊天面板

    图片解析：在输入框输入  img <图片URL> <问题>  例如：
      img https://picsum.photos/400 这张图里有什么？

    ⚠️ 重要：KEY 是你的私有凭据，请勿把带 key 的脚本公开分享！
       也可以用 getgenv().AgnesAIKey = "sk-xxx" 提前注入，脚本会自动读取。
]]

-- ============ 配置区 ============
local KEY       = getgenv().AgnesAIKey or "sk-zgcP2NSe8sUGhyQPoX6ADvUVYnKbXrdUr2g5HHipKWZynVNf" -- ← 换成你自己的
local MODEL     = getgenv().AgnesAIModel or "agnes-2.5-flash"
local BASE_URL  = "https://apihub.agnes-ai.com/v1"
local TOGGLE_KEY = Enum.KeyCode.RightAlt   -- 开关快捷键
local MAX_ROUNDS = 10                       -- 保留最近几轮对话作为上下文
local MAX_TOKENS = 1024                     -- 回复最大长度

-- 主题色
local COLORS = {
    panel   = Color3.fromRGB(28, 31, 42),
    titlebg = Color3.fromRGB(35, 39, 54),
    user    = Color3.fromRGB(56, 92, 200),
    ai      = Color3.fromRGB(46, 50, 63),
    text    = Color3.fromRGB(235, 238, 245),
    subtext = Color3.fromRGB(150, 155, 168),
    accent  = Color3.fromRGB(80, 130, 255),
    input   = Color3.fromRGB(24, 26, 36),
    danger  = Color3.fromRGB(220, 80, 80),
}

-- ============ 环境检查 ============
local httpRequest = syn and syn.request or http and http.request or request
if not httpRequest then
    warn("[AI助手] 当前执行器不支持 request，无法使用")
    return
end
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- 防止重复执行
if getgenv().AgnesAIChatActive then return end
getgenv().AgnesAIChatActive = true

-- 对话上下文
local history = {}

-- ============ UI 构建 ============
local playerGui = lp:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "AgnesAIChat"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(460, 560)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = COLORS.panel
panel.BorderSizePixel = 0
panel.Parent = gui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.accent
stroke.Thickness = 1.5
stroke.Transparency = 0.65
stroke.Parent = panel

-- ---------- 标题栏 ----------
local titlebar = Instance.new("Frame")
titlebar.Name = "TitleBar"
titlebar.Size = UDim2.new(1, 0, 0, 40)
titlebar.BackgroundTransparency = 1
titlebar.Active = true
titlebar.Parent = panel

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -90, 1, 0)
titleText.Position = UDim2.fromOffset(14, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "AI 聊天助手  ·  " .. MODEL
titleText.TextColor3 = COLORS.text
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 16
titleText.Parent = titlebar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(32, 32)
closeBtn.Position = UDim2.new(1, -38, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "×"
closeBtn.TextColor3 = COLORS.subtext
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = titlebar
closeBtn.Activated:Connect(function()
    panel.Visible = false
end)

-- 拖拽（按住标题栏拖动）
local dragging = false
local dragOffset = Vector2.zero
titlebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragOffset = input.Position - panel.AbsolutePosition
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
        local pos = input.Position - dragOffset
        panel.AnchorPoint = Vector2.new(0, 0)
        panel.Position = UDim2.fromOffset(pos.X, pos.Y)
    end
end)

-- ---------- 聊天记录区 ----------
local chatFrame = Instance.new("ScrollingFrame")
chatFrame.Name = "Chat"
chatFrame.Size = UDim2.new(1, 0, 1, -96)
chatFrame.Position = UDim2.fromOffset(0, 40)
chatFrame.BackgroundTransparency = 1
chatFrame.BorderSizePixel = 0
chatFrame.ScrollBarThickness = 5
chatFrame.ScrollBarImageColor3 = COLORS.accent
chatFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
chatFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatFrame.Parent = panel

local chatList = Instance.new("UIListLayout")
chatList.Padding = UDim.new(0, 8)
chatList.Parent = chatFrame

local chatPadding = Instance.new("UIPadding")
chatPadding.PaddingLeft = UDim.new(0, 10)
chatPadding.PaddingRight = UDim.new(0, 10)
chatPadding.PaddingTop = UDim.new(0, 8)
chatPadding.PaddingBottom = UDim.new(0, 8)
chatPadding.Parent = chatFrame

-- 自动滚到底
chatList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    task.wait()
    chatFrame.CanvasPosition = Vector2.new(
        0,
        math.max(0, chatFrame.AbsoluteCanvasSize.Y - chatFrame.AbsoluteWindowSize.Y)
    )
end)

-- ---------- 输入区 ----------
local inputBar = Instance.new("Frame")
inputBar.Name = "InputBar"
inputBar.Size = UDim2.new(1, 0, 0, 52)
inputBar.Position = UDim2.new(0, 0, 1, -52)
inputBar.BackgroundTransparency = 1
inputBar.Parent = panel

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(1, -86, 0, 36)
inputBox.Position = UDim2.fromOffset(10, 8)
inputBox.BackgroundColor3 = COLORS.input
inputBox.TextColor3 = COLORS.text
inputBox.PlaceholderColor3 = COLORS.subtext
inputBox.PlaceholderText = "输入消息…  img <图片URL> 可带图"
inputBox.Font = Enum.Font.Gotham
inputBox.TextSize = 15
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.ClearTextOnFocus = false
inputBox.Parent = inputBar
Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 8)

inputBox.FocusLost:Connect(function(enter)
    if enter then send() end
end)

local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(0, 70, 0, 36)
sendBtn.Position = UDim2.new(1, -80, 0, 8)
sendBtn.BackgroundColor3 = COLORS.accent
sendBtn.Text = "发送"
sendBtn.TextColor3 = Color3.new(1, 1, 1)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 15
sendBtn.AutoButtonColor = true
sendBtn.Parent = inputBar
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 8)
sendBtn.Activated:Connect(function() send() end)

-- ============ 工具函数 ============
local function makeBubble(role, text)
    -- 一行消息：外层全宽行 + 内层气泡（用户靠右，AI 靠左）
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 0)
    row.BackgroundTransparency = 1
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.Parent = chatFrame

    local bubble = Instance.new("Frame")
    bubble.Size = UDim2.new(0.72, 0, 0, 0)
    bubble.AutomaticSize = Enum.AutomaticSize.Y
    bubble.BackgroundColor3 = role == "user" and COLORS.user or COLORS.ai
    bubble.BorderSizePixel = 0
    if role == "user" then
        bubble.AnchorPoint = Vector2.new(1, 0)
        bubble.Position = UDim2.fromScale(1, 0)
    end
    bubble.Parent = row
    Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 10)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = bubble

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLORS.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextWrapped = true
    label.TextXAlignment = role == "user" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
    label.Parent = bubble

    return label
end

local function setBubble(label, text, isError)
    label.Text = text
    if isError then
        label.TextColor3 = COLORS.danger
    else
        label.TextColor3 = COLORS.text
    end
end

-- ============ 核心逻辑 ============
local function send()
    local text = inputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    inputBox.Text = ""

    -- 图片模式：img <URL> <问题>
    local content
    local isImage = text:match("^[iI][mM][gG]%s+") ~= nil
    if isImage then
        local _, _, url, question = text:find("^[iI][mM][gG]%s+(%S+)%s*(.-)$")
        url = url or ""
        question = question or ""
        if url == "" then
            makeBubble("ai", "格式：img <图片URL> <问题>")
            return
        end
        content = {
            { type = "text", text = question ~= "" and question or "请用中文描述这张图片" },
            { type = "image_url", image_url = { url = url } }
        }
    else
        content = text
    end

    makeBubble("user", text)
    table.insert(history, { role = "user", content = content })

    -- 裁剪上下文（保留最近 MAX_ROUNDS 轮）
    while #history > MAX_ROUNDS * 2 do
        table.remove(history, 1)
        table.remove(history, 1)
    end

    local thinking = makeBubble("ai", "正在思考…")

    task.spawn(function()
        local ok, reply = pcall(function()
            local res = httpRequest({
                Url = BASE_URL .. "/chat/completions",
                Method = "POST",
                Headers = {
                    ["Authorization"] = "Bearer " .. KEY,
                    ["Content-Type"] = "application/json",
                },
                Body = HttpService:JSONEncode({
                    model = MODEL,
                    messages = history,
                    max_tokens = MAX_TOKENS,
                }),
            })
            if not res or not res.Body then
                error("网络请求失败")
            end
            local data = HttpService:JSONDecode(res.Body)
            if data.error then
                error(data.error.message or "API 错误")
            end
            local msg = data.choices and data.choices[1]
            if not msg or not msg.message or not msg.message.content then
                error("响应格式异常")
            end
            return msg.message.content
        end)

        if ok then
            setBubble(thinking, reply)
            table.insert(history, { role = "assistant", content = reply })
        else
            local err = tostring(reply)
            if #err > 300 then err = err:sub(1, 300) .. "…" end
            setBubble(thinking, "⚠️ " .. err, true)
            table.insert(history, { role = "assistant", content = "（错误）" })
        end
    end)
end

-- ============ 快捷键开关 ============
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == TOGGLE_KEY then
        if UIS:GetFocusedTextBox() then return end
        panel.Visible = not panel.Visible
        if panel.Visible then
            -- 打开时弹一下
            local original = panel.Position
            panel.Position = original + UDim2.fromScale(0, 0.02)
            TweenService:Create(panel, TweenInfo.new(0.15), { Position = original }):Play()
        end
    end
end)

-- 欢迎消息
makeBubble("ai", "你好！我是 Agnes AI 助手（" .. MODEL .. "）。\n\n直接输入文字聊天；想看图片就输入：\nimg <图片URL> <问题>")
panel.Visible = true

-- 提示已加载
print("[AI助手] 已加载，按 RightAlt 开关面板")
