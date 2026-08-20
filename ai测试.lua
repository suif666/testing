--[[
    【游戏内 AI 聊天助手】 by suif
    基于 Agnes AI API（OpenAI 兼容），模型 agnes-2.5-flash（支持对话 + 图像理解）
    UI 抄自 BS 脚本的聊天界面（原生 ScreenGui，兼容手机/电脑）
    API 调用走你的 Cloudflare Worker 中转（game:HttpGet → Worker → Agnes API）

    使用方法：
      1. 确保你的 Cloudflare Worker 已部署新版源码.lua（含 /ai 端点，KEY 在 Worker 里）
      2. 注入器里加载本脚本
      3. 面板默认打开，可拖动、可最小化

    图片解析：输入  img <图片URL> <问题>   例如：
      img https://picsum.photos/400 这张图里有什么？

    ⚠️ 请求全部走你的 Cloudflare Worker 中转（KEY 在 Worker 端，游戏内不暴露）
]]

-- ============ 配置 ============
local WORKER_URL = "https://suture-hub-counter.sfbdsl666.workers.dev/ai" -- ← 你的 Worker 中转地址
local MODEL      = getgenv().AgnesAIModel or "agnes-2.5-flash"

-- ============ 环境 ============
local HttpService = game:GetService("HttpService")
HttpService.HttpTimeout = 120 -- AI 回复可能较慢，放宽超时
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- 防止重复执行
if getgenv().AgnesAIChatActive then return end
getgenv().AgnesAIChatActive = true

-- ============ UI 构建（抄自 BS 脚本）============
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AgnesAIChatUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local frameWidth, frameHeight = 420, 500
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, frameWidth, 0, frameHeight)
frame.Position = UDim2.new(0.5, -frameWidth/2, 0.5, -frameHeight/2)
frame.BackgroundColor3 = Color3.fromRGB(240, 245, 255)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 11)

-- 标题栏
local titleBar = Instance.new("Frame", frame)
titleBar.Size = UDim2.new(1, 0, 0, 31)
titleBar.BackgroundColor3 = Color3.fromRGB(200, 220, 230)
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 11)

local title = Instance.new("TextLabel", titleBar)
title.Text = "AI 聊天助手 · Agnes"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(50, 70, 120)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)

local minimizeBtn = Instance.new("TextButton", titleBar)
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -26, 0.5, -10)
minimizeBtn.Text = "_"
minimizeBtn.TextColor3 = Color3.fromRGB(50, 70, 120)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(220, 235, 245)
minimizeBtn.TextSize = 16
minimizeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 4)

local isMinimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        frame.Size = UDim2.new(0, 200, 0, 34)
        minimizeBtn.Text = "+"
    else
        frame.Size = UDim2.new(0, frameWidth, 0, frameHeight)
        minimizeBtn.Text = "_"
    end
end)

-- 聊天区
local chatBox = Instance.new("ScrollingFrame", frame)
chatBox.Size = UDim2.new(1, -21, 1, -101)
chatBox.Position = UDim2.new(0, 10, 0, 42)
chatBox.BackgroundTransparency = 1
chatBox.BorderSizePixel = 0
chatBox.ScrollBarThickness = 6
chatBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatBox.CanvasSize = UDim2.new(0, 0, 0, 0)
local list = Instance.new("UIListLayout", chatBox)
list.Padding = UDim.new(0, 7)
list.SortOrder = Enum.SortOrder.LayoutOrder

-- 输入区
local inputFrame = Instance.new("ScrollingFrame", frame)
inputFrame.Size = UDim2.new(1, -104, 0, 84)
inputFrame.Position = UDim2.new(0, 10, 1, -94)
inputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
inputFrame.BorderSizePixel = 0
inputFrame.ScrollBarThickness = 4
inputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
inputFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", inputFrame).CornerRadius = UDim.new(0, 8)

local input = Instance.new("TextBox", inputFrame)
input.Size = UDim2.new(1, -10, 1, 0)
input.Position = UDim2.new(0, 5, 0, 0)
input.PlaceholderText = "输入消息（Enter 发送，Ctrl+Enter 换行）\nimg <图片URL> 可解析图片"
input.Text = ""
input.TextSize = 16
input.ClearTextOnFocus = false
input.MultiLine = true
input.TextWrapped = true
input.BackgroundTransparency = 1
input.TextColor3 = Color3.fromRGB(50, 50, 50)
input.AutomaticSize = Enum.AutomaticSize.Y

-- 发送按钮
local sendBtn = Instance.new("TextButton", frame)
sendBtn.Size = UDim2.new(0, 73, 0, 46)
sendBtn.Position = UDim2.new(1, -84, 1, -94)
sendBtn.Text = "发送"
sendBtn.TextSize = 19
sendBtn.Font = Enum.Font.GothamBold
sendBtn.BackgroundColor3 = Color3.fromRGB(182, 200, 255)
sendBtn.TextColor3 = Color3.fromRGB(50, 70, 120)
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 8)

-- 打字指示
local typing = Instance.new("TextLabel", frame)
typing.Text = ""
typing.Font = Enum.Font.Gotham
typing.TextSize = 13
typing.TextColor3 = Color3.fromRGB(120, 140, 160)
typing.BackgroundTransparency = 1
typing.Size = UDim2.new(1, -21, 0, 18)
typing.Position = UDim2.new(0, 10, 1, -80)

