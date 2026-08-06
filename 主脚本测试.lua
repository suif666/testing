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

local plrs = game:GetService("Players")
local lp = plrs.LocalPlayer

-- 【视觉体积优化版】全局通知函数
local function notify(title, content, icon, duration)
    local shortText = title
    if content and content ~= "" then
        shortText = title .. " | " .. content
    end

    local ok, err = pcall(function()
        WindUI:Notify({ Title = shortText, Duration = duration or 2, Icon = icon or "bell" })
    end)

    if not ok then
        warn("通知失败:", err)
    end
end

local function run(url, name)
    task.spawn(function()
        local ok, err = pcall(function()
            local source = game:HttpGet(url)
            local fn, compileErr = loadstring(source)
            if not fn then
                error(compileErr)
            end
            fn()
        end)

        if ok then
            notify("执行成功", (name or "脚本") .. " 已运行", "check", 2)
        else
            warn("执行失败: " .. tostring(err))
        end
    end)
end

-- 后台异步加载远程模块：失败自动重试，仍失败时给出可见提示
local function loadRemote(url, desc)
    task.spawn(function()
        local ok, err
        for attempt = 1, 3 do
            ok, err = pcall(function()
                local src = game:HttpGet(url)
                local fn, compileErr = loadstring(src)
                if not fn then
                    error(compileErr)
                end
                fn()
            end)
            if ok then
                return
            end
            task.wait(0.5 * attempt)
        end
        warn((desc or "远程脚本") .. " 加载失败:", err)
        pcall(notify, desc or "远程脚本", "加载失败：" .. tostring(err), "warning", 5)
    end)
end

local function getHum()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- 全局通用防爆杀 (Adonis Bypass)
getgenv().bypass_adonis = true

if not getgenv().SutureHubAntiAFK then
    getgenv().SutureHubAntiAFK = true
    local vu = game:GetService("VirtualUser")
    lp.Idled:Connect(function()
        vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
    notify("防挂机", "正在运行", "info", 2)
end

local uiSet = { Theme = "Dark", Transparent = true, HideSearchBar = false, SideBarWidth = 180 }

local win = WindUI:CreateWindow({
    Title = "Suture Hub", Icon = "aperture", Author = "by suif", Folder = "SutureHub",
    Size = UDim2.fromOffset(620, 460), MinSize = Vector2.new(560, 350), MaxSize = Vector2.new(900, 600),
    ToggleKey = Enum.KeyCode.RightShift, Transparent = uiSet.Transparent, Theme = uiSet.Theme,
    Resizable = true, SideBarWidth = uiSet.SideBarWidth, HideSearchBar = uiSet.HideSearchBar,
    ScrollBarEnabled = true, NewElements = true,
    User = { Enabled = true, Anonymous = false, Callback = function() print("当前用户:", lp.Name) end }
})

win:Tag({ Title = "free", Icon = "gem", Color = Color3.fromHex("#30ff6a"), Radius = 0 })

-- 主窗口可见性广播：子脚本的独立浮层（雷达、Ping/FPS 等）跟随主 UI 一起显示/隐藏
getgenv().SutureMainWindow = win
getgenv().SutureMainUIVisible = true
task.spawn(function()
    while true do
        task.wait(0.15)
        local ok, vis = pcall(function()
            return win.UIElements.Main.Visible
        end)
        getgenv().SutureMainUIVisible = ok and vis or false
    end
end)

--// 【彩虹边框】原版 while 逻辑回归
local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(255, 255, 255)
UIStroke.Thickness = 3
UIStroke.LineJoinMode = Enum.LineJoinMode.Round
UIStroke.Parent = win.UIElements.Main

local UIGradient = Instance.new("UIGradient")
UIGradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
}
UIGradient.Parent = UIStroke

task.spawn(function()
    while true do
        local dt = task.wait()
        UIGradient.Rotation = (UIGradient.Rotation + dt * 200) % 360
    end
end)


local dialog
dialog = win:Dialog({
    Icon = "megaphone", Title = "公告", Content = "觉得脚本好用的话可以分享给好友 如果感觉哪里不好可以点击右上角反馈按钮进行反馈",
    Buttons = {
        {
            Title = "我知晓",
            Callback = function()
                if dialog and dialog.Close then
                    dialog:Close()
                end
            end
        }
    }
})
task.delay(1, function()
    if dialog and dialog.Show then
        dialog:Show()
    end
end)

-- 主页
local mainTab = win:Tab({ Title = "主页", Icon = "house", Locked = false })
mainTab:Select()


-- 功能类
local funcSec = win:Section({ Title = "功能", Icon = "folder", Opened = false })
local playerTab = funcSec:Tab({ Title = "玩家类", Icon = "user", Locked = false })
local FwTab = funcSec:Tab({ Title = "范围类", Icon = "user", Locked = false })
local SfTab = funcSec:Tab({ Title = "甩飞类", Icon = "user", Locked = false })
local fyTab = funcSec:Tab({ Title = "翻译类", Icon = "languages", Locked = false })
local toolTab = funcSec:Tab({ Title = "工具类", Icon = "wrench", Locked = false })
local amTab = funcSec:Tab({ Title = "自瞄类", Icon = "user", Locked = false })

-- 视觉类
local shijueSec = win:Section({ Title = "视觉类", Icon = "palette", Locked = false })
local pingfpsTab = shijueSec:Tab({ Title = "ping/fps显示", Icon = "rss", Locked = false })
local radarTab = shijueSec:Tab({ Title = "雷达", Icon = "radar", Locked = false })
local fovTab = shijueSec:Tab({ Title = "视野", Icon = "palette", Locked = false })

