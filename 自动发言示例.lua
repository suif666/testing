-- 自动发言 + 私聊 独立脚本（自带 WindUI）
-- 布局：选择玩家 → 发言内容 → 发言次数 → 发言间隔 → 启用私聊 → 开启发言
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
    Size = UDim2.fromOffset(360, 540),
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
local sayInterval = 1          -- 秒
local whisperOnly = false      -- 私聊模式
local speakEnabled = false
local speakThread = nil
local selectedTarget = nil

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

local function SendWhisper(targetName, message)
    if not targetName or targetName == "" or not message or message == "" then return end
    SendChatMessage("/w " .. targetName .. " " .. message)
end

local function SendCurrent()
    if whisperOnly then
        if selectedTarget then
            SendWhisper(selectedTarget.Name, sayMessage)
        end
    else
        SendChatMessage(sayMessage)
    end
end

-- ===== UI：玩家选择（自动刷新） =====
local playerNameList = {}
local listKey = ""
local TargetDropdown = nil

local function refreshList(force)
    local newList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            table.insert(newList, p.Name)
        end
    end
    local key = table.concat(newList, ",")
    if force or key ~= listKey then
        listKey = key
        playerNameList = newList
        pcall(function()
            TargetDropdown:SetValues(playerNameList)
        end)
    end
end

TargetDropdown = mainTab:Dropdown({
    Title = "选择玩家",
    Desc = "私聊对象；公屏发言时可忽略",
    Values = playerNameList,
    Value = playerNameList[1] or "无",
    Callback = function(v)
        selectedTarget = Players:FindFirstChild(v)
    end
})

Players.PlayerAdded:Connect(function() refreshList(false) end)
Players.PlayerRemoving:Connect(function() refreshList(false) end)
task.spawn(function()
    while true do
        task.wait(2)
        refreshList(false)
    end
end)

refreshList(true)

-- ===== UI：发言设置 =====
mainTab:Input({
    Title = "发言内容",
    Desc = "要发送的话",
    Callback = function(v)
        sayMessage = v or ""
    end
})

mainTab:Input({
    Title = "发言次数",
    Desc = "一共发送几次",
    Callback = function(v)
        sayCount = tonumber(v) or 1
    end
})

mainTab:Slider({
    Title = "发言间隔",
    Desc = "每条消息间隔（秒）",
    Step = 0.5,
    Value = { Min = 0.5, Max = 10, Default = 1 },
    Callback = function(v)
        sayInterval = tonumber(v) or 1
    end
})

mainTab:Dropdown({
    Title = "发言方式",
    Desc = "公屏 = 发给所有人；私聊 = 只发给选中的玩家",
    Values = { "公屏", "私聊" },
    Value = "公屏",
    Callback = function(v)
        whisperOnly = (v == "私聊")
    end
})

mainTab:Toggle({
    Title = "开启发言",
    Desc = "按上面的设置开始/停止发言",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        speakEnabled = s
        if s then
            if sayMessage == "" then
                warn("[自动发言] 请先输入发言内容")
                speakEnabled = false
                return
            end
            if whisperOnly and not selectedTarget then
                warn("[自动发言] 私聊模式请先选择玩家")
                speakEnabled = false
                return
            end
            speakThread = task.spawn(function()
                for i = 1, math.max(1, sayCount) do
                    if not speakEnabled then break end
                    SendCurrent()
                    task.wait(math.clamp(sayInterval, 0.5, 10))
                end
                speakEnabled = false
            end)
        else
            if speakThread then
                task.cancel(speakThread)
                speakThread = nil
            end
        end
    end
})

WindUI:Notify({
    Title = "自动发言",
    Content = "脚本加载完成",
    Icon = "check",
    Duration = 3
})
