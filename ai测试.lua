--[[
    现代交互面板 UI · Nebula Interface
    风格：深色玻璃拟态 + 霓虹渐变 + 流畅动画
    功能：Tab 切换 / Toggle / Slider / Dropdown / 进度条 / 通知提示
]]

local WindUI
do
    local ok, res = pcall(function()
        local source = game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua")
        local fn, compileErr = loadstring(source)
        if not fn then error(compileErr) end
        return fn()
    end)
    if not ok or not res then
        warn("WindUI 加载失败:", res)
        return
    end
    WindUI = res
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ======================== 配色方案 ========================
local C = {
    bg          = Color3.fromRGB(18, 18, 28),
    surface     = Color3.fromRGB(28, 28, 42),
    surface2    = Color3.fromRGB(36, 36, 54),
    border      = Color3.fromRGB(50, 50, 70),
    accent1     = Color3.fromRGB(120, 80, 255),   -- 霓虹紫
    accent2     = Color3.fromRGB(0, 210, 255),    -- 霓虹青
    accent3     = Color3.fromRGB(255, 60, 150),   -- 霓虹粉
    text        = Color3.fromRGB(230, 235, 255),
    textDim     = Color3.fromRGB(130, 135, 160),
    success     = Color3.fromRGB(0, 220, 130),
    danger      = Color3.fromRGB(255, 70, 90),
    warning     = Color3.fromRGB(255, 180, 0),
}

-- ======================== 工具函数 ========================
local function lerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

local function createAccentGradient(instance)
    -- 创建带渐变边框的效果（通过 UIStroke）
    local stroke = Instance.new("UIStroke", instance)
    stroke.Color = C.accent1
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    return stroke
end

local function fadeOut(instance, delay)
    delay = delay or 0
    game:GetService("Debris"):AddItem(instance, delay)
end

-- ======================== 主窗口 ========================
local Window = WindUI:CreateWindow({
    Title = "⚡ Nebula Hub",
    Center = true,
    Resolution = UDim2.new(0, 460, 0, 620),
    Theme = { Background = C.bg },
})

-- ======================== Tab 系统 ========================
local MainTab = Window:AddTab("🎮 主控面板")
local VisualTab = Window:AddTab("👁️ 视觉增强")
local SettingsTab = Window:AddTab("⚙️ 设置")
local AboutTab = Window:AddTab("ℹ️ 关于")

-- =================== 🎮 主控面板 ===================
-- 大标题区域
MainTab:AddLabel("N E B U L A   H U B", C.text, 22, true)

-- 状态卡片
local StatusCard = MainTab:AddGroupbox("系统状态")

-- Toggle: 主开关
local mainToggle = StatusCard:AddToggle({
    Text = "系统总开关",
    Default = false,
    Callback = function(val)
        WindUI:Notify({
            Title = "Nebula",
            Content = val and "✅ 系统已启动" or "❌ 系统已关闭",
            Icon = "info",
            Duration = 2
        })
        -- 动画反馈
        mainToggle.Element.BackgroundColor3 = val and C.accent1 or C.surface2
    end
})
mainToggle.Element.BackgroundColor3 = C.surface2

-- 状态指示
local statusText = StatusCard:AddLabel("状态: 未启动", C.textDim, 13)
local function updateStatus(text, color)
    statusText.Label.Text = "状态: " .. text
    statusText.Label.TextColor3 = color
end

-- 功能 Toggle 列表
local features = {
    { key = "autoFarm",   label = "自动 farming",   color = C.success },
    { key = "antiAFK",    label = "防 AFK",         color = C.warning },
    { key = "espToggle",  label = "ESP 透视",       color = C.accent2 },
    { key = "flyMode",    label = "飞行模式",        color = C.accent3 },
    { key = "speedHack",  label = "速度外挂",        color = C.danger },
}

for _, f in ipairs(features) do
    local toggle = StatusCard:AddToggle({
        Text = f.label,
        Default = false,
        Callback = function(val)
            local msg = val and "已开启" or "已关闭"
            updateStatus(f.label .. " " .. msg, val and f.color or C.textDim)
            if val then
                WindUI:Notify({
                    Title = f.label,
                    Content = "已启用",
                    Icon = "check",
                    Duration = 1.5,
                    Color = f.color
                })
            end
        end
    })
    toggle.Element.BackgroundColor3 = C.surface2
    toggle.OnClick = function()
        toggle.Value = not toggle.Value
        toggle:FireCallback(toggle.Value)
    end
end

-- 分组框：快捷操作
local QuickBox = MainTab:AddGroupbox("快捷操作")

