--[[
    坐标传送（独立版）by suif
    功能：
      1. 段落实时显示玩家当前坐标（精确到小数点后两位）
      2. 「实时刷新坐标」开关，默认关闭（关闭时坐标显示静止，复制/保存仍取实时值）
      3. 复制当前坐标 / 保存当前坐标 / 自定义名称输入框
         名称留空时自动命名：坐标01、坐标02、坐标03……
      4. 可折叠的「已保存坐标」分组：刷新列表按钮 + 每条坐标带「传送」「删除」
    依赖：WindUI-Boreal
      - 优先复用主脚本已加载的 getgenv().WindUI
      - 没有则自己从 GitHub 拉取（可直接单独执行）
    说明：核心逻辑导出到 getgenv().CoordTP，方便以后并入主脚本
]]

-- ==================== 加载 WindUI ====================
local WindUI = getgenv().WindUI
if not WindUI then
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/WindUI-Boreal.lua"))()
    end)
    if ok and res then
        WindUI = res
        getgenv().WindUI = WindUI
    else
        warn("[坐标传送] WindUI 加载失败：", res)
        return
    end
end

-- ==================== 服务与玩家 ====================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local setClipboard = setclipboard or toclipboard or (syn and syn.setclipboard)
    or (getgenv and getgenv().setclipboard)

-- ==================== 存储（会话内 + 可选文件持久化） ====================
local SAVE_FILE = "SutureCoordTP.json"

local function loadSavesFromFile()
    local ok, data = pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            local raw = readfile(SAVE_FILE)
            if raw and raw ~= "" then
                return HttpService:JSONDecode(raw)
            end
        end
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function saveSavesToFile(list)
    pcall(function()
        if writefile then
            writefile(SAVE_FILE, HttpService:JSONEncode(list))
        end
    end)
end

-- 已保存坐标列表：{ {name="坐标01", x=, y=, z=}, ... }
local Saves = getgenv().SutureCoordSaves
if type(Saves) ~= "table" then
    Saves = loadSavesFromFile() or {}
    getgenv().SutureCoordSaves = Saves
end

-- ==================== 工具函数 ====================
local function getRoot()
    local char = lp.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getPos()
    local root = getRoot()
    if root then
        return root.Position
    end
    -- 兜底：用模型 pivot
    local char = lp.Character
    if char then
        local ok, pivot = pcall(function() return char:GetPivot() end)
        if ok and pivot then return pivot.Position end
    end
    return nil
end

local function fmtPos(p)
    if not p then return "X: --, Y: --, Z: --" end
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", p.X, p.Y, p.Z)
end

local function fmtEntry(e)
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", e.x or 0, e.y or 0, e.z or 0)
end

-- 自动命名：从 01 开始找第一个没有被占用的编号（填补空缺）
-- 例：已有 坐标01、坐标03（02 被删了）→ 下一个是 坐标02
local function nextDefaultName()
    local used = {}
    for _, e in ipairs(Saves) do
        local n = tostring(e.name or ""):match("^坐标(%d+)$")
        if n then
            used[tonumber(n)] = true
        end
    end
    local i = 1
    while used[i] do
        i = i + 1
    end
    return string.format("坐标%02d", i)
end

-- 通知（WindUI 全局 Notify）
local function notify(title, content, icon)
    pcall(function()
        WindUI:Notify({
            Title = tostring(title or "坐标传送"),
            Content = tostring(content or ""),
            Icon = icon or "map-pin",
            Duration = 3,
        })
    end)
end

-- 销毁元素（不同组件暴露的方法名不同，做兜底）
local function destroyElement(el)
    if not el then return end
    pcall(function()
        if type(el.Destroy) == "function" then
            el:Destroy()
        elseif el.ParagraphFrame then
            el.ParagraphFrame:Destroy()
        elseif el.ElementFrame then
            el.ElementFrame:Destroy()
        end
    end)
end

-- ==================== 核心功能 ====================
local Core = {}
Core.Saves = Saves
-- 外显坐标：显示区当前显示的数值。复制/保存都取它（所见即所得），
-- 关闭实时刷新后外显冻结，复制/保存拿到的就是冻结住的那组坐标。
Core.displayedPos = nil

