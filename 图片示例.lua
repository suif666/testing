-- WindUI 图片 + 自定义图标示例
-- 用法：复制进注入器执行，先登录 Roblox 并把下面的 asset id 换成你自己上传的图片

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

-- ==================== 自定义图标 ====================
-- 注册一个名为 mypack 的图标包，之后用 "mypack:图标名" 引用
WindUI.Creator.AddIcons("mypack", {
    sword = "rbxassetid://替换成你的图片id",     -- 单张图片当图标
    gem = 1234567890,                             -- 传数字 id 也可以
    -- 图集（雪碧图）里的某一个图标：
    -- sprite = {
    --     Image = "rbxassetid://图集id",
    --     ImageRectSize = Vector2.new(24, 24),
    --     ImageRectPosition = Vector2.new(0, 0),
    -- },
})

local win = WindUI:CreateWindow({
    Title = "图片/图标示例",
    Icon = "aperture",
    Author = "demo",
    Folder = "ImageDemo",
    Size = UDim2.fromOffset(620, 460),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    NewElements = true,
})

local demoSection = win:Section({ Title = "图片演示", Icon = "folder", Opened = true })
local demoTab = demoSection:Tab({ Title = "内容", Icon = "image" })

demoTab:Select()

-- ==================== 右侧内容区放图片 ====================
local imgSec = demoTab:Section({ Title = "直接放图片", Icon = "folder", Opened = true })

imgSec:Image({
    Image = "rbxassetid://替换成你的图片id", -- rbxassetid / rbxthumb 链接都行
    AspectRatio = "16:9",                    -- 或数字 1.777
    Radius = 8,                              -- 圆角
})

-- ==================== 用自定义图标 ====================
local iconSec = demoTab:Section({ Title = "自定义图标", Icon = "folder", Opened = true })

iconSec:Button({
    Title = "用 mypack:sword 图标",
    Desc = "图标会跟随主题色",
    Icon = "mypack:sword",
    Callback = function()
        print("点击了自定义图标按钮")
    end,
})

iconSec:Toggle({
    Title = "自定义图标开关",
    Icon = "mypack:gem",
    Value = false,
    Callback = function(v)
        print("开关:", v)
    end,
})

WindUI:Notify({
    Title = "图片/图标示例",
    Content = "记得把示例里的 rbxassetid 换成你自己的图片",
    Icon = "aperture",
    Duration = 5,
})