-- 脚本类
local scriptSec = win:Section({ Title = "脚本类", Icon = "folder", Opened = false })
local tyscriptTab = scriptSec:Tab({ Title = "通用", Icon = "shell", Opened = false })
local gnjbTab = scriptSec:Tab({ Title = "国内脚本", Icon = "shell", Opened = false })
local fescriptTab = scriptSec:Tab({ Title = "Fe脚本", Icon = "shell", Opened = false })
local doorsTab = scriptSec:Tab({ Title = "doors/门", Icon = "shell", Locked = false })
local byqTab = scriptSec:Tab({ Title = "被遗弃", Icon = "shell", Locked = false })
local stgTab = scriptSec:Tab({ Title = "死铁轨", Icon = "shell", Locked = false })
local slTab = scriptSec:Tab({ Title = "扫雷", Icon = "shell", Locked = false })
local fkgsTab = scriptSec:Tab({ Title = "方块故事", Icon = "shell", Locked = false })
local zrzhTab = scriptSec:Tab({ Title = "自然灾害", Icon = "shell", Locked = false })
local xesqTab = scriptSec:Tab({ Title = "将会发生些邪恶事情", Icon = "shell", Locked = false })
local wqkTab = scriptSec:Tab({ Title = "武器库", Icon = "shell", Locked = false })
local wxlgTab = scriptSec:Tab({ Title = "无限旅馆", Icon = "shell", Locked = false })
local dwyyTab = scriptSec:Tab({ Title = "动物医院", Icon = "shell", Locked = false })
local pghsTab = scriptSec:Tab({ Title = "排干湖水", Icon = "shell", Locked = false })
local lcTab = scriptSec:Tab({ Title = "莱克星顿与康科德/lc", Icon = "shell", Locked = false })
local zhyfxTab = scriptSec:Tab({ Title = "最后一封信", Icon = "shell", Locked = false })
local sxmsaTab = scriptSec:Tab({ Title = "数学谋杀案", Icon = "shell", Locked = false })
local zbjscqtTab = scriptSec:Tab({ Title = "在北极生存7天", Icon = "shell", Locked = false })
local scjsjjcTab = scriptSec:Tab({ Title = "生存僵尸竞技场", Icon = "shell", Locked = false })
local nzyhhyTab = scriptSec:Tab({ Title = "内脏与黑火药/GB", Icon = "shell", Locked = false })
local nljjcTab = scriptSec:Tab({ Title = "能力竞技场", Icon = "shell", Locked = false })
local bdh2Tab = scriptSec:Tab({ Title = "冰大亨2", Icon = "shell", Locked = false })
local zxdyTab = scriptSec:Tab({ Title = "重型钓鱼", Icon = "shell", Locked = false })

local settingsTab = win:Tab({ Title = "设置", Icon = "sliders-horizontal", Locked = false })



-- WindUI 原生顶栏反馈入口
local FeedbackURL = "https://raw.githubusercontent.com/suif666/suif/refs/heads/main/suif%E8%84%9A%E6%9C%AC%E5%8F%8D%E9%A6%88%E6%B8%A0%E9%81%93.lua"

-- 屏蔽“执行脚本时反馈模块自己弹出的加载通知”
-- 但保留用户真正发送反馈时可能需要的成功/失败提示
local function feedbackNotify(title, content, icon, duration)
    local msg = tostring(title or "") .. " " .. tostring(content or "")

    if msg:find("加载", 1, true)
        or msg:find("初始化", 1, true)
        or msg:find("入口", 1, true)
        or msg:find("已启动", 1, true)
        or msg:find("已就绪", 1, true)
    then
        warn("反馈模块已加载", msg)
        return
    end

    notify(title, content, icon, duration)
end

getgenv().SutureHubFeedback = {
    API = "https://suture-feedback.sfbdsl666.workers.dev/",
    WindUI = WindUI,
    Window = win,
    Notify = feedbackNotify
}

task.spawn(function()
    task.wait(0.5)

    local ok, err = pcall(function()
        local src = game:HttpGet(FeedbackURL)
        local fn, loadErr = loadstring(src)

        if not fn then
            error(loadErr)
        end

        fn()
    end)

    if not ok then
        warn("反馈模块加载失败:", err)
    end
end)



-- 主页

mainTab:Paragraph({
    Title = "小提醒",
    Desc = "脚本右上角可以进行反馈\n脚本名字带有[🔑]则需要卡密 没有就是不需要"
})

mainTab:Paragraph({
    Title = "Suture Hub",
    Desc = "欢迎使用 Suture Hub\n作者：suif\n当前玩家：" .. lp.Name
})

local countText = mainTab:Paragraph({
    Title = "全网执行次数",
    Desc = "正在获取..."
})

local function updateCount()
    local ok, res = pcall(function()
        local player = game.Players.LocalPlayer
        local playerName = player.Name
        local displayName = player.DisplayName
        local userId = tostring(player.UserId)
        local accountAge = tostring(player.AccountAge)
        local maxPlayers = tostring(game.Players.MaxPlayers)

        -- 获取真实游戏名
        local gameName = game.Name
        pcall(function()
            local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
            if info and info.Name then
                gameName = info.Name
            end
        end)

        -- 获取注入器名称
        local executor = "未知"
        pcall(function()
            executor = identifyexecutor() or "未知"
        end)

        local HttpService = game:GetService("HttpService")
        local url = "https://suture-hub-counter.sfbdsl666.workers.dev/count"
            .. "?player="      .. HttpService:UrlEncode(playerName)
            .. "&displayname=" .. HttpService:UrlEncode(displayName)
            .. "&userid="      .. HttpService:UrlEncode(userId)
            .. "&game="        .. HttpService:UrlEncode(gameName)
            .. "&accountage="  .. HttpService:UrlEncode(accountAge)
            .. "&executor="    .. HttpService:UrlEncode(executor)
            .. "&maxplayers="  .. HttpService:UrlEncode(maxPlayers)

        return game:HttpGet(url)
    end)

    if ok then
        res = tostring(res)
        if countText.SetDesc then
            countText:SetDesc("当前全网执行次数：" .. res)
        end
        notify("执行统计", "次数：" .. res, "activity", 2)
    else
        if countText.SetDesc then
            countText:SetDesc("获取失败")
        end
        warn("全网执行次数获取失败:", res)
    end
end

task.spawn(updateCount)

mainTab:Select()

-- 玩家
getgenv().SutureMoveCfg = getgenv().SutureMoveCfg or {}
if getgenv().SutureMoveCfg.WalkSpeed == nil then getgenv().SutureMoveCfg.WalkSpeed = 16 end
if getgenv().SutureMoveCfg.JumpPower == nil then getgenv().SutureMoveCfg.JumpPower = 50 end

local MoveCfg = getgenv().SutureMoveCfg

local function applyMovementToHumanoid(h)
    if not h or not h.Parent then return end

    if h.WalkSpeed ~= MoveCfg.WalkSpeed then
        h.WalkSpeed = MoveCfg.WalkSpeed
    end

    if not h.UseJumpPower then
        h.UseJumpPower = true
    end

    if h.JumpPower ~= MoveCfg.JumpPower then
        h.JumpPower = MoveCfg.JumpPower
    end