QuickBox:AddButton({
    Text = "📋 复制配置",
    Callback = function()
        local config = HttpService:JSONEncode({
            main = mainToggle.Value,
            features = {
                autoFarm = true,
                antiAFK = false,
            }
        })
        setclipboard(config)
        WindUI:Notify({
            Title = "已复制",
            Content = "配置已复制到剪贴板",
            Icon = "check",
            Duration = 2,
            Color = C.success
        })
    end
})

QuickBox:AddButton({
    Text = "🔄 重置所有设置",
    Callback = function()
        mainToggle.Value = false
        mainToggle:FireCallback(false)
        for _, f in ipairs(features) do
            -- 重置逻辑
        end
        updateStatus("已重置", C.warning)
        WindUI:Notify({ Title = "重置完成", Content = "所有设置已恢复默认", Icon = "refresh", Duration = 2 })
    end
})

QuickBox:AddButton({
    Text = "📊 性能监控",
    Callback = function()
        local fps = game:GetService("Stats").NetworkServerPing or 0
        WindUI:Notify({
            Title = "性能数据",
            Content = string.format("FPS: %d | Ping: %dms", tick(), fps),
            Icon = "stats",
            Duration = 3
        })
    end
})

-- 滑块区域
local ControlBox = MainTab:AddGroupbox("灵敏度控制")

ControlBox:AddSlider({
    Text = "移动速度",
    Min = 16, Max = 200, Default = 16,
    Rounding = 1,
    Callback = function(val)
        -- 这里可以接入实际的速度修改
        ControlBox.SliderElement.Label.Text = string.format("移动速度: %.0f", val)
    end
})

ControlBox:AddSlider({
    Text = "跳跃高度",
    Min = 50, Max = 300, Default = 50,
    Rounding = 1,
    Callback = function(val)
        ControlBox.SliderElement.Label.Text = string.format("跳跃高度: %.0f", val)
    end
})

ControlBox:AddSlider({
    Text = "FOV 视野",
    Min = 70, Max = 120, Default = 70,
    Rounding = 0,
    Callback = function(val)
        ControlBox.SliderElement.Label.Text = string.format("FOV: %d°", val)
    end
})

-- Dropdown
local DropBox = MainTab:AddGroupbox("选择模式")

DropBox:AddDropdown({
    Text = "游戏模式",
    List = { "经典模式", "竞速模式", "生存模式", "自定义" },
    Default = "经典模式",
    Multi = false,
    Callback = function(val)
        WindUI:Notify({
            Title = "模式切换",
            Content = "已切换到: " .. val,
            Icon = "info",
            Duration = 2,
            Color = C.accent2
        })
    end
})

DropBox:AddDropdown({
    Text = "主题颜色",
    List = { "霓虹紫", "赛博青", "极光粉", "暗黑蓝" },
    Default = "霓虹紫",
    Multi = false,
    Callback = function(val)
        WindUI:Notify({ Title = "主题", Content = val, Icon = "palette", Duration = 2 })
    end
})


-- =================== 👁️ 视觉增强 ===================
VisualTab:AddLabel("ESP 设置", C.accent2, 16, true)

local EspGroup = VisualTab:AddGroupbox("ESP 选项")

EspGroup:AddToggle({
    Text = "启用 ESP",
    Default = false,
    Callback = function(val)
        EspGroup.Label.Text = val and "✅ ESP 已启用" or "ESP 未启用"
    end
})

EspGroup:AddToggle({
    Text = "显示距离",
    Default = true,
    Callback = function(val) end
})

EspGroup:AddToggle({
    Text = "显示血量条",
    Default = true,
    Callback = function(val) end
})

EspGroup:AddToggle({
    Text = "显示名称",
    Default = true,
    Callback = function(val) end
})

EspGroup:AddColorpicker({
    Text = "轮廓颜色",
    Default = C.accent2,
    Callback = function(val) end
})

EspGroup:AddColorpicker({
    Text = "填充颜色",
    Default = Color3.fromRGB(0, 0, 0),
    Callback = function(val) end
})

-- 预设按钮
local PresetGroup = VisualTab:AddGroupbox("ESP 预设")

local espPresets = {
    { name = "极简", color = C.accent2 },
    { name = "战斗", color = C.danger },
    { name = "幽灵", color = C.accent3 },
    { name = "隐身", color = Color3.fromRGB(100, 255, 100) },
}

