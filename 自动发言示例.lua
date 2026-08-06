-- 发言类 远程脚本（自动发言 + 私聊，依赖主脚本提供 SayTab）
-- 主脚本需设置：getgenv().Tabs.SayTab（或 getgenv().SutureSayTab）
print("[发言类] 远程脚本开始执行")

if getgenv().__SUTURE_SAY_LOADED then
    return
end
getgenv().__SUTURE_SAY_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.SayTab) or getgenv().SutureSayTab
if not Tab then
    warn("[发言类] 未找到 SayTab，请检查主脚本是否正确赋值")
    return
end

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

-- ===== 状态 =====
local sayMessage = ""
local sayCount = 1
local sayInterval = 1          -- 秒
local whisperOnly = false      -- 私聊模式
local speakEnabled = false
local speakThread = nil
local selectedTarget = nil

-- WindUI 下拉回调可能返回 table，统一解包成字符串
local function unwrap(v)
    if typeof(v) == "table" then
        return v.Value or v[1]
    end
    return v
end

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

-- 私聊：用显示名（DisplayName）发送 /w 指令
local function SendWhisper(target, message)
    if not target or not message or message == "" then return end
    SendChatMessage("/w " .. target.DisplayName .. " " .. message)
end

local function SendCurrent()
    if whisperOnly then
        if selectedTarget then
            SendWhisper(selectedTarget, sayMessage)
        else
            warn("[发言类] 找不到所选玩家，请重新选择")
        end
    else
        SendChatMessage(sayMessage)
    end
end

-- ===== UI：玩家选择（自动刷新） =====
local uiOk, uiErr = pcall(function()
    local playerNameList = {}
    local listKey = ""
    local selectedName = nil
    local TargetDropdown = nil
    local lastListRefresh = 0

    local function rebuildList()
        playerNameList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                table.insert(playerNameList, p.Name)
            end
        end
    end

    local function updateList(force)
        -- 限流：3 秒内最多真正刷新一次，避免频繁重建下拉框导致卡顿
        local now = os.clock()
        if not force and now - lastListRefresh < 3 then return end
        rebuildList()
        local key = table.concat(playerNameList, ",")
        if force or key ~= listKey then
            listKey = key
            lastListRefresh = now
            pcall(function()
                if TargetDropdown.Refresh then
                    TargetDropdown:Refresh(playerNameList, selectedName)
                else
                    TargetDropdown:SetValues(playerNameList)
                end
            end)
        end
    end

    rebuildList()

    TargetDropdown = Tab:Dropdown({
        Title = "选择玩家",
        Desc = "私聊对象；公屏发言时可忽略",
        Values = playerNameList,
        Value = playerNameList[1] or "无",
        Callback = function(v)
            v = unwrap(v)
            selectedName = v
            selectedTarget = (typeof(v) == "string") and Players:FindFirstChild(v) or nil
        end
    })

    Players.PlayerAdded:Connect(function() updateList(false) end)
    Players.PlayerRemoving:Connect(function() updateList(false) end)
    task.spawn(function()
        while true do
            task.wait(5)
            updateList(false)
        end
    end)

    updateList(true)

    -- ===== UI：发言设置 =====
    Tab:Input({
        Title = "发言内容",
        Desc = "要发送的话",
        Callback = function(v)
            sayMessage = v or ""
        end
    })

    Tab:Input({
        Title = "发言次数",
        Desc = "一共发送几次",
        Callback = function(v)
            sayCount = tonumber(v) or 1
        end
    })

    Tab:Slider({
        Title = "发言间隔",
        Desc = "每条消息间隔（秒）",
        Step = 0.5,
        Value = { Min = 0.5, Max = 10, Default = 1 },
        Callback = function(v)
            sayInterval = tonumber(v) or 1
        end
    })

    Tab:Dropdown({
        Title = "发言方式",
        Desc = "公屏 = 发给所有人；私聊 = 只发给选中的玩家",
        Values = { "公屏", "私聊" },
        Value = "公屏",
        Callback = function(v)
            v = unwrap(v)
            whisperOnly = (v == "私聊")
        end
    })

    Tab:Toggle({
        Title = "开启发言",
        Desc = "按上面的设置开始/停止发言",
        Type = "Checkbox",
        Value = false,
        Callback = function(s)
            speakEnabled = s
            if s then
                if sayMessage == "" then
                    warn("[发言类] 请先输入发言内容")
                    speakEnabled = false
                    return
                end
                if whisperOnly and not selectedTarget then
                    warn("[发言类] 私聊模式请先选择玩家")
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
end)

if not uiOk then
    warn("[发言类] Tab UI 创建失败:", uiErr)
else
    print("[发言类] 远程脚本加载完成")
end