end

local function applyMovement()
    local h = getHum()
    if h then
        applyMovementToHumanoid(h)
    end
end

getgenv().SutureMoveToken = (getgenv().SutureMoveToken or 0) + 1
local MoveToken = getgenv().SutureMoveToken

task.spawn(function()
    while getgenv().SutureMoveToken == MoveToken do
        applyMovement()
        task.wait(0.25)
    end
end)

lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        local h = char:WaitForChild("Humanoid", 8)
        if h then
            task.wait(0.2)
            applyMovementToHumanoid(h)
        end
    end)
end)

-- 玩家类 UI（不折叠，全部直接挂在玩家类下）
local moveSec = playerTab
local enhanceSec = playerTab
local physSec = playerTab
local otherSec = playerTab

moveSec:Slider({
    Title = "移动速度",
    Desc = "修改并锁定 WalkSpeed，防止被游戏重置",
    Step = 1,
    Value = { Min = 16, Max = 100, Default = MoveCfg.WalkSpeed or 16 },
    Callback = function(v)
        MoveCfg.WalkSpeed = tonumber(v) or 16
        applyMovement()
    end
})

moveSec:Slider({
    Title = "跳跃高度",
    Desc = "修改并锁定 JumpPower，防止被游戏重置",
    Step = 1,
    Value = { Min = 50, Max = 200, Default = MoveCfg.JumpPower or 50 },
    Callback = function(v)
        MoveCfg.JumpPower = tonumber(v) or 50
        applyMovement()
    end
})

moveSec:Button({
    Title = "恢复默认属性",
    Desc = "恢复默认速度和跳跃，并继续锁定默认值",
    Callback = function()
        MoveCfg.WalkSpeed = 16
        MoveCfg.JumpPower = 50
        applyMovement()
    end
})

-- ============ 玩家增强：无限跳跃 / 穿墙 / 重力 / 旋转 ============
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local defaultPlayerExtra = {
    InfJump = false, Noclip = false,
    Spin = false, SpinSpeed = 180, Gravity = 10, GravityLock = false,
    AirJumps = 0, FakeDown = false, NoFallDamage = false,
}
getgenv().SuturePlayerExtra = getgenv().SuturePlayerExtra or {}
for k, v in pairs(defaultPlayerExtra) do
    if getgenv().SuturePlayerExtra[k] == nil then
        getgenv().SuturePlayerExtra[k] = v
    end
end

local PlayerExtra = getgenv().SuturePlayerExtra

-- 旧版本存的是 196.2 档，转成新的 0~10 档
if (PlayerExtra.Gravity or 10) > 10 then
    PlayerExtra.Gravity = 10
end

-- 无限跳跃：用 JumpRequest 监听（键盘/手机跳跃键都能触发），空中跳直接改垂直速度
local function isGrounded()
    local h = getHum()
    return h ~= nil and h.FloorMaterial ~= Enum.Material.Air
end

local airJumpsUsed = 0
local wasGrounded = true

UIS.JumpRequest:Connect(function()
    local h = getHum()
    local c = lp.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if not h or not root or h.Health <= 0 or h.SeatPart then return end

    local grounded = isGrounded()

    -- 落地时重置空中跳跃计数
    if grounded and not wasGrounded then
        airJumpsUsed = 0
    end
    wasGrounded = grounded

    if grounded then
        h:ChangeState(Enum.HumanoidStateType.Jumping)
        airJumpsUsed = 0
        return
    end

    -- 空中：无限跳跃优先，其次按“空中跳跃次数”限制
    local allow = PlayerExtra.InfJump
        or (PlayerExtra.AirJumps > 0 and airJumpsUsed < PlayerExtra.AirJumps)
    if allow then
        if not PlayerExtra.InfJump then
            airJumpsUsed = airJumpsUsed + 1
        end
        pcall(function()
            local v = root.Velocity
            root.Velocity = Vector3.new(v.X, h.JumpPower, v.Z)
        end)
    end
end)

-- 穿墙：移动时取消碰撞，停止时恢复
local function setCharacterCollide(collide)
    local c = lp.Character
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = collide
            end)
        end
    end
end

RunService.Stepped:Connect(function()
    if not PlayerExtra.Noclip then return end
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not c or not h then return end
    local moving = h.MoveDirection.Magnitude > 0.5
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CanCollide = not moving
            end)
        end
    end
end)

-- 修改重力：持续锁定
local function applyGravity()
    workspace.Gravity = PlayerExtra.Gravity * 19.62
end

task.spawn(function()
    while true do
        if PlayerExtra.GravityLock then
            pcall(applyGravity)
        end
        task.wait(0.5)
    end
end)

-- 人物旋转
RunService.Heartbeat:Connect(function(step)
    if PlayerExtra.Spin then
        local c = lp.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(PlayerExtra.SpinSpeed) * step, 0)
        end
    end
end)

-- 伪装倒地（布娃娃）：取消四肢物理瘫倒，恢复时还原位置
local FakeDownSaved = {}

local function applyFakeDown(on)
    local char = lp.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    if on then
        FakeDownSaved = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(FakeDownSaved, { Part = part, Anchored = part.Anchored, CFrame = part.CFrame })
            end
        end
        for _, d in ipairs(FakeDownSaved) do
            if d.Part ~= root then
                d.Part.Anchored = false
            end
        end
        root.Anchored = true
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    else
        for _, d in ipairs(FakeDownSaved) do
            pcall(function()
                d.Part.Anchored = d.Anchored
                d.Part.CFrame = d.CFrame
            end)
        end
        FakeDownSaved = {}
        root.Anchored = false
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
end

-- 无伤坠落：隐形保护罩，免疫坠落伤害
local function applyNoFallDamage(on)
    local char = lp.Character
    if not char then return end
    if on then
        if not char:FindFirstChildOfClass("ForceField") then
            local ff = Instance.new("ForceField")
            ff.Visible = false
            ff.Parent = char
        end
    else
        for _, ff in ipairs(char:GetDescendants()) do
            if ff:IsA("ForceField") and not ff.Visible then
                pcall(function()
                    ff:Destroy()
                end)
            end
        end
    end
end

