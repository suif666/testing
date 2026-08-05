-- 黑白脚本群卡片示例（WindUI + 直挂 GuiObject，兼容 Delta）
-- 布局：头像+群名 -> 提示小字 -> 复制按钮，垂直居中排列

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

local QQ群号 = "1062578052" -- 黑白脚本群群号，改成你自己的

local win = WindUI:CreateWindow({
    Title = "群组卡片示例",
    Icon = "aperture",
    Author = "demo",
    Folder = "GroupCardDemo",
    Size = UDim2.fromOffset(620, 460),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    NewElements = true,
})

local mainSec = win:Section({ Title = "群组", Icon = "folder", Opened = true })
local cardTab = mainSec:Tab({ Title = "卡片", Icon = "gem" })
cardTab:Select()

local cardSec = cardTab:Section({ Title = "黑白脚本群", Icon = "folder", Opened = true })
cardSec:Paragraph({ Title = "预览", Desc = "下面是自定义卡片（直挂 GuiObject）" })

-- 分组元素容器：直挂自定义 UI 的入口
local content = cardSec.ElementFrame.Outline.Content

-- ==================== 卡片本体 ====================
local card = Instance.new("Frame")
card.Name = "GroupCard"
card.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
card.BackgroundTransparency = 0.2
card.Size = UDim2.new(1, -24, 0, 150)
card.Parent = content

local cardList = Instance.new("UIListLayout")
cardList.FillDirection = Enum.FillDirection.Vertical
cardList.HorizontalAlignment = Enum.HorizontalAlignment.Center
cardList.VerticalAlignment = Enum.VerticalAlignment.Center
cardList.Padding = UDim.new(0, 8)
cardList.Parent = card

-- ==================== 第一层：头像 + 群名 ====================
local avatarRow = Instance.new("Frame")
avatarRow.BackgroundTransparency = 1
avatarRow.Size = UDim2.new(0, 250, 0, 56)
avatarRow.Parent = card

local rowList = Instance.new("UIListLayout")
rowList.FillDirection = Enum.FillDirection.Horizontal
rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowList.VerticalAlignment = Enum.VerticalAlignment.Center
rowList.Padding = UDim.new(0, 10)
rowList.Parent = avatarRow

-- 方形头像（暗色底 + 中间白色"黑白脚本"文字）
local avatar = Instance.new("Frame")
avatar.Name = "Avatar"
avatar.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
avatar.Size = UDim2.fromOffset(56, 56)
avatar.Parent = avatarRow
Instance.new("UICorner", avatar).CornerRadius = UDim.new(0, 10)

local avatarText = Instance.new("TextLabel")
avatarText.BackgroundTransparency = 1
avatarText.Size = UDim2.new(1, 0, 1, 0)
avatarText.Font = Enum.Font.GothamBold
avatarText.Text = "黑白脚本"
avatarText.TextColor3 = Color3.fromRGB(255, 255, 255)
avatarText.TextSize = 13
avatarText.Parent = avatar

-- 群名（纯白加粗大字，垂直居中）
local groupName = Instance.new("TextLabel")
groupName.BackgroundTransparency = 1
groupName.Size = UDim2.new(0, 180, 0, 56)
groupName.Font = Enum.Font.GothamBold
groupName.Text = "黑白脚本群"
groupName.TextColor3 = Color3.fromRGB(255, 255, 255)
groupName.TextSize = 24
groupName.TextXAlignment = Enum.TextXAlignment.Left
groupName.Parent = avatarRow

-- ==================== 第二层：提示小字 ====================
local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(0, 300, 0, 18)
hint.Font = Enum.Font.Gotham
hint.Text = "点击按钮获取黑白脚本群QQ号"
hint.TextColor3 = Color3.fromRGB(190, 190, 198)
hint.TextSize = 13
hint.Parent = card

-- ==================== 第三层：复制按钮 ====================
local copyBtn = Instance.new("TextButton")
copyBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
copyBtn.Size = UDim2.new(0, 180, 0, 38)
copyBtn.Font = Enum.Font.GothamBold
copyBtn.Text = "复制群号"
copyBtn.TextColor3 = Color3.fromRGB(20, 20, 25)
copyBtn.TextSize = 16
copyBtn.Parent = card
Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 8)

copyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(QQ群号)
        pcall(WindUI.Notify, WindUI, {
            Title = "复制成功",
            Content = "群号已复制：" .. QQ群号,
            Icon = "clipboard",
            Duration = 2,
        })
    else
        warn("当前环境不支持 setclipboard")
    end
end)

WindUI:Notify({
    Title = "群组卡片示例",
    Content = "卡片已生成，试试复制按钮",
    Icon = "aperture",
    Duration = 4,
})
