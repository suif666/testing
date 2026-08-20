--[[
    【游戏内 AI 聊天助手 · WindUI Boreal 版】 by suif
    基于 Agnes AI API（OpenAI 兼容），模型 agnes-2.5-flash（支持对话 + 图像理解）
    UI 使用 WindUI Boreal（和主脚本同款，手机/电脑通用）
    API 调用使用 HttpService:RequestAsync（Roblox 官方，兼容所有执行器，BS脚本验证过）

    使用方法：
      1. 把下面 KEY 换成你自己的 key（platform.agnes-ai.com 获取）
      2. 注入器里加载本脚本
      3. 按 RightAlt 打开/关闭窗口（手机上点胶囊栏重开）

    图片解析：输入  img <图片URL> <问题>   例如：
      img https://picsum.photos/400 这张图里有什么？

    ⚠️ 重要：KEY 是私有凭据，请勿把带 key 的脚本公开分享！
       可用 getgenv().AgnesAIKey = "sk-xxx" 提前注入，脚本自动读取。
]]

-- ============ 配置 ============
local KEY       = getgenv().AgnesAIKey or "sk-zgcP2NSe8sUGhyQPoX6ADvUVYnKbXrdUr2g5HHipKWZynVNf" -- ← 换成你自己的
local MODEL     = getgenv().AgnesAIModel or "agnes-2.5-flash"
local BASE_URL  = "https://apihub.agnes-ai.com/v1"
local MAX_ROUNDS = 10      -- 上下文保留轮数
local MAX_TOKENS = 1024    -- 回复最大 token

-- ============ 加载 WindUI Boreal（和主脚本同一个链接）============
local ok, WindUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/WindUI-Boreal.lua"))()
end)
if not ok or not WindUI then
    warn("[AI助手] WindUI(Boreal) 加载失败:", WindUI)
    pcall(function()
        if setclipboard then setclipboard("Boreal加载失败: " .. tostring(WindUI)) end
    end)
    return
end

local HttpService = game:GetService("HttpService")

-- 防止重复执行
if getgenv().AgnesAIChatActive then return end
getgenv().AgnesAIChatActive = true

-- ============ 创建窗口 ============
local win = WindUI:CreateWindow({
    Title = "AI 聊天助手",
    Icon = "message-square",
    Author = "by suif",
    Folder = "AgnesAIChat",
    Size = UDim2.fromOffset(430, 560),
    ToggleKey = Enum.KeyCode.RightAlt,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    HideSearchBar = true,
    SideBarWidth = 120,
})

local chatTab = win:Tab({ Title = "AI 助手", Icon = "bot", Locked = false })

-- ============ 对话历史 ============
local history = {}

local function scrollToBottom()
    task.wait()
    local c = chatTab.UIElements and chatTab.UIElements.ContainerFrame
    if c then
        c.CanvasPosition = Vector2.new(0, math.max(0, c.AbsoluteCanvasSize.Y))
    end
end

local function addMessage(role, text)
    local p = chatTab:Paragraph({
        Title = role == "user" and "🧑 你" or "🤖 Agnes",
        Desc = text,
    })
    scrollToBottom()
    return p
end

-- ============ 输入区 ============
local input = chatTab:Input({
    Title = "消息",
    Desc = "img <图片URL> 可附带图片",
    Placeholder = "输入内容…",
    Value = "",
    ClearTextOnFocus = false,
    Callback = function(v) end,
})

chatTab:Button({
    Title = "发送",
    Desc = "发送消息给 AI",
    Callback = function()
        send()
    end,
})

-- 从 WindUI Input 组件内部找出真正的 TextBox（直接读它的文本，避免失焦延迟问题）
local function getInputText()
    -- 优先直接读 TextBox
    local function findTextBox(inst, depth)
        if depth > 10 then return nil end
        for _, c in ipairs(inst:GetChildren()) do
            if c:IsA("TextBox") then return c end
            local r = findTextBox(c, depth + 1)
            if r then return r end
        end
        return nil
    end
    local main = input.InputFrame and input.InputFrame.UIElements
        and (input.InputFrame.UIElements.Container or input.InputFrame.UIElements.Main)
    local tb = main and findTextBox(main, 0)
    if tb and tb.Text ~= "" then
        return tb, tb
    end
    -- 兜底：用组件的 Value
    return input.Value or "", nil
end

local function clearInput()
    pcall(function()
        input:Set("")
    end)
end

-- ============ 发送逻辑 ============
local busy = false

local function send()
    if busy then return end
    local text, tb = getInputText()
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end

    clearInput()

    addMessage("user", text)

    -- 图片模式：img <URL> <问题>
    local content
    if text:match("^[iI][mM][gG]%s+") then
        local _, _, url, question = text:find("^[iI][mM][gG]%s+(%S+)%s*(.-)$")
        url = url or ""
        question = question or ""
        if url == "" then
            addMessage("ai", "格式：img <图片URL> <问题>")
            return
        end
        content = {
            { type = "text", text = question ~= "" and question or "请用中文描述这张图片" },
            { type = "image_url", image_url = { url = url } },
        }
    else
        content = text
    end

    table.insert(history, { role = "user", content = content })
    while #history > MAX_ROUNDS * 2 do
        table.remove(history, 1)
        table.remove(history, 1)
    end

    local thinking = addMessage("ai", "正在思考…")
    busy = true

    task.spawn(function()
        local okReq, reply = pcall(function()
            -- 用 HttpService:RequestAsync（Roblox 官方 API，BS脚本验证过可用）
            local response = HttpService:RequestAsync({
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
            if not response or not response.Success then
                error("网络请求失败" .. (response and response.StatusCode or ""))
            end
            local data = HttpService:JSONDecode(response.Body)
            if data.error then error(data.error.message or "API 错误") end
            local msg = data.choices and data.choices[1]
            if not msg or not msg.message or not msg.message.content then error("响应格式异常") end
            return msg.message.content
        end)

        if okReq then
            if thinking.SetDesc then thinking:SetDesc(reply) end
            table.insert(history, { role = "assistant", content = reply })
        else
            local err = tostring(reply)
            if #err > 300 then err = err:sub(1, 300) .. "…" end
            if thinking.SetDesc then thinking:SetDesc("⚠️ " .. err) end
            table.insert(history, { role = "assistant", content = "（错误）" })
        end
        busy = false
        scrollToBottom()
    end)
end

-- 欢迎消息
addMessage("ai", "你好！我是 Agnes AI 助手（" .. MODEL .. "）。\n\n直接输入文字聊天；想看图片：\nimg <图片URL> <问题>")

print("[AI助手] 已加载，按 RightAlt 开关，输入 img <图片URL> 可解析图片")
