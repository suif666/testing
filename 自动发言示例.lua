-- 自动发言 + 私聊 独立脚本（自带 WindUI）
-- 功能：自动发言（指定次数连发）、指定发言（私聊）
local WindUI
do
    local ok, res = pcall(function()
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
end

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local win = WindUI:CreateWindow({
    Title = "自动发言",
    Icon = "aperture",
    Author = "by suif",
    Folder = "SutureHub",
    Size = UDim2.fromOffset(360, 440),
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    HideSearchBar = true,
    ScrollBarEnabled = true,
    NewElements = true,
})

local mainTab = win:Tab({ Title = "发言", Icon = "user", Locked = false })
mainTab:Select()

-- ===== 状态 =====
local sayMessage = ""
local sayCount = 1
local isSpeaking = false
local speakThread = nil

local whisperMessage = ""
local whisperCount = 1
local whisperTarget = nil

-- ===== 发送函数（兼容新旧聊天系统） =====
local function SendChatMessage(message)
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local ch = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
            if ch then
                ch:SendAsync(message)
            end
        else
            local say = ReplicatedStorage
                and ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
                and ReplicatedStorage.DefaultChatSystemChatEvents:FindFirstChild("SayMessageRequest")
            if say then
                say:FireServer(message, "All")
            end
        end
    end)
end

-- 私聊：用聊天指令 /w 玩家名 内容
local function SendWhisper(targetName, message)
    if not targetName or targetName == "" or not message or message == "" then return end
    SendChatMessage("/w " .. targetName .. " " .. message)
end

-- ===== 自动发言 UI =====
mainTab:Paragraph({
    Title = "自动发言",
    Desc = "按指定次数连续发送同一句话"
})

mainTab:Input({
    Title = "发言内容",
    Desc = "要自动发送的话",
    Callback = function(v)
        sayMessage = v or ""
    end
})

mainTab:Input({
    Title = "发言次数",
    Desc = "连续发送几次",
    Callback = function(v)
        sayCount = tonumber(v) or 1
    end
})

mainTab:Toggle({
    Title = "发言开关",
    Desc = "开启后按上面的内容和次数发送",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        isSpeaking = s
        if s then
            if sayMessage == "" then
                warn("[自动发言] 请先输入发言内容")
                isSpeaking = false
                return
            end
            speakThread = task.spawn(function()
                for i = 1, math.max(1, sayCount) do
                    if not isSpeaking then break end
                    SendChatMessage(sayMessage)
                    task.wait(0.5)
                end
                isSpeaking = false
            end)
        else
            if speakThread then
                task.cancel(speakThread)
                speakThread = nil
            end
        end
    end
})

mainTab:Space()

-- ===== 私聊 UI =====
mainTab:Paragraph({
    Title = "指定发言（私聊）",
    Desc = "选择玩家后发送私聊消息"
})

local playerNameList = {}
local function rebuildList()
    playerNameList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            table.insert(playerNameList, p.Name)
        end
    end
end
rebuildList()

local TargetDropdown = mainTab:Dropdown({
    Title = "选择私聊对象",
    Values = playerNameList,
    Value = playerNameList[1] or "无",
    Callback = function(v)
        whisperTarget = Players:FindFirstChild(v)
    end
})

mainTab:Button({
    Title = "刷新玩家列表",
    Callback = function()
        rebuildList()
        pcall(function()
            TargetDropdown:SetValues(playerNameList)
        end)
    end
})

Players.PlayerAdded:Connect(function()
    rebuildList()
    pcall(function()
        TargetDropdown:SetValues(playerNameList)
    end)
end)

Players.PlayerRemoving:Connect(function()
    rebuildList()
    pcall(function()
        TargetDropdown:SetValues(playerNameList)
    end)
end)

mainTab:Input({
    Title = "私聊内容",
    Desc = "发给选中玩家的消息",
    Callback = function(v)
        whisperMessage = v or ""
    end
})

mainTab:Input({
    Title = "私聊次数",
    Desc = "连发几次",
    Callback = function(v)
        whisperCount = tonumber(v) or 1
    end
})

mainTab:Button({
    Title = "发送私聊",
    Desc = "对选中的玩家发送私聊",
    Callback = function()
        if not whisperTarget then
            warn("[自动发言] 请先选择私聊对象")
            return
        end
        if whisperMessage == "" then
            warn("[自动发言] 请先输入私聊内容")
            return
        end
        task.spawn(function()
            for i = 1, math.max(1, whisperCount) do
                SendWhisper(whisperTarget.Name, whisperMessage)
                task.wait(0.3)
            end
        end)
    end
})

WindUI:Notify({
    Title = "自动发言",
    Content = "脚本加载完成",
    Icon = "check",
    Duration = 3
})
