-- 数学谋杀案 自动答题（WindUI 独立版）
-- 移植自 XIAOXI付费版数学谋杀案，UI 换成 WindUI
-- 用法：在数学谋杀案游戏里直接执行本脚本

if getgenv().__SUTURE_MATH_MURDER_LOADED then
    return
end
getgenv().__SUTURE_MATH_MURDER_LOADED = true

-- ==================== WindUI 加载 ====================
local WindUI
local ok, res = pcall(function()
    return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)
if not ok then
    warn("[数学谋杀案] WindUI 加载失败:", res)
    return
end
WindUI = res

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

-- ==================== 游戏引用 ====================
local Screen, QuestionText, TypingText, Fill
local CurrentSpeller, ClickSound, GameEvent

local function initGameRefs()
    local okRefs = pcall(function()
        local map = workspace:FindFirstChild("Map")
        local functional = map and map:FindFirstChild("Functional")
        local s = functional and functional:FindFirstChild("Screen")
        if not s then
            return nil
        end
        local mainContainer = s.SurfaceGui.MainFrame.MainGameContainer
        Screen = s
        QuestionText = mainContainer.MainTxtContainer.QuestionText
        TypingText = mainContainer.MainTxtContainer.TypingText
        Fill = mainContainer.TimerbarContainer.Fill
    end)
    local okVals = pcall(function()
        CurrentSpeller = ReplicatedStorage.GameValues.CurrentSpeller
        ClickSound = ReplicatedStorage.Assets.SFX.Click
        GameEvent = ReplicatedStorage.Events.GameEvent
    end)
    return okRefs and okVals and QuestionText ~= nil
end

if not initGameRefs() then
    warn("[数学谋杀案] 未找到游戏界面（workspace.Map.Functional.Screen），请确认在数学谋杀案游戏里执行")
    return
end

-- ==================== 全局设置 ====================
local AutoAnswerEnabled = false      -- 秒回答
local Delay6Enabled = false          -- 6秒回答
local Delay9Enabled = false          -- 9秒回答
local CustomDelayEnabled = false     -- 自定义延迟
local CustomDelaySeconds = 5         -- 自定义延迟秒数
local TypingSpeed = 0.05             -- 打字速度（秒/字符）
local ErrorSpeed = 0.1
local MaxGuessNumber = 200
local RandomPauseChance = 0.2
local BigErrorChance = 0.2           -- 重大错误概率
local InstantSubmit = false          -- 即时提交

-- ==================== 通用函数 ====================
local function SetTyping(text)
    if ClickSound then
        pcall(function() ClickSound:Play() end)
    end
    pcall(function()
        TypingText.Text = text
        GameEvent:FireServer("updateAnswer", text)
    end)
end