-- ============ 消息气泡（抄自 BS 脚本）============
local function addBubble(sender, text, isMe, typingEffect)
    local container = Instance.new("Frame", chatBox)
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y

    local lbl = Instance.new("TextLabel", container)
    lbl.TextWrapped = true
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.Text = ""
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.Size = UDim2.new(0.75, 0, 0, 0)
    lbl.BackgroundColor3 = isMe and Color3.fromRGB(200, 220, 255) or Color3.fromRGB(230, 240, 255)
    lbl.TextColor3 = Color3.fromRGB(40, 40, 40)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 10)

    local pad = Instance.new("UIPadding", lbl)
    pad.PaddingTop = UDim.new(0, 7)
    pad.PaddingBottom = UDim.new(0, 7)
    pad.PaddingLeft = UDim.new(0, 9)
    pad.PaddingRight = UDim.new(0, 9)

    -- 小头像/名字标签
    local nameLabel = Instance.new("TextLabel", container)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 11
    nameLabel.TextColor3 = isMe and Color3.fromRGB(70, 110, 180) or Color3.fromRGB(90, 130, 90)
    nameLabel.Text = sender
    nameLabel.Size = UDim2.new(0.75, 0, 0, 15)
    nameLabel.AutomaticSize = Enum.AutomaticSize.X

    if isMe then
        lbl.AnchorPoint = Vector2.new(1, 0)
        lbl.Position = UDim2.new(1, 0, 0, 0)
        lbl.TextXAlignment = Enum.TextXAlignment.Right
        nameLabel.AnchorPoint = Vector2.new(1, 0)
        nameLabel.Position = UDim2.new(1, 0, 0, 0)
        nameLabel.TextXAlignment = Enum.TextXAlignment.Right
    else
        lbl.AnchorPoint = Vector2.new(0, 0)
        lbl.Position = UDim2.new(0, 0, 0, 0)
        nameLabel.AnchorPoint = Vector2.new(0, 0)
        nameLabel.Position = UDim2.new(0, 0, 0, 0)
    end

    if typingEffect then
        for i = 1, #text do
            lbl.Text = string.sub(text, 1, i)
            task.wait(0.03)
        end
    else
        lbl.Text = text
    end

    -- 滚到底部
    task.wait()
    chatBox.CanvasPosition = Vector2.new(0, math.max(0, chatBox.AbsoluteCanvasSize.Y))

    return container
end

-- ============ API 调用（Cloudflare Worker 中转，game:HttpGet）============
-- 你的环境只有 game:HttpGet 能访问第三方域名（request/RequestAsync 都被 Roblox 域名白名单挡）
-- 所以请求走 Worker：HttpGet → Worker 转发 Agnes API → 返回回复文本
local function callAI(text, imgUrl)
    local url = WORKER_URL .. "?msg=" .. HttpService:UrlEncode(text)
    if imgUrl and imgUrl ~= "" then
        url = url .. "&img=" .. HttpService:UrlEncode(imgUrl)
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok then
        return "（请求失败：" .. tostring(body) .. "）"
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if okDecode and data then
        if data.ok and data.reply then
            return data.reply
        end
        return "（" .. tostring(data.error or "未知错误") .. "）"
    end
    return "（响应解析失败：" .. tostring(body):sub(1, 120) .. "）"
end

-- ============ 发送逻辑（抄自 BS 脚本）============
local busy = false
local currentMessages = {}
local lastUserMessage = nil

local function send(text, isRetry)
    if busy then return end
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    if text == "" then return end

    if not isRetry then
        lastUserMessage = text
    end

    addBubble("你", text, true, false)
    input.Text = ""
    busy = true
    typing.Text = "Agnes正在输入…"

    -- 图片模式：img <URL> <问题>
    local aiText = text
    local imgUrl = nil
    if text:match("^[iI][mM][gG]%s+") then
        local _, _, url, question = text:find("^[iI][mM][gG]%s+(%S+)%s*(.-)$")
        url = url or ""
        question = question or ""
        if url == "" then
            typing.Text = ""
            busy = false
            addBubble("系统", "格式：img <图片URL> <问题>", false, false)
            return
        end
        imgUrl = url
        aiText = question ~= "" and question or "请用中文描述这张图片"
    end

    table.insert(currentMessages, { role = "user", content = text })
    -- 裁剪上下文（保留最近 10 轮）
    while #currentMessages > 20 do
        table.remove(currentMessages, 1)
        table.remove(currentMessages, 1)
    end

    local reply = callAI(aiText, imgUrl)
    typing.Text = ""

    if busy then
        table.insert(currentMessages, { role = "assistant", content = reply })
        addBubble("Agnes", reply, false, true)
        busy = false
    end
end

-- 发送绑定
sendBtn.MouseButton1Click:Connect(function()
    send(input.Text)
end)

input.FocusLost:Connect(function(enterPressed)
    if enterPressed and not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        send(input.Text)
    end
end)

-- 欢迎消息
addBubble("Agnes", "你好！我是 Agnes AI 助手（" .. MODEL .. "）。\n\n直接输入文字聊天；想看图片输入：\nimg <图片URL> <问题>", false, false)

print("[AI助手] 已加载（BS 风格 UI），Enter 发送，img <URL> 解析图片")
