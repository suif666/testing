-- WindUI 雷达（兼容 Delta）
-- 功能：四角位置切换（下拉框）、圆角程度（滑块）、敌人/队友/好友/中立显示开关
print("[雷达] 开始执行")

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
print("[雷达] WindUI 加载完成")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local RADAR_SIZE = 200          -- 雷达边长（像素）
local RADAR_RANGE = 200         -- 探测范围（studs），想改远改这里
local BLIP_SIZE = 6             -- 亮点大小
local BLIP_COUNT = 40           -- 最多显示多少个亮点

local Settings = {
    Enabled = true,
    Position = "右上",
    Corner = 50,                -- 圆角程度 0~100，100 = 正圆
    ShowEnemy = true,
    ShowTeam = true,
    ShowFriend = true,
    ShowNeutral = true,
}

local CAT_COLORS = {
    enemy = Color3.fromRGB(255, 70, 70),
    team = Color3.fromRGB(70, 200, 90),
    friend = Color3.fromRGB(255, 200, 60),
    neutral = Color3.fromRGB(180, 180, 190),
}

-- ============ 雷达父级：优先 gethui()（Delta 兼容） ============
local RadarParent
do
    local ok, p = pcall(gethui)
    if ok and p then
        RadarParent = p
    end
    if not RadarParent then
        local ok2, c = pcall(function()
            return game:GetService("CoreGui")
        end)
        if ok2 then
            RadarParent = c
        end
    end
    if not RadarParent then
        RadarParent = lp:WaitForChild("PlayerGui")
    end
end

local radarGui = Instance.new("ScreenGui")
radarGui.Name = "RadarOverlay"
radarGui.IgnoreGuiInset = true
radarGui.ResetOnSpawn = false
radarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
radarGui.Parent = RadarParent

local protect = protectgui or (syn and syn.protect_gui)
if protect then
    pcall(protect, radarGui)
end

local okOverlay, errOverlay = pcall(function()
    -- ============ 雷达底板 ============
    local radarFrame = Instance.new("Frame")
    radarFrame.Name = "Radar"
    radarFrame.Size = UDim2.fromOffset(RADAR_SIZE, RADAR_SIZE)
    radarFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    radarFrame.BackgroundTransparency = 0.25
    radarFrame.ClipsDescendants = true
    radarFrame.ZIndex = 4
    radarFrame.Parent = radarGui

    local corner = Instance.new("UICorner")
    corner.Parent = radarFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 200, 255)
    stroke.Thickness = 2
    stroke.Parent = radarFrame

    -- 十字参考线
    local crossH = Instance.new("Frame")
    crossH.Size = UDim2.new(1, 0, 0, 1)
    crossH.Position = UDim2.new(0, 0, 0.5, 0)
    crossH.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    crossH.BackgroundTransparency = 0.7
    crossH.ZIndex = 4
    crossH.Parent = radarFrame

    local crossV = Instance.new("Frame")
    crossV.Size = UDim2.new(0, 1, 1, 0)
    crossV.Position = UDim2.new(0.5, 0, 0, 0)
    crossV.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    crossV.BackgroundTransparency = 0.7
    crossV.ZIndex = 4
    crossV.Parent = radarFrame

    -- 自己（中心白点）
    local centerDot = Instance.new("Frame")
    centerDot.Size = UDim2.fromOffset(8, 8)
    centerDot.Position = UDim2.new(0.5, -4, 0.5, -4)
    centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    centerDot.ZIndex = 6
    centerDot.Parent = radarFrame
    Instance.new("UICorner", centerDot).CornerRadius = UDim.new(1, 0)

    -- 亮点池
    local blips = {}
    for i = 1, BLIP_COUNT do
        local b = Instance.new("Frame")
        b.Size = UDim2.fromOffset(BLIP_SIZE, BLIP_SIZE)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Visible = false
        b.ZIndex = 5
        b.Parent = radarFrame
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        table.insert(blips, b)
    end

    -- ============ 位置 / 圆角 ============
    local PositionMap = {
        ["左上"] = { AnchorPoint = Vector2.new(0, 0), Pos = UDim2.new(0, 12, 0, 12) },
        ["右上"] = { AnchorPoint = Vector2.new(1, 0), Pos = UDim2.new(1, -12, 0, 12) },
        ["左下"] = { AnchorPoint = Vector2.new(0, 1), Pos = UDim2.new(0, 12, 1, -12) },
        ["右下"] = { AnchorPoint = Vector2.new(1, 1), Pos = UDim2.new(1, -12, 1, -12) },
    }

    local function applyPosition()
        local data = PositionMap[Settings.Position]
        if not data then return end
        radarFrame.AnchorPoint = data.AnchorPoint
        radarFrame.Position = data.Pos
    end

    local function applyCorner()
        local pct = math.clamp(Settings.Corner, 0, 100) / 100
        corner.CornerRadius = UDim.new(0, math.floor((RADAR_SIZE / 2) * pct))
    end

    -- ============ 更新逻辑 ============
    local function updateRadar()
        local myChar = lp.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then
            for _, b in ipairs(blips) do
                b.Visible = false
            end
            return
        end

        local cf = myHrp.CFrame
        local right = cf.RightVector
        local look = cf.LookVector
        local myPos = myHrp.Position
        local myTeam = lp.Team
        local scale = (RADAR_SIZE / 2 - 10) / RADAR_RANGE

        local idx = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local rel = hrp.Position - myPos
                    local dist = rel.Magnitude
                    if dist <= RADAR_RANGE then
                        -- 分类：好友 > 队友 > 敌人/中立
                        local isFriend = p:IsFriendsWith(lp.UserId)
                        local sameTeam = myTeam ~= nil and p.Team == myTeam
                        local cat
                        if isFriend then
                            cat = "friend"
                        elseif sameTeam then
                            cat = "team"
                        elseif myTeam ~= nil and p.Team ~= nil then
                            cat = "enemy"
                        elseif myTeam ~= nil then
                            cat = "neutral"   -- 对方还没入队
                        else
                            cat = "enemy"     -- 自由对战：非好友都是敌人
                        end

                        local show = (cat == "enemy" and Settings.ShowEnemy)
                            or (cat == "team" and Settings.ShowTeam)
                            or (cat == "friend" and Settings.ShowFriend)
                            or (cat == "neutral" and Settings.ShowNeutral)

                        if show then
                            idx = idx + 1
                            if idx > BLIP_COUNT then break end

                            -- 以角色朝向为雷达正上方
                            local rx = rel:Dot(right)
                            local rz = rel:Dot(look)
                            local b = blips[idx]
                            b.Position = UDim2.new(0.5, rx * scale, 0.5, -rz * scale)
                            b.BackgroundColor3 = CAT_COLORS[cat]
                            b.Visible = true
                        end
                    end
                end
            end
        end

        for i = idx + 1, BLIP_COUNT do
            blips[i].Visible = false
        end
    end

    -- 后台循环更新（10Hz，出错不中断）
    task.spawn(function()
        while true do
            if Settings.Enabled then
                pcall(updateRadar)
            end
            task.wait(0.1)
        end
    end)

    applyPosition()
    applyCorner()

    return {
        Frame = radarFrame,
        ApplyPosition = applyPosition,
        ApplyCorner = applyCorner,
    }