-- 角色重生后自动补上开启中的伪装倒地 / 无伤坠落
lp.CharacterAdded:Connect(function(char)
    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 8)
        if hum then
            task.wait(0.2)
            if PlayerExtra.FakeDown then
                applyFakeDown(true)
            end
            if PlayerExtra.NoFallDamage then
                applyNoFallDamage(true)
            end
        end
    end)
end)

enhanceSec:Toggle({
    Title = "无限跳跃",
    Desc = "在空中可以连续跳跃，键盘和手机跳跃键都有效",
    Type = "Checkbox",
    Value = PlayerExtra.InfJump or false,
    Callback = function(s)
        PlayerExtra.InfJump = s
    end
})

enhanceSec:Toggle({
    Title = "穿墙（Noclip）",
    Desc = "移动时无视碰撞，停止移动恢复碰撞，关闭后全部恢复",
    Type = "Checkbox",
    Value = PlayerExtra.Noclip or false,
    Callback = function(s)
        PlayerExtra.Noclip = s
        if not s then
            setCharacterCollide(true)
        end
    end
})

enhanceSec:Slider({
    Title = "空中跳跃次数",
    Desc = "0 = 关闭；空中可额外跳跃的次数（无限跳跃开启时优先，不受此限制）",
    Step = 1,
    Value = { Min = 0, Max = 20, Default = PlayerExtra.AirJumps or 0 },
    Callback = function(v)
        PlayerExtra.AirJumps = tonumber(v) or 0
        airJumpsUsed = 0
    end
})

physSec:Slider({
    Title = "修改重力",
    Desc = "0 = 无重力，10 = 正常重力(196.2)，中间按比例，移动滑块后持续锁定",
    Step = 1,
    Value = { Min = 0, Max = 10, Default = PlayerExtra.Gravity or 10 },
    Callback = function(v)
        PlayerExtra.Gravity = tonumber(v) or 10
        PlayerExtra.GravityLock = true
        pcall(applyGravity)
    end
})

physSec:Button({
    Title = "恢复默认重力",
    Desc = "停止锁定并恢复正常重力",
    Callback = function()
        PlayerExtra.GravityLock = false
        PlayerExtra.Gravity = 10
        workspace.Gravity = 196.2
    end
})

physSec:Slider({
    Title = "旋转速度",
    Desc = "数值越高转得越快",
    Step = 1,
    Value = { Min = 0, Max = 720, Default = PlayerExtra.SpinSpeed or 180 },
    Callback = function(v)
        PlayerExtra.SpinSpeed = tonumber(v) or 180
    end
})

physSec:Toggle({
    Title = "人物旋转",
    Desc = "开启后角色持续旋转",
    Type = "Checkbox",
    Value = PlayerExtra.Spin or false,
    Callback = function(s)
        PlayerExtra.Spin = s
        local h = getHum()
        if h then
            h.AutoRotate = not s
        end
    end
})

otherSec:Toggle({
    Title = "伪装倒地",
    Desc = "布娃娃状态，四肢瘫倒，关闭后还原",
    Type = "Checkbox",
    Value = PlayerExtra.FakeDown or false,
    Callback = function(s)
        PlayerExtra.FakeDown = s
        applyFakeDown(s)
    end
})

otherSec:Toggle({
    Title = "无伤坠落",
    Desc = "隐形保护罩，免疫坠落伤害（同时也会免疫其他伤害）",
    Type = "Checkbox",
    Value = PlayerExtra.NoFallDamage or false,
    Callback = function(s)
        PlayerExtra.NoFallDamage = s
        applyNoFallDamage(s)
    end
})

otherSec:Button({
    Title = "重置角色",
    Desc = "让自己的角色重生",
    Callback = function()
        local h = getHum()
        if h then
            h.Health = 0
        end
    end
})

fyTab:Paragraph({
    Title = "注意",
    Desc = "先用别人写好的 等我用空了在自己写一个"
})

fyTab:Space()

fyTab:Button({
    Title = "devastate翻译", Desc = "字面意思", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/dream6-e/rbx/refs/heads/main/%E7%BF%BB%E8%AF%91%E8%84%9A%E6%9C%AC.lua", "devastate翻译")
    end
})

-- 视觉

-- ============ 视野（FOV） ============
local fovConn = nil
pcall(function()
    fovTab:Slider({
        Title = "视野角度",
        Desc = "70 = 默认，120 = 广角，会持续锁定防止被游戏重置",
        Step = 1,
        Value = { Min = 70, Max = 120, Default = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70 },
        Callback = function(v)
            local fov = tonumber(v) or 70
            if fovConn then
                fovConn:Disconnect()
                fovConn = nil
            end
            fovConn = RunService.RenderStepped:Connect(function()
                local cam = workspace.CurrentCamera
                if cam and cam.FieldOfView ~= fov then
                    cam.FieldOfView = fov
                end
            end)
        end
    })
end)