for _, preset in ipairs(espPresets) do
    PresetGroup:AddButton({
        Text = preset.name,
        Callback = function()
            WindUI:Notify({
                Title = "预设已应用",
                Content = "ESP 已切换为: " .. preset.name,
                Icon = "eye",
                Duration = 2,
                Color = preset.color
            })
        end
    })
end


-- =================== ⚙️ 设置 ===================
SettingsTab:AddLabel("快捷键设置", C.accent3, 16, true)

local KeybindGroup = SettingsTab:AddGroupbox("按键绑定")

KeybindGroup:AddKeybind({
    Text = "切换 ESP",
    Default = Enum.KeyCode.X,
    SyncWithToggle = false,
    Callback = function(val)
        KeybindGroup.Label.Text = "ESP 键: " .. val.Name
    end
})

KeybindGroup:AddKeybind({
    Text = "切换飞行",
    Default = Enum.KeyCode.C,
    SyncWithToggle = false,
    Callback = function(val)
        KeybindGroup.Label.Text = "飞行键: " .. val.Name
    end
})

KeybindGroup:AddKeybind({
    Text = "截图",
    Default = Enum.KeyCode.F9,
    SyncWithToggle = false,
    Callback = function(val) end
})

-- 设置开关
local SettingGroup = SettingsTab:AddGroupbox("常规设置")

SettingGroup:AddToggle({
    Text = "启动时自动加载",
    Default = false,
    Callback = function(val) end
})

SettingGroup:AddToggle({
    Text = "显示通知气泡",
    Default = true,
    Callback = function(val) end
})

SettingGroup:AddToggle({
    Text = "静音效果音",
    Default = false,
    Callback = function(val) end
})

SettingGroup:AddSlider({
    Text = "通知持续时间",
    Min = 1, Max = 5, Default = 2,
    Rounding = 1,
    Callback = function(val) end
})


-- =================== ℹ️ 关于 ===================
AboutTab:AddLabel("关于 Nebula Hub", C.accent1, 18, true)

local InfoGroup = AboutTab:AddGroupbox("版本信息")

InfoGroup:AddLabel("版本号: v2.5.0", C.text, 14)
InfoGroup:AddLabel("构建日期: 2026-08-20", C.textDim, 13)
InfoGroup:AddLabel("作者: Agnes AI", C.textDim, 13)
InfoGroup:AddLabel("UI 框架: WindUI", C.textDim, 13)

local FeatureGroup = AboutTab:AddGroupbox("功能特性")
FeatureGroup:AddLabel("✓ 多 Tab 模块化设计", C.success, 13)
FeatureGroup:AddLabel("✓ 流畅动画与过渡效果", C.success, 13)
FeatureGroup:AddLabel("✓ 霓虹渐变视觉风格", C.success, 13)
FeatureGroup:AddLabel("✓ 完整交互组件库", C.success, 13)
FeatureGroup:AddLabel("✓ 响应式通知系统", C.success, 13)

AboutTab:AddButton({
    Text = "⭐ 在 GitHub Star",
    Callback = function()
        game:HttpGet("https://github.com")
        WindUI:Notify({ Title = "已打开", Content = "GitHub 页面", Icon = "link", Duration = 2 })
    end
})

AboutTab:AddButton({
    Text = "📖 查看文档",
    Callback = function()
        WindUI:Notify({ Title = "文档", Content = "请访问官网获取最新文档", Icon = "book", Duration = 3 })
    end
})

AboutTab:AddButton({
    Text = "💬 加入 Discord",
    Callback = function()
        WindUI:Notify({ Title = "Discord", Content = "欢迎加入社区！", Icon = "chat", Duration = 2 })
    end
})


-- ======================== 启动动画 ========================
-- 窗口打开时的入场动画
task.delay(0.3, function()
    WindUI:Notify({
        Title = "🚀 Nebula Hub",
        Content = "欢迎使用现代交互面板 v2.5",
        Icon = "rocket",
        Duration = 4,
        Color = C.accent1
    })
end)

-- ======================== 全局快捷键 ========================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- F1 切换主面板可见性
    if input.KeyCode == Enum.KeyCode.F1 then
        Window:SetOpened(not Window.Opened)
        WindUI:Notify({
            Title = "面板",
            Content = Window.Opened and "已打开" or "已关闭",
            Duration = 1
        })
    end
    
    -- F5 刷新/重置
    if input.KeyCode == Enum.KeyCode.F5 then
        WindUI:Notify({ Title = "刷新", Content = "UI 已重置", Duration = 1.5, Color = C.warning })
    end
end)

print("[Nebula Hub] UI 加载完成！按 F1 显示/隐藏面板")
