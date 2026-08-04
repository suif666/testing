-- WindUI 折叠演示
-- 左侧边栏：窗口级 Section（标签分组）折叠
-- 右侧内容区：Tab 级 Section（元素分组）折叠
-- 用法：直接复制进注入器执行，会从 GitHub 在线加载 WindUI

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

local win = WindUI:CreateWindow({
    Title = "折叠演示",
    Icon = "aperture",
    Author = "demo",
    Folder = "CollapseDemo",
    Size = UDim2.fromOffset(620, 460),
    MinSize = Vector2.new(560, 350),
    MaxSize = Vector2.new(900, 600),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    NewElements = true,
})

-- ==================== 左侧边栏：窗口级 Section ====================
-- win:Section 创建“标签分组”，标题栏右侧的小三角就是折叠按钮。
-- Opened = true 初始展开，Opened = false 初始收起。
local gameSec = win:Section({ Title = "游戏功能", Icon = "folder", Opened = true })
local playerTab = gameSec:Tab({ Title = "玩家", Icon = "user" })
local visualTab = gameSec:Tab({ Title = "视觉", Icon = "palette" })
local fightTab = gameSec:Tab({ Title = "战斗", Icon = "swords" })

local scriptSec = win:Section({ Title = "脚本库", Icon = "folder", Opened = false })
local feTab = scriptSec:Tab({ Title = "Fe脚本", Icon = "shell" })
local toolTab = scriptSec:Tab({ Title = "工具", Icon = "wrench" })

local aboutSec = win:Section({ Title = "关于", Icon = "info", Opened = true })
local aboutTab = aboutSec:Tab({ Title = "说明", Icon = "book-open" })

-- ==================== 右侧内容区：Tab 级 Section ====================
-- tab:Section 创建“元素分组”，同样支持小三角折叠。
playerTab:Select()

local function demoSection(tab, title, icon, opened)
    return tab:Section({ Title = title, Icon = icon, Opened = opened })
end

local baseSec = demoSection(playerTab, "基础设置", "settings", true)
baseSec:Paragraph({
    Title = "说明",
    Desc = "右侧这些分组和左边一样\n点击标题栏小三角即可折叠",
})
baseSec:Toggle({
    Title = "示例开关",
    Desc = "Toggle 演示",
    Value = true,
    Callback = function(v)
        print("开关:", v)
    end,
})
baseSec:Slider({
    Title = "示例滑条",
    Step = 1,
    Value = { Min = 0, Max = 100, Default = 50 },
    Callback = function(v)
        print("滑条:", v)
    end,
})

local advSec = demoSection(playerTab, "高级选项", "sliders-horizontal", false)
advSec:Dropdown({
    Title = "选择模式",
    Values = { "模式A", "模式B", "模式C" },
    Value = "模式A",
    Callback = function(v)
        print("下拉:", v)
    end,
})
advSec:Button({
    Title = "执行按钮",
    Desc = "点击后打印",
    Callback = function()
        print("按钮被点击")
    end,
})

-- 视觉标签页：再演示一组右侧折叠
local visualSec = visualTab:Section({ Title = "显示设置", Icon = "palette", Opened = true })
visualSec:Toggle({
    Title = "显示FPS",
    Value = false,
    Callback = function(v)
        print("显示FPS:", v)
    end,
})
visualSec:Dropdown({
    Title = "位置",
    Values = { "左上", "右上", "左下", "右下" },
    Value = "右上",
    Callback = function(v)
        print("位置:", v)
    end,
})

-- 战斗/Fe脚本/工具标签页给点内容，避免空白
fightTab:Paragraph({ Title = "战斗", Desc = "留空示例" })
feTab:Paragraph({ Title = "Fe脚本", Desc = "留空示例" })
toolTab:Paragraph({ Title = "工具", Desc = "留空示例" })

aboutTab:Paragraph({
    Title = "折叠演示",
    Desc = "左侧：窗口级 Section 折叠标签组\n右侧：Tab 级 Section 折叠元素组\n\n初始展开/收起由 Opened 参数控制",
})

WindUI:Notify({
    Title = "折叠演示",
    Content = "加载完成！试试左右两侧的小三角",
    Icon = "aperture",
    Duration = 4,
})
