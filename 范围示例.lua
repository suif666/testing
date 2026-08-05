-- 范围放大（参考 BS-loves_you.lua 的"范围"功能）
-- 把其他玩家的 HumanoidRootPart 放大成可自由调节大小的红色半透明立方体
-- 因为是真实根部件：射线子弹、Touched 近战都能正常命中
print("[范围放大] 开始执行")

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
print("[范围放大] WindUI 加载完成")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    Enabled = false,
    Size = 30,                -- 立方体边长（studs），自由调节
    Transparency = 0.7,
    PhysicalCollide = false,  -- 近战物理碰撞开关
}

local State = {
    snapshots = {},           -- 每个被改过的根部件 -> 原始属性
}

local function getHRP(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- 第一次修改前记录原始属性
local function snapshot(character)
    local hrp = getHRP(character)
    if hrp and not State.snapshots[hrp] then
        State.snapshots[hrp] = {
            Size = hrp.Size,
            Transparency = hrp.Transparency,
            Color = hrp.Color,
            Material = hrp.Material,
            CanCollide = hrp.CanCollide,
            Massless = hrp.Massless,
            CanQuery = hrp.CanQuery,
            CanTouch = hrp.CanTouch,
        }
    end
end

local function restoreHRP(hrp)
    local old = State.snapshots[hrp]
    if old and hrp and hrp.Parent then
        pcall(function()
            hrp.Size = old.Size
            hrp.Transparency = old.Transparency
            hrp.Color = old.Color
            hrp.Material = old.Material
            hrp.CanCollide = old.CanCollide
            hrp.Massless = old.Massless
            hrp.CanQuery = old.CanQuery
            hrp.CanTouch = old.CanTouch
        end)
    end
end

local function restoreAll()
    for hrp, _ in pairs(State.snapshots) do
        restoreHRP(hrp)
    end
    State.snapshots = {}
end

-- 每帧锁定所有目标（游戏脚本想重置也会被拉回来）
local function applyAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local hrp = getHRP(plr.Character)
            if hrp then
                snapshot(plr.Character)
                pcall(function()
                    hrp.Size = Vector3.new(Config.Size, Config.Size, Config.Size)
                    hrp.Transparency = Config.Transparency
                    hrp.Material = Enum.Material.Neon
                    hrp.Color = Color3.fromRGB(255, 0, 0)
                    hrp.CanCollide = Config.PhysicalCollide
                    hrp.Massless = true          -- 零质量：不影响钩子拉人等物理效果
                    hrp.CanQuery = true
                    hrp.CanTouch = true
                end)
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    if Config.Enabled then
        pcall(applyAll)
    end
end)

-- ============ UI ============
local win = WindUI:CreateWindow({
    Title = "范围放大",
    Icon = "radar",
    Author = "demo",
    Folder = "RangeEnlarge",
    Size = UDim2.fromOffset(620, 460),
    Resizable = true,
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 180,
    NewElements = true,
})
print("[范围放大] 窗口创建完成")

local sec = win:Section({ Title = "范围设置", Icon = "folder", Opened = true })
local tab = sec:Tab({ Title = "设置", Icon = "sliders-horizontal" })
tab:Select()

local mainToggle = tab:Toggle({
    Title = "主开关",
    Desc = "开启后放大所有玩家的根部件",
    Value = Config.Enabled,
    Callback = function(v)
        Config.Enabled = v
        if not v then
            restoreAll()
        end
    end,
})

tab:Slider({
    Title = "范围大小",
    Desc = "立方体边长（studs），自由调节",
    Step = 1,
    Value = { Min = 0, Max = 2500, Default = Config.Size },
    Callback = function(v)
        Config.Size = v
    end,
})

tab:Slider({
    Title = "透明度",
    Desc = "0 完全透明，1 完全不透明",
    Step = 0.05,
    Value = { Min = 0, Max = 1, Default = Config.Transparency },
    Callback = function(v)
        Config.Transparency = v
    end,
})

tab:Toggle({
    Title = "物理碰撞（近战命中）",
    Desc = "开启后武器实体碰到也算命中，但会挡人",
    Value = Config.PhysicalCollide,
    Callback = function(v)
        Config.PhysicalCollide = v
    end,
})

tab:Button({
    Title = "恢复正常大小",
    Callback = function()
        Config.Enabled = false
        restoreAll()
        if mainToggle and mainToggle.Set then
            pcall(mainToggle.Set, mainToggle, false)
        end
    end,
})

print("[范围放大] 全部加载完成")

WindUI:Notify({
    Title = "范围放大",
    Content = "加载完成！开启后可用滑块自由调范围",
    Icon = "radar",
    Duration = 4,
})