local function HumanType(target)
    local text = ""
    while text ~= target do
        -- 重大错误模拟（打错字再删）
        if math.random() < BigErrorChance then
            local wrong = tostring(math.random(1, MaxGuessNumber))
            SetTyping(wrong)
            task.wait(ErrorSpeed * math.random(1, 2))
            SetTyping(string.sub(wrong, 1, math.random(0, #wrong)))
            task.wait(ErrorSpeed)
        end

        -- 正常打字
        local nextLen = #TypingText.Text + 1
        text = string.sub(target, 1, nextLen)
        SetTyping(text)

        -- 随机停顿
        if math.random() < RandomPauseChance then
            task.wait(TypingSpeed * (1 + math.random()))
        else
            task.wait(TypingSpeed)
        end

        -- 即时提交
        if InstantSubmit and text == target then
            GameEvent:FireServer("submitAnswer", text)
        end
    end
end

-- ==================== 旧连接清理（重复执行不冲突） ====================
if getgenv().mathMurderConnections then
    for _, c in ipairs(getgenv().mathMurderConnections) do
        pcall(function() c:Disconnect() end)
    end
end
local Connections = {}
getgenv().mathMurderConnections = Connections

-- ==================== 窗口 ====================
local win = WindUI:CreateWindow({
    Title = "数学谋杀案 自动答题",
    Icon = "calculator",
    Author = "WindUI 移植版",
    Folder = "MathMurder",
    Size = UDim2.fromOffset(560, 420),
    MinSize = Vector2.new(480, 320),
    MaxSize = Vector2.new(800, 560),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 160,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    NewElements = true,
    User = { Enabled = false }
})

-- ==================== Tab1：秒回答 ====================
local tab1 = win:Tab({ Title = "秒回答", Icon = "zap", Locked = false })
local sec1 = tab1:Section({ Title = "立即回答", Icon = "settings", Opened = true })

tab1:Paragraph({
    Title = "说明",
    Desc = "成为数学大手😍"
})

tab1:Toggle({
    Title = "启用秒回答",
    Desc = "题目出现后立即计算并回答（随机延迟 0.1~0.3 秒）",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        if v then
            Delay6Enabled = false
            Delay9Enabled = false
            CustomDelayEnabled = false
            AutoAnswerEnabled = true
        else
            AutoAnswerEnabled = false
        end
    end
})

-- ==================== Tab2：演戏回答（6秒） ====================
local tab2 = win:Tab({ Title = "演戏回答", Icon = "clapperboard", Locked = false })
local sec2 = tab2:Section({ Title = "在六秒后自动回答", Icon = "settings", Opened = true })

tab2:Paragraph({
    Title = "说明",
    Desc = "演戏回答防止别人看出你是挂"
})

tab2:Toggle({
    Title = "启用演戏回答",
    Desc = "等 6 秒再回答",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        if v then
            AutoAnswerEnabled = false
            Delay9Enabled = false
            CustomDelayEnabled = false
            Delay6Enabled = true
        else
            Delay6Enabled = false
        end
    end
})

-- ==================== Tab3：最后一刻回答（9秒） ====================
local tab3 = win:Tab({ Title = "最后一刻", Icon = "timer", Locked = false })
local sec3 = tab3:Section({ Title = "在最后一秒回答", Icon = "settings", Opened = true })

tab3:Paragraph({
    Title = "说明",
    Desc = "装逼专属，在最后一秒直接回答正确答案"
})

tab3:Toggle({
    Title = "启用在最后一秒回答",
    Desc = "等 9 秒压线回答",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        if v then
            AutoAnswerEnabled = false
            Delay6Enabled = false
            CustomDelayEnabled = false
            Delay9Enabled = true
        else
            Delay9Enabled = false
        end
    end
})

-- ==================== Tab4：自定义延迟 ====================
local tab4 = win:Tab({ Title = "自定义", Icon = "settings-2", Locked = false })
local sec4 = tab4:Section({ Title = "自定义回答", Icon = "settings", Opened = true })

tab4:Paragraph({
    Title = "说明",
    Desc = "可自定义输入回答速度"
})

tab4:Toggle({
    Title = "启用自定义回答",
    Desc = "按你设置的秒数延迟回答",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        if v then
            AutoAnswerEnabled = false
            Delay6Enabled = false
            Delay9Enabled = false
            CustomDelayEnabled = true
        else
            CustomDelayEnabled = false
        end
    end
})

tab4:Slider({
    Title = "在几秒回答",
    Desc = "1 ~ 9 秒",
    Step = 0.5,
    Value = { Min = 1, Max = 9, Default = 5 },
    Callback = function(v)
        CustomDelaySeconds = v
    end
})

-- ==================== Tab5：设置（拟人化） ====================
local tabS = win:Tab({ Title = "设置", Icon = "sliders-horizontal", Locked = false })
local secS = tabS:Section({ Title = "拟人化设置", Icon = "settings", Opened = true })

tabS:Slider({
    Title = "打字速度 (秒/字符)",
    Desc = "越小打得越快（0.01 最快）",
    Step = 0.01,
    Value = { Min = 0.01, Max = 0.2, Default = 0.05 },
    Callback = function(v)
        TypingSpeed = v
    end
})

tabS:Slider({
    Title = "重大错误概率 (%)",
    Desc = "模拟打错字再改，越高越像真人",
    Step = 1,
    Value = { Min = 0, Max = 50, Default = 20 },
    Callback = function(v)
        BigErrorChance = v / 100
    end
})

tabS:Toggle({
    Title = "即时提交",
    Desc = "输完即交（不勾选则等游戏触发提交）",
    Type = "Checkbox",
    Value = false,
    Callback = function(v)
        InstantSubmit = v
    end
})

-- ==================== 核心监听逻辑 ====================
local CurrentQuestionResult

table.insert(Connections, QuestionText:GetPropertyChangedSignal("Text"):Connect(function()
    -- 所有模式都关闭则忽略
    if not AutoAnswerEnabled and not Delay6Enabled and not Delay9Enabled and not CustomDelayEnabled then
        return
    end
    if CurrentSpeller.Value ~= lp then
        return
    end

    -- 计算答案
    local question = string.split(QuestionText.Text, "=")[1]
    if not question or question == "" then
        return
    end

    local success, result = pcall(function()
        return tostring(loadstring("return " .. string.gsub(question, "x", "*"))())
    end)
    if not success then
        return
    end
    CurrentQuestionResult = result
    Fill:SetAttribute("Answer", result)

    -- ===== 模式1：秒回答 =====
    if AutoAnswerEnabled then
        task.wait(math.random(1, 3) / 10)
        HumanType(result)
        if not InstantSubmit then
            GameEvent:FireServer("submitAnswer", result)
        end
    end

    -- ===== 模式2：6秒回答 =====
    if Delay6Enabled then
        SetTyping("")
        task.wait(6)
        HumanType(result)
        if not InstantSubmit then
            GameEvent:FireServer("submitAnswer", result)
        end
    end

    -- ===== 模式3：9秒回答 =====
    if Delay9Enabled then
        SetTyping("")
        task.wait(9)
        HumanType(result)
        if not InstantSubmit then
            GameEvent:FireServer("submitAnswer", result)
        end
    end

    -- ===== 模式4：自定义延迟 =====
    if CustomDelayEnabled then
        SetTyping("")
        task.wait(CustomDelaySeconds)
        HumanType(result)
        if not InstantSubmit then
            GameEvent:FireServer("submitAnswer", result)
        end
    end
end))

print("[数学谋杀案] WindUI 版已加载")
warn("[数学谋杀案] 检测到此服务器数学谋杀案")