-- ============ 自瞄（通用相机自瞄） ============
local aimbotOk, aimbotErr = pcall(function()
local defaultAimbot = {
    Enabled = false, ShowFov = true, Fov = 200, MaxDistance = 1000,
    Part = "Head", TeamCheck = false, WallCheck = false,
    Smooth = 0.8, Prediction = 0.1, Trigger = "按住右键",
}
getgenv().SutureAimbot = getgenv().SutureAimbot or {}
for k, v in pairs(defaultAimbot) do
    if getgenv().SutureAimbot[k] == nil then
        getgenv().SutureAimbot[k] = v
    end
end

local Aimbot = getgenv().SutureAimbot

-- FOV 圈：UI 版圆环（参考夜脚本源：UIStroke + UICorner），不依赖注入器的 Drawing 库
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "AimbotFOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
do
    local ok, p = pcall(gethui)
    fovGui.Parent = ok and p or game:GetService("CoreGui")
end

local fovRing = Instance.new("Frame")
fovRing.Name = "Ring"
fovRing.AnchorPoint = Vector2.new(0.5, 0.5)
fovRing.Position = UDim2.new(0.5, 0, 0.5, 0)
fovRing.Size = UDim2.fromOffset(200, 200)
fovRing.BackgroundTransparency = 1
fovRing.Visible = false
fovRing.Parent = fovGui
Instance.new("UICorner", fovRing).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 2
fovStroke.Color = Color3.fromRGB(255, 255, 255)
fovStroke.Parent = fovRing

local function getAimPart(character)
    if not character then return nil end
    if Aimbot.Part == "随机" then
        local list = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }
        return character:FindFirstChild(list[math.random(1, #list)])
    end
    return character:FindFirstChild(Aimbot.Part)
end

local function aimTriggerActive()
    if Aimbot.Trigger == "一直瞄准" then return true end
    if Aimbot.Trigger == "按住右键" then
        local ok, v = pcall(function()
            return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end)
        return ok and v
    end
    if Aimbot.Trigger == "按住F" then return UIS:IsKeyDown(Enum.KeyCode.F) end
    return false
end

local function getAimTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local center = cam.ViewportSize / 2
    local best, bestDist = nil, Aimbot.Fov
    local myChar = lp.Character

    for _, p in ipairs(plrs:GetPlayers()) do
        if p == lp then continue end
        local char = p.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if Aimbot.TeamCheck and p.Team and lp.Team and p.Team == lp.Team then continue end

        local part = getAimPart(char)
        if not part then continue end

        local pos, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if screenDist > Aimbot.Fov then continue end

        if (cam.CFrame.Position - part.Position).Magnitude > Aimbot.MaxDistance then continue end

        if Aimbot.WallCheck then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { myChar, char }
            local ray = workspace:Raycast(
                cam.CFrame.Position,
                (part.Position - cam.CFrame.Position).Unit * Aimbot.MaxDistance,
                params
            )
            if ray and ray.Instance then continue end
        end

        if screenDist < bestDist then
            bestDist = screenDist
            best = { Character = char, Part = part }
        end
    end

    return best
end

local function aimbotLoop()
    local cam = workspace.CurrentCamera
    if not cam then return end

    -- FOV 圈：只跟“显示FOV圈”开关绑定，不依赖自瞄总开关
    if Aimbot.ShowFov then
        pcall(function()
            fovRing.Visible = true
            fovRing.Size = UDim2.fromOffset(Aimbot.Fov * 2, Aimbot.Fov * 2)
            fovRing.Position = UDim2.new(0.5, 0, 0.5, 0)
        end)
    elseif fovRing.Visible then
        fovRing.Visible = false
    end

    if not Aimbot.Enabled or not aimTriggerActive() then return end

    local target = getAimTarget()
    if target and target.Part then
        local targetPos = target.Part.Position
        if Aimbot.Prediction > 0 then
            targetPos = targetPos + target.Part.AssemblyLinearVelocity * Aimbot.Prediction
        end
        cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, targetPos), Aimbot.Smooth)
    end
end

RunService.RenderStepped:Connect(aimbotLoop)

local aimUi = amTab
if not aimUi then
    error("[自瞄] 自瞄标签页没有创建成功")
end

aimUi:Toggle({
    Title = "自瞄开关",
    Desc = "总开关，配合下面的触发方式使用",
    Type = "Checkbox",
    Value = Aimbot.Enabled,
    Callback = function(s)
        Aimbot.Enabled = s
    end
})

aimUi:Toggle({
    Title = "显示FOV圈",
    Desc = "屏幕中心显示瞄准范围圈",
    Type = "Checkbox",
    Value = Aimbot.ShowFov,
    Callback = function(s)
        Aimbot.ShowFov = s
        if not s and fovRing then
            fovRing.Visible = false
        end
    end
})

aimUi:Slider({
    Title = "FOV范围",
    Desc = "屏幕中心多大范围内会锁定目标",
    Step = 10,
    Value = { Min = 10, Max = 700, Default = Aimbot.Fov },
    Callback = function(v)
        Aimbot.Fov = tonumber(v) or 200
    end
})

aimUi:Slider({
    Title = "最大距离",
    Desc = "超过该距离不锁定（米）",
    Step = 50,
    Value = { Min = 50, Max = 6000, Default = Aimbot.MaxDistance },
    Callback = function(v)
        Aimbot.MaxDistance = tonumber(v) or 1000
    end
})

aimUi:Dropdown({
    Title = "瞄准部位",
    Values = { "Head", "HumanoidRootPart", "随机" },
    Value = Aimbot.Part,
    Callback = function(v)
        Aimbot.Part = v
    end
})

aimUi:Dropdown({
    Title = "触发方式",
    Values = { "一直瞄准", "按住右键", "按住F" },
    Value = Aimbot.Trigger,
    Callback = function(v)
        Aimbot.Trigger = v
    end
})

aimUi:Toggle({
    Title = "队伍检测",
    Desc = "开启后跳过同队玩家",
    Type = "Checkbox",
    Value = Aimbot.TeamCheck,
    Callback = function(s)
        Aimbot.TeamCheck = s
    end
})

aimUi:Toggle({
    Title = "穿墙自瞄",
    Desc = "开启后有墙挡住就不会锁定",
    Type = "Checkbox",
    Value = Aimbot.WallCheck,
    Callback = function(s)
        Aimbot.WallCheck = s
    end
})

aimUi:Slider({
    Title = "平滑度",
    Desc = "越低越平滑，1 = 瞬间转向",
    Step = 0.05,
    Value = { Min = 0.1, Max = 1, Default = Aimbot.Smooth },
    Callback = function(v)
        Aimbot.Smooth = tonumber(v) or 0.8
    end
})

aimUi:Slider({
    Title = "预判(秒)",
    Desc = "0 = 关闭；预测移动目标的位置（参考 Xa 的预判）",
    Step = 0.05,
    Value = { Min = 0, Max = 1, Default = Aimbot.Prediction },
    Callback = function(v)
        Aimbot.Prediction = tonumber(v) or 0.1
    end
})

end)
if not aimbotOk then
    warn("[自瞄] 自瞄模块加载失败:", aimbotErr)
end

-- 即时互动（极简版，几乎不掉帧）
getgenv().SutureHubPromptHoldCache = getgenv().SutureHubPromptHoldCache or setmetatable({}, { __mode = "k" })
local PromptHoldCache = getgenv().SutureHubPromptHoldCache

for prompt, oldHold in pairs(PromptHoldCache) do
    if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") and oldHold ~= nil then
        pcall(function() prompt.HoldDuration = oldHold end)
    end
    PromptHoldCache[prompt] = nil
end

getgenv().InstantInteract = false

local PromptConn

-- 断开上次执行遗留的连接
if getgenv().SuturePromptAddedConn then
    pcall(function() getgenv().SuturePromptAddedConn:Disconnect() end)
    getgenv().SuturePromptAddedConn = nil
end