-- 传送
function Core.teleportTo(x, y, z)
    local char = lp.Character
    local root = getRoot()
    if not char or not root then
        notify("传送失败", "角色不存在（可能正在重生）", "x")
        return false
    end
    local target = Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    local ok = pcall(function()
        char:PivotTo(CFrame.new(target))
    end)
    if not ok then
        ok = pcall(function()
            root.CFrame = CFrame.new(target)
        end)
    end
    if ok then
        -- 清掉惯性，避免传送后被甩走
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
        end)
        notify("传送成功", fmtPos(target), "check")
        return true
    end
    notify("传送失败", "该执行器不支持 PivotTo / CFrame 写入", "x")
    return false
end

-- 保存坐标（取外显数值：显示区显示什么就存什么）
function Core.saveCurrent(customName)
    local p = Core.displayedPos
    if not p then
        notify("保存失败", "显示区还没有坐标，请先点「刷新一次」", "x")
        return false
    end
    local name = tostring(customName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = nextDefaultName()
    end
    table.insert(Saves, {
        name = name,
        x = tonumber(string.format("%.2f", p.X)),
        y = tonumber(string.format("%.2f", p.Y)),
        z = tonumber(string.format("%.2f", p.Z)),
    })
    saveSavesToFile(Saves)
    notify("已保存", name .. "  " .. fmtPos(p), "check")
    return true
end

-- 复制坐标（取外显数值：显示区显示什么就复制什么）
function Core.copyCurrent()
    local p = Core.displayedPos
    if not p then
        notify("复制失败", "显示区还没有坐标，请先点「刷新一次」", "x")
        return false
    end
    local text = fmtPos(p)
    if setClipboard then
        pcall(setClipboard, text)
        notify("已复制到剪贴板", text, "copy")
    else
        notify("复制失败", "当前执行器没有 setclipboard", "x")
    end
    return true
end

getgenv().CoordTP = Core

-- ==================== 创建界面 ====================
local win = WindUI:CreateWindow({
    Title = "坐标传送",
    Icon = "map-pin",
    Author = "by suif",
    Folder = "CoordTP",
    Size = UDim2.fromOffset(480, 520),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    HideSearchBar = true,
})

local tab = win:Tab({ Title = "坐标传送", Icon = "map-pin", Locked = false })

-- ---------- 分组1：当前坐标 ----------
local mainSec = tab:Section({ Title = "当前坐标", Icon = "crosshair", Opened = true })

local coordPara = mainSec:Paragraph({
    Title = "玩家当前位置",
    Desc = "X: --, Y: --, Z: --",
})

-- 找到段落里显示 Desc 的那个 TextLabel（用初始文本精确匹配），用于实时更新
local descLabel = nil
do
    local frame = coordPara.ParagraphFrame or coordPara.ElementFrame
    if frame then
        for _, d in ipairs(frame:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text == "X: --, Y: --, Z: --" then
                descLabel = d
                break
            end
        end
    end
end

local LiveRefresh = false

local PLACEHOLDER_TEXT = "X: --, Y: --, Z: --"

-- 在段落内部找显示 Desc 的 TextLabel（首次没找到时刷新时会重试）
local function findDescLabel()
    local frame = coordPara.ParagraphFrame or coordPara.ElementFrame
    if not frame then return nil end
    for _, d in ipairs(frame:GetDescendants()) do
        if d:IsA("TextLabel") then
            if d.Text == PLACEHOLDER_TEXT or (d.Text and d.Text:find("X: ", 1, true)) then
                return d
            end
        end
    end
    return nil
end

local function refreshDisplay()
    local p = getPos()
    if not p then
        -- 拿不到角色坐标（重生中/未加载）：外显保持原样，不清空
        if not descLabel then descLabel = findDescLabel() end
        if descLabel and descLabel.Parent and not Core.displayedPos then
            descLabel.Text = PLACEHOLDER_TEXT
        end
        return
    end
    -- 更新外显值（复制/保存都取它）
    Core.displayedPos = p
    local text = fmtPos(p)
    if not descLabel then
        descLabel = findDescLabel()
    end
    if descLabel and descLabel.Parent then
        descLabel.Text = text
        return
    end
    -- 兜底：段落若支持 Set 就整体更新
    if type(coordPara.Set) == "function" then
        pcall(function()
            coordPara:Set({ Title = "玩家当前位置", Desc = text })
        end)
    end
end

mainSec:Toggle({
    Title = "实时刷新坐标",
    Desc = "开启后持续刷新上方坐标；关闭时坐标冻结，复制/保存取的仍是显示区那个值",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        LiveRefresh = state and true or false
        if LiveRefresh then
            refreshDisplay()
        end
    end,
})

mainSec:Button({
    Title = "刷新一次",
    Desc = "把显示区更新为当前实际坐标",
    Icon = "refresh-cw",
    Callback = function()
        refreshDisplay()
        notify("已刷新", fmtPos(Core.displayedPos), "check")
    end,
})

mainSec:Button({
    Title = "复制当前坐标",
    Desc = "复制显示区上的坐标（外显数值）",
    Icon = "copy",
    Callback = function()
        Core.copyCurrent()
    end,
})

-- 名称输入框（读取内部 TextBox 的实时文本）
local lastInputText = ""
local nameInput = mainSec:Input({
    Title = "坐标名称",
    Desc = "留空自动命名：坐标01、坐标02、坐标03……",
    Placeholder = "留空自动命名",
    Callback = function(v)
        lastInputText = tostring(v or "")
    end,
})

local function readInputText()
    -- 优先直接读输入框内部的 TextBox（用户可能还没回车就点了保存）
    local frame = nameInput.ElementFrame or nameInput.UIElements
    if frame then
        local ok, box = pcall(function()
            return frame:FindFirstChildWhichIsA("TextBox", true)
        end)
        if ok and box and box.Text and box.Text ~= "" then
            return tostring(box.Text)
        end
    end
    -- 兜底：用回调缓存的值
    return lastInputText
end

-- 前置声明，供上方按钮回调引用
local rebuildList

mainSec:Button({
    Title = "保存当前坐标",
    Desc = "保存显示区上的坐标（外显数值）到下方列表",
    Icon = "save",
    Callback = function()
        if Core.saveCurrent(readInputText()) then
            if rebuildList then rebuildList() end
        end
    end,
})

-- ---------- 分组2：已保存坐标（可折叠 = 收缩栏） ----------
local listSec = tab:Section({ Title = "已保存坐标", Icon = "folder", Opened = false })

listSec:Button({
    Title = "刷新列表",
    Desc = "重新加载保存的坐标列表",
    Icon = "refresh-cw",
    Callback = function()
        if rebuildList then rebuildList() end
        notify("列表已刷新", tostring(#Saves) .. " 个坐标", "check")
    end,
})

-- 列表元素缓存（刷新时销毁重建）
local listElements = {}

rebuildList = function()
    -- 清掉旧条目
    for _, el in ipairs(listElements) do
        destroyElement(el)
    end
    listElements = {}

    if #Saves == 0 then
        local empty = listSec:Paragraph({
            Title = "暂无保存的坐标",
            Desc = "在上方点「保存当前坐标」后，这里会显示",
        })
        table.insert(listElements, empty)
        return
    end

    for i, e in ipairs(Saves) do
        local entry = e
        local idx = i
        local item = listSec:Paragraph({
            Title = tostring(entry.name or ("坐标" .. i)),
            Desc = fmtEntry(entry),
            Buttons = {
                {
                    Title = "传送",
                    Icon = "target",
                    Variant = "Primary",
                    Callback = function()
                        Core.teleportTo(entry.x, entry.y, entry.z)
                    end,
                },
                {
                    Title = "删除",
                    Icon = "trash",
                    Callback = function()
                        table.remove(Saves, idx)
                        saveSavesToFile(Saves)
                        notify("已删除", tostring(entry.name or ""), "x")
                        rebuildList()
                    end,
                },
            },
        })
        table.insert(listElements, item)
    end

    -- 让分组重新排版（不同版本方法名不同，做兜底）
    pcall(function()
        if type(listSec.Refresh) == "function" then
            listSec:Refresh()
        elseif type(listSec.Update) == "function" then
            listSec:Update()
        end
    end)
end

-- 初始构建一次列表
rebuildList()
refreshDisplay()

-- ---------- 实时刷新循环（默认关闭，开启后每 0.1 秒刷新） ----------
task.spawn(function()
    while true do
        task.wait(0.1)
        if LiveRefresh then
            refreshDisplay()
        end
    end
end)

notify("坐标传送已加载", "右键 Shift 开关界面（默认）", "map-pin")