end)

if not okOverlay then
    warn("[雷达] 雷达覆盖层创建失败:", errOverlay)
    return
end
print("[雷达] 覆盖层创建完成")

local Radar = okOverlay

-- ============ WindUI 控制面板 ============
local win = WindUI:CreateWindow({
    Title = "雷达",
    Icon = "radar",
    Author = "demo",
    Folder = "RadarHub",
    Size = UDim2.fromOffset(620, 460),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    NewElements = true,
})
print("[雷达] 窗口创建完成")

local sec = win:Section({ Title = "雷达设置", Icon = "folder", Opened = true })
local tab = sec:Tab({ Title = "设置", Icon = "sliders-horizontal" })
tab:Select()

tab:Toggle({
    Title = "启用雷达",
    Desc = "总开关",
    Value = Settings.Enabled,
    Callback = function(v)
        Settings.Enabled = v
        Radar.Frame.Visible = v
    end,
})

tab:Dropdown({
    Title = "显示位置",
    Desc = "雷达放在屏幕哪个角",
    Values = { "左上", "右上", "左下", "右下" },
    Value = Settings.Position,
    Callback = function(v)
        Settings.Position = v
        Radar.ApplyPosition()
    end,
})

tab:Slider({
    Title = "圆角程度",
    Desc = "越高越圆，100 为圆形",
    Step = 1,
    Value = { Min = 0, Max = 100, Default = Settings.Corner },
    Callback = function(v)
        Settings.Corner = v
        Radar.ApplyCorner()
    end,
})

tab:Toggle({
    Title = "显示敌人",
    Desc = "红色亮点",
    Value = Settings.ShowEnemy,
    Callback = function(v)
        Settings.ShowEnemy = v
    end,
})

tab:Toggle({
    Title = "显示队友",
    Desc = "绿色亮点",
    Value = Settings.ShowTeam,
    Callback = function(v)
        Settings.ShowTeam = v
    end,
})

tab:Toggle({
    Title = "显示好友",
    Desc = "黄色亮点",
    Value = Settings.ShowFriend,
    Callback = function(v)
        Settings.ShowFriend = v
    end,
})

tab:Toggle({
    Title = "显示中立",
    Desc = "灰色亮点（未入队/其他玩家）",
    Value = Settings.ShowNeutral,
    Callback = function(v)
        Settings.ShowNeutral = v
    end,
})

print("[雷达] 全部加载完成")

WindUI:Notify({
    Title = "雷达",
    Content = "加载完成！右上角可见雷达",
    Icon = "radar",
    Duration = 4,
})