local function setInstantPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if PromptHoldCache[prompt] == nil then
        PromptHoldCache[prompt] = prompt.HoldDuration
    end
    if prompt.HoldDuration ~= 0 then
        prompt.HoldDuration = 0
    end
end

local function restoreAllPrompts()
    for prompt, oldHold in pairs(PromptHoldCache) do
        if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") then
            pcall(function() prompt.HoldDuration = oldHold end)
        end
        PromptHoldCache[prompt] = nil
    end
end

local function setPromptListener(enable)
    if enable then
        if not PromptConn then
            PromptConn = workspace.DescendantAdded:Connect(function(v)
                if v:IsA("ProximityPrompt") then
                    setInstantPrompt(v)
                end
            end)
            getgenv().SuturePromptAddedConn = PromptConn
        end
    elseif PromptConn then
        pcall(function() PromptConn:Disconnect() end)
        PromptConn = nil
        getgenv().SuturePromptAddedConn = nil
    end
end

toolTab:Toggle({
    Title = "即时互动",
    Desc = "关闭恢复初始数值，但可能需要玩家死亡一次或互动按钮刷新一次",
    Icon = "zap",
    Type = "Checkbox",
    Value = false,
    Callback = function(s)
        getgenv().InstantInteract = s
        if s then
            setPromptListener(true)
            for _, v in ipairs(workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    setInstantPrompt(v)
                end
            end
        else
            setPromptListener(false)
            restoreAllPrompts()
        end
    end
})


toolTab:Button({
    Title = "Gui文本获取v24", Desc = "自制 ai神力 感谢李藝州🙏🙏🙏", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/UI%E6%8F%90%E5%8F%96_v24_%E4%BF%AE%E5%A4%8D%E7%89%88.lua", "Gui文本获取v24") end
})

toolTab:Button({
    Title = "dex汉化", Desc = "顾名思义", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/dex.lua", "dex汉化") end
})

toolTab:Button({
    Title = "iy汉化", Desc = "顾名思义", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/config/iy%E6%B1%89%E5%8C%96%E7%89%88", "iy汉化") end
})



-- 脚本区域
doorsTab:Button({
    Title = "全自动刷旋钮", Desc = "字面意思 执行后什么都不用管了", Icon = "shell",
    Callback = function()
        getgenv().Config = { MinContainers = 10, MinCoins = 50, UseLockpick = false, UseRobuxKnobsBoost = false }
        run("https://api.luarmor.net/files/v4/loaders/6e87698669de88a8f81d6348ce368b73.lua", "Doors 脚本")
    end
})

doorsTab:Button({
    Title = "半自动刷旋钮",
    Desc = "字面意思 大厅执行后进游戏里收集金币就可以了",
    Icon = "shell",
    Callback = function()
        getgenv().Config = { MinContainers = 10, MinCoins = 50, UseLockpick = false, UseRobuxKnobsBoost = false }
        run("https://api.jnkie.com/api//luascripts/public/5d2e14fd21f767f03b28cfb5537f6260a6f45279ddeb806fd04e706153ed0ce0/download", "Doors 脚本")
    end
})

doorsTab:Button({
    Title = "[🔑]mspaint",
    Desc = "需卡密 超好用",
    Icon = "shell",
    Callback = function()
        local link = "https://www.mspaint.cc/key"
        if setclipboard then
            setclipboard(link)
        else
            warn("复制失败：当前环境不支持复制链接")
        end
        run("https://api.luarmor.net/files/v3/loaders/002c19202c9946e6047b0c6e0ad51f84.lua", "Doors msp")
    end
})

byqTab:Button({
    Title = "fart[suif汉化]", Desc = "个人感觉很好用", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/fa%E6%B1%89%E5%8C%96", "被遗弃脚本") end
})

byqTab:Button({
    Title = "jnkie", Desc = "依旧国外大手子制作", Icon = "shell",
    Callback = function() run("https://api.jnkie.com/api/v1/luascripts/public/d36d2b96db2abcbb0f20b5c556b53cc5260ff74db0f8bfc3bea83eaa1da7947f/download", "被遗弃脚本02") 
end
})

stgTab:Button({
    Title = "[🔑]叶子", Desc = "好长时间都没有更新了...", Icon = "shell",
    Callback = function() run("https://getnative.cc/script/loader", "死铁轨叶子") end
})

stgTab:Button({
    Title = "ringta[suif汉化]", Desc = "应该是最好用", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/Ringta%E6%AD%BB%E9%93%81%E8%BD%A8.lua", "死铁轨ringta") end
})

stgTab:Button({
    Title = "Alkaline[suif汉化]", Desc = "对ringta拙劣的模仿 但还是有自己的功能的", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E6%AD%BB%E9%93%81%E8%BD%A8alkaline", "死铁轨Alkaline") end
})

stgTab:Button({
    Title = "死铁轨刷债券", Desc = "速度也是非常快好吧 蜗牛在修复司马😡😡😡", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/afkar-gg/sc/refs/heads/main/auto-bond", "死铁轨刷债券") end
})

slTab:Button({
    Title = "扫雷", Desc = "支持服务器bLockerman's Minesweeper", Icon = "shell",
    Callback = function() run("https://project-xiaeo.vercel.app/api/v1/luascripts/public/3d7d1c298ca6ff866ccb419f77d6b97d9e22c6be0d239b80d46d753f539d31e8/download", "扫雷") end
})

slTab:Button({
    Title = "扫雷02", Desc = "支持服务器bLockerman's Minesweeper", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/timmytim12354-png/simplescriptz/refs/heads/main/loader.lua?='", "扫雷") end
})

fkgsTab:Button({
    Title = "方块故事[suif汉化]", Desc = "支持方块故事战斗模拟器", Icon = "shell",
    Callback = function() run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E6%96%B9%E5%9D%97%E6%95%85%E4%BA%8B%E6%B1%89%E5%8C%96.lua", "方块故事") end
})

zrzhTab:Button({
    Title = "自然灾害 龙卷风", Desc = "大风车呀滴溜溜的转...", Icon = "shell",
    Callback = function() run("https://pastebin.com/raw/JR7RBh2a", "自然灾害") end
})

xesqTab:Button({
    Title = "将会发生些邪恶事情", Desc = "没有Gui 点击即执行 无限体力", Icon = "shell",
    Callback = function() run("https://rawscripts.net/raw/UPD-something-evil-will-happen-Inf-stamina-57438", "邪恶事情") end
})

wqkTab:Button({
    Title = "武器库 静默瞄准", Desc = "没有esp 但是有静默瞄准", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/FakeAngles/PasteWare-v2/refs/heads/main/PasteWare.lua", "武器库")
    end
})

getgenv().Tabs = getgenv().Tabs or {}
getgenv().Tabs.wxlgTab = wxlgTab

run("https://pastebin.com/raw/wV07BGnS")

fescriptTab:Button({
    Title = "fe无敌少侠", Desc = "他人可见", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/giobolqvi1/universal-conquest-fly-by-GioBolqv1/refs/heads/main/lonely.lua", "无敌少侠")
    end
})

fescriptTab:Button({
    Title = "fe祖国人[suif汉化]", Desc = "晚安,阿祖", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E7%A5%96%E5%9B%BD%E4%BA%BA%E6%B1%89%E5%8C%96.lua", "祖国人")
    end
})

fescriptTab:Button({
    Title = "fe火车头[suif汉化]", Desc = "情侣拆散器", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E7%81%B3%E8%BD%A4%E6%B1%89%E5%8C%96.lua", "火车头")
    end
})

fescriptTab:Button({
    Title = "fe死亡[suif汉化]", Desc = "他人可见 优质的动作脚本", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/uhhhhhh.lua", "uhhhh")
    end
})

fescriptTab:Button({
    Title = "凋零风暴fe", Desc = "他人不可见 优质的fe脚本 建议在自然灾害执行", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/ian49972/SCRIPTS/refs/heads/main/Wither", "凋零风暴")
    end
})


tyscriptTab:Button({
    Title = "飞行V3", Desc = "顾名思义", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/FlyGuiV3.lua", "飞行V3")
    end
})

tyscriptTab:Button({
    Title = "npc控制[suif汉化]", Desc = "可以控制npc", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/npc%E6%B1%89%E5%8C%96.lua", "npc控制")
    end
})

dwyyTab:Button({
    Title = "[🔑]动物医院 自动类01[suif汉化]", Desc = "有些事件需要手动去完成 另外我用这个只活到15天", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/HBtj3VFu", "动物医院")
    end
})

dwyyTab:Button({
    Title = "[🔑]动物医院 自动类02[suif汉化]", Desc = "有些事件需要手动去完成 没测试最高多少天", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/pFzZvHum", "动物医院02")
    end
})

dwyyTab:Button({
    Title = "[🔑]动物医院 自动类03[suif汉化]", Desc = "高度自定义 至少ui挺好看 不好用", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E5%8A%A8%E7%89%A9%E5%8C%BB%E9%99%A2%20%E5%8A%9F%E8%83%BD%E4%B8%B0%E5%AF%8F.lua", "动物医院03")
    end
})

dwyyTab:Button({
    Title = "动物医院 自动类04[suif汉化]", Desc = "美丽ui 挺好用 就是容易治死人导致游戏结束 等作者优化吧 启动时会有雷霆大叫[调低音量]", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E5%8A%A8%E7%89%A9%E5%8C%BB%E9%99%A2Foxname%5Bsuifhanghang%5D.lua", "动物医院04")
    end
})

pghsTab:Button({
    Title = "排干湖水 自动类01[suif汉化]", Desc = "离售卖机远了没法自动售卖  15分钟左右通关", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/heads/main/%E6%8E%92%E7%A9%BA%E6%B9%96%E6%B0%B4.lua", "排干湖水01")
    end
})

lcTab:Button({
    Title = "lc脚本01", Desc = "", Icon = "shell",
    Callback = function()
        local link = "heiqiang-fa84d1b1-141d-46ad-991a-73b65016038c"
        if setclipboard then
            setclipboard(link)
            notify("复制成功", "卡密已复制到剪贴板！", "clipboard", 2)
        end
        run("https://api.jnkie.com/api/v1/luascripts/public/6bd5c94e9da68dce4a2bdf5abd1f6fb9a1379f41faaadbc0354b98d543066f58/download", "lc莱克星顿与康科德")
    end
})

zhyfxTab:Button({
    Title = "最后一封信 自动类01[suif汉化]", Desc = "有些词脚本想不出来 还是人脑牛逼👍🏻👍🏻👍🏻", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E5%86%99%E4%B8%80%E5%B0%81%E4%BF%A1%5B%E6%B1%89%E5%8C%96%5D.lua", "最后一封信01")
    end
})

sxmsaTab:Button({
    Title = "数学谋杀案 自动类01[suif汉化]", Desc = "这游戏有什么好开的。。", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E6%95%B0%E5%AD%A6%E8%B0%8B%E6%9D%80%E6%A1%88%5B%E6%B1%89%E5%8C%96%5D.lua", "数学谋杀案01")
    end
})

zbjscqtTab:Button({
    Title = "[🔑]在北极生存7天 自动类01[suif汉化]", Desc = "加载时间可能比较长 不好用", Icon = "shell",
    Callback = function()
        local link = "https://wayoutscript.netlify.app/getkey"
        if setclipboard then
            setclipboard(link)
            notify("复制成功", "解卡链接已复制到剪贴板！", "clipboard", 2)
        end
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E5%9C%A8%E5%8C%97%E6%9E%81%E7%94%9F%E5%AD%987%E5%A4%A9.lua", "在北极生存7天01")
    end
})



fescriptTab:Button({
    Title = "r15动作包[suif汉化]", Desc = "他人可见 注意只支持r15 r6用了会直接僵直", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/r15%E5%8A%A8%E4%BD%9C%E5%8C%85fe", "r15动作包")
    end
})

scjsjjcTab:Button({
    Title = "生存僵尸竞技场01[suif汉化]", Desc = "汉化不全 但无关紧要 主要的功能都是汉化过的 感觉还行", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/r15%E5%8A%A8%E4%BD%9C%E5%8C%85fe", "生存僵尸竞技场01")
    end
})

fescriptTab:Button({
    Title = "我的世界fe", Desc = "他人不可见 米米世界牛逼。", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/ian49972/SCRIPTS/refs/heads/main/Steve", "我的世界fe")
    end
})

tyscriptTab:Button({
    Title = "定位传送", Desc = "借鉴[夜脚本]的闪电尖兵大招", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/Ctx5L33c", "定位传送")
    end
})

fescriptTab:Button({
    Title = "召唤吉吉fe", Desc = "他人不可见 嗯对没有蛋仔。", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/fqm5dDXN", "召唤吉吉fe")
    end
})


gnjbTab:Paragraph({
    Title = "注意",
    Desc = "我只收录我QQ群里看得见的脚本 不论好坏 如果你不想让你的脚本出现在这里 可以点击右上角反馈按钮进行反馈"
})

gnjbTab:Space()

gnjbTab:Button({
    Title = "夜脚本", Desc = "国内脚本 群[711757444]", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/ylt410/roblox-Script/refs/heads/main/yejiaoben", "夜脚本")
    end
})

gnjbTab:Button({
    Title = "霖溺脚本", Desc = "国内脚本 群[744830231] 需加入roblox指定社区", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/ShenJiaoBen/ScriptLoader/refs/heads/main/Linni_FreeLoader.lua", "霖溺")
    end
})

gnjbTab:Button({
    Title = "XA脚本", Desc = "国内脚本 群[1057545155] 可能有时执行不了", Icon = "shell",
    Callback = function()
        run("https://raw.gitcode.com/Xingtaiduan/Scripts/raw/main/Loader.lua", "XA脚本")
    end
})

gnjbTab:Button({
    Title = "黑白脚本", Desc = "国内脚本 群[1062578052]", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/tfcygvunbind/Apple/main/%E9%BB%91%E7%99%BD%E8%84%9A%E6%9C%AC%E5%8A%A0%E8%BD%BD%E5%99%A8", "黑白脚本")
    end
})

gnjbTab:Button({
    Title = "kunkun脚本", Desc = "国内脚本 群[1009291930]", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/cfCbSrqr", "kunkun脚本")
    end
})

gnjbTab:Button({
    Title = "TrashHub脚本", Desc = "国内脚本 群[786284990]", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/WasKKal/OnlyJumpToOther/main/loader.lua", "TrashHub脚本")
    end
})

gnjbTab:Button({
    Title = "Rb脚本", Desc = "国内脚本 群[1018099361]", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/Yungengxin/roblox/refs/heads/main/Rb-Hub", "Rb脚本")
    end
})

--范围远程
getgenv().Tabs.RangeTab = FwTab          -- 这里换成你实际创建的 Tab 变量名

loadRemote("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E8%8C%83%E5%9B%B4.lua?t=" .. tostring(tick()), "范围")

--甩飞远程
getgenv().Tabs.FlingTPTab = SfTab
getgenv().WindUI = WindUI

loadRemote("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E7%94%A9%E9%A3%9E?t=" .. tostring(tick()), "甩飞")

--ping fps显示
getgenv().Tabs.PingFPSTab = pingfpsTab
getgenv().SuturePingFPSTab = pingfpsTab

loadRemote("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E6%98%BE%E7%A4%BAfps%E5%92%8Cping.lua?t=" .. tostring(tick()), "ping/fps显示")

--雷达
getgenv().Tabs.RadarTab = radarTab
getgenv().SutureRadarTab = radarTab

loadRemote("https://raw.githubusercontent.com/suif666/testing/refs/heads/main/%E9%9B%B7%E8%BE%BE%E7%A4%BA%E4%BE%8B.lua?t=" .. tostring(tick()), "雷达")

tyscriptTab:Button({
    Title = "绕过群组检测", Desc = "可以绕过部分脚本的群组检测", Icon = "shell",
    Callback = function()
        run("https://pastebin.com/raw/4LzyCSnp", "已成功绕过群组检测")
    end
})

nzyhhyTab:Button({
    Title = "内脏与黑火药Skin4.1", Desc = "国内脚本 群[1079452161] 搜不到就是禁止加入了", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/wzhxll/Invincible-Willow-Leaf/refs/heads/main/Skin%20HUB%204.1.lua", "内脏与黑火药Skin")
    end
})

zrzhTab:Button({
    Title = "未锚定部件吸附", Desc = "花样龙卷风 还可以嫁祸别人 嗯对反正我用不明白", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E8%87%AA%E7%84%B6%E7%81%BE%E5%AE%B3%E9%BB%91%E6%B4%9E.lua", "未锚定部件吸附")
    end
})

nljjcTab:Button({
    Title = "[🔑]能力竞技场", Desc = "外网很多人在用 就搬过来了 不适合演戏 不适合手机游玩 功能挺多", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E8%83%BD%E5%8A%9B%E7%AB%9E%E6%8A%80%E5%9C%BA.lua", "能力竞技场")
    end
})

bdh2Tab:Paragraph({
    Title = "注意",
    Desc = "这个神人服务器长期霸占我主页 不找脚本有点过不去了"
})

bdh2Tab:Space()

bdh2Tab:Button({
    Title = "[🔑]冰大亨2[自动化]", Desc = "功能很多 自动化功能全开之后就可以睡觉了😛😛😛", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E5%86%B0%E5%A4%A7%E4%BA%A82.lua", "冰大亨2")
    end
})

zxdyTab:Button({
    Title = "[🔑]重型钓鱼", Desc = "感觉中规中矩 要是觉得不好用再右上角反馈功能进行反馈", Icon = "shell",
    Callback = function()
        run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E9%87%8D%E5%9E%8B%E9%92%93%E9%B1%BC.lua", "重型钓鱼")
    end
})


-- UI设置
local themeMap = {
    ["深色"]="Dark", ["浅色"]="Light", ["玫瑰"]="Rose", ["植物"]="Plant", ["红色"]="Red",
    ["靛蓝"]="Indigo", ["天空蓝"]="Sky", ["紫罗兰"]="Violet", ["琥珀"]="Amber"
}
settingsTab:Dropdown({
    Title = "UI 主题", Desc = "切换 UI 主题",
    Values = { "深色","浅色","玫瑰","植物","红色","靛蓝","天空蓝","紫罗兰","琥珀" },
    Value = "深色",
    Callback = function(name)
        local real = themeMap[name]
        uiSet.Theme = real
        if WindUI.SetTheme then WindUI:SetTheme(real) elseif win.SetTheme then win:SetTheme(real) end
    end
})

WindUI:Notify({
    Title = "Suture Hub",
    Content = "成功加载全部功能！",
    Icon = "aperture",
    Duration = 3
})

WindUI:Notify({
    Title = "小提示",
    Content = "遇到什么问题\n没有自己想玩的服务器\n脚本没法执行\n可以点右上角的反馈按钮进行反馈",
    Icon = "message-square-warning",
    Duration = 10
})
