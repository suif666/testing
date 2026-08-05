-- 黑白脚本群卡片示例 v2（WindUI + 直挂 GuiObject，兼容 Delta）
-- 结构：深色底板 -> 少女预览图 -> 头像+群名 -> 提示小字 -> 白色复制按钮
print("[卡片示例] 开始执行")

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
print("[卡片示例] WindUI 加载完成")

local qqNumber = "1062578052" -- 黑白脚本群群号，改成你自己的
local previewImage = "rbxassetid://80369590845546" -- 预览图，换成你的图片

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
print("[卡片示例] 窗口创建完成")

local mainSec = win:Section({ Title = "群组", Icon = "folder", Opened = true })
local cardTab = mainSec:Tab({ Title = "卡片", Icon = "gem" })
cardTab:Select()

local cardSec = cardTab:Section({ Title = "黑白脚本群", Icon = "folder", Opened = true })
cardSec:Paragraph({ Title = "预览", Desc = "下面是自定义卡片（直挂 GuiObject）" })
print("[卡片示例] 分组创建完成")

local okCard, errCard = pcall(function()
    local content = cardSec.ElementFrame.Outline.Content

    -- ============ 1. 深色半透明底板（暗紫-黑） ============
    local panel = Instance.new("Frame")
    panel.Name = "GroupPanel"
    panel.BackgroundColor3 = Color3.fromRGB(18, 14, 32)   -- 暗紫黑
    panel.BackgroundTransparency = 0.25
    panel.Size = UDim2.new(1, -24, 0, 320)
    panel.ClipsDescendants = true
    panel.Parent = content
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

    -- 底板背景的蓝色霓虹"黑白"装饰字（藏在最底层）
    local neonText = Instance.new("TextLabel")
    neonText.BackgroundTransparency = 1
    neonText.Size = UDim2.new(1, 0, 0, 90)
    neonText.Position = UDim2.new(0, 0, 0, 110)
    neonText.ZIndex = 1
    neonText.Font = Enum.Font.GothamBold
    neonText.Text = "黑白"
    neonText.TextColor3 = Color3.fromRGB(40, 110, 255)
    neonText.TextTransparency = 0.78
    neonText.TextStrokeTransparency = 0.45
    neonText.TextSize = 72
    neonText.Parent = panel

    -- 内容层（盖在霓虹字上面）
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Vertical
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.Padding = UDim.new(0, 12)
    list.Parent = panel

    -- ============ 2. 上方二次元预览框（黑色圆角长方形） ============
    local preview = Instance.new("Frame")
    preview.Name = "PreviewBox"
    preview.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    preview.Size = UDim2.new(0, 420, 0, 120)
    preview.ClipsDescendants = true
    preview.Parent = panel
    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 10)

    local previewImg = Instance.new("ImageLabel")
    previewImg.Image = previewImage
    previewImg.BackgroundTransparency = 1
    previewImg.Size = UDim2.new(1, 0, 1, 0)
    previewImg.ScaleType = Enum.ScaleType.Crop -- 铺满裁切; 想完整显示用 Fit
    previewImg.Parent = preview

    -- ============ 3. 头像 + 群名（水平居中、垂直对齐中线） ============
    local avatarRow = Instance.new("Frame")
    avatarRow.BackgroundTransparency = 1
    avatarRow.Size = UDim2.new(0, 260, 0, 56)
    avatarRow.ZIndex = 2
    avatarRow.Parent = panel

    local rowList = Instance.new("UIListLayout")
    rowList.FillDirection = Enum.FillDirection.Horizontal
    rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowList.VerticalAlignment = Enum.VerticalAlignment.Center
    rowList.Padding = UDim.new(0, 10)
    rowList.Parent = avatarRow

    -- 正方形头像（暗色底 + 白色"黑白脚本"）
    local avatar = Instance.new("Frame")
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

    -- 群名（纯白加粗大字）
    local groupName = Instance.new("TextLabel")
    groupName.BackgroundTransparency = 1
    groupName.Size = UDim2.new(0, 190, 0, 56)
    groupName.Font = Enum.Font.GothamBold
    groupName.Text = "黑白脚本群"
    groupName.TextColor3 = Color3.fromRGB(255, 255, 255)
    groupName.TextSize = 24
    groupName.TextXAlignment = Enum.TextXAlignment.Left
    groupName.Parent = avatarRow

    -- ============ 4. 功能提示小字 ============
    local hint = Instance.new("TextLabel")
    hint.BackgroundTransparency = 1
    hint.Size = UDim2.new(0, 320, 0, 18)
    hint.ZIndex = 2
    hint.Font = Enum.Font.Gotham
    hint.Text = "点击按钮获取黑白脚本群QQ号"
    hint.TextColor3 = Color3.fromRGB(190, 190, 198)
    hint.TextSize = 13
    hint.Parent = panel

    -- ============ 5. 白色复制按钮（空心皇冠 + 文字） ============
    local copyBtn = Instance.new("TextButton")
    copyBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    copyBtn.Size = UDim2.new(0, 200, 0, 42)
    copyBtn.ZIndex = 2
    copyBtn.Parent = panel
    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(1, 0) -- 大圆角胶囊

    -- 按钮内部：皇冠图标 + 间隔 + 黑色文字，水平垂直居中
    local btnInner = Instance.new("Frame")
    btnInner.BackgroundTransparency = 1
    btnInner.Size = UDim2.new(1, 0, 1, 0)
    btnInner.ZIndex = 3
    btnInner.Parent = copyBtn

    local btnList = Instance.new("UIListLayout")
    btnList.FillDirection = Enum.FillDirection.Horizontal
    btnList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    btnList.VerticalAlignment = Enum.VerticalAlignment.Center
    btnList.Padding = UDim.new(0, 8)
    btnList.Parent = btnInner

    -- 浅灰色空心皇冠（WindUI lucide 图标）
    local crownImg = Instance.new("ImageLabel")
    crownImg.Size = UDim2.fromOffset(20, 20)
    crownImg.BackgroundTransparency = 1
    crownImg.ImageColor3 = Color3.fromRGB(160, 160, 168)
    crownImg.Parent = btnInner

    local crown = WindUI.Creator and WindUI.Creator.Icon and WindUI.Creator.Icon("crown")
    if crown then
        crownImg.Image = crown[1]
        crownImg.ImageRectSize = crown[2].ImageRectSize
        crownImg.ImageRectOffset = crown[2].ImageRectPosition
    else
        crownImg.Image = "rbxassetid://替换成皇冠图标id"
    end

    local btnText = Instance.new("TextLabel")
    btnText.BackgroundTransparency = 1
    btnText.Size = UDim2.new(0, 110, 0, 30)
    btnText.Font = Enum.Font.GothamBold
    btnText.Text = "复制QQ群号"
    btnText.TextColor3 = Color3.fromRGB(20, 20, 25)
    btnText.TextSize = 16
    btnText.Parent = btnInner

    copyBtn.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(qqNumber)
            WindUI:Notify({
                Title = "复制成功",
                Content = "群号已复制：" .. qqNumber,
                Icon = "clipboard",
                Duration = 2,
            })
        else
            warn("当前环境不支持 setclipboard")
        end
    end)
end)

if not okCard then
    warn("[卡片示例] 卡片创建失败:", errCard)
else
    print("[卡片示例] 卡片创建完成")
end

WindUI:Notify({
    Title = "群组卡片示例",
    Content = "卡片已生成，试试复制按钮",
    Icon = "aperture",
    Duration = 4,
})
