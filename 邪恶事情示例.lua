-- 无限体力 + ESP + 夜视/除雾（WindUI 独立版，游戏专属）

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
		warn("WindUI 加载失败:", res)
		return
	end
	WindUI = res
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer

-- ==================== 无限体力 ====================
local Stamina = nil
pcall(function()
	Stamina = require(ReplicatedStorage.Resources.Client.MovementHandler.Stamina)
end)
if not Stamina then
	warn("[无限体力] 未找到体力模块，本脚本仅适用于对应游戏")
end

-- ==================== ESP 基础 ====================
local function getHui()
	local ok, hui = pcall(function()
		if gethui then return gethui() end
		return nil
	end)
	return ok and hui or nil
end

local HighlightFolder = Instance.new("Folder")
HighlightFolder.Name = "SutureESP"
local hui = getHui()
if hui then
	HighlightFolder.Parent = hui
else
	HighlightFolder.Parent = game:GetService("CoreGui")
end

local function clearHighlights()
	for _, h in ipairs(HighlightFolder:GetChildren()) do
		h:Destroy()
	end
end

-- 高亮整个对象：每个部件单独建 Highlight（避免 Model 整体高亮只亮一个部件），
-- 并在主部件上挂一个名字文字标签
local function highlightObject(obj, color, name)
	if not obj then return end

	local parts = {}
	if obj:IsA("BasePart") then
		parts = {obj}
	else
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
	end
	if #parts == 0 then return end

	for _, p in ipairs(parts) do
		local h = Instance.new("Highlight")
		h.Name = name
		h.Adornee = p
		h.FillColor = color
		h.OutlineColor = Color3.new(1, 1, 1)
		h.FillTransparency = 0.3
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = HighlightFolder
	end

	-- 文字标签：优先 PrimaryPart，否则取所有部件的包围盒中心附近的部件
	local anchor = obj:IsA("Model") and obj.PrimaryPart or nil
	if not anchor then
		local center = parts[1].Position
		if #parts > 1 then
			local minP, maxP = parts[1].Position, parts[1].Position
			for _, p in ipairs(parts) do
				minP = Vector3.new(math.min(minP.X, p.Position.X), math.min(minP.Y, p.Position.Y), math.min(minP.Z, p.Position.Z))
				maxP = Vector3.new(math.max(maxP.X, p.Position.X), math.max(maxP.Y, p.Position.Y), math.max(maxP.Z, p.Position.Z))
			end
			center = (minP + maxP) / 2
		end
		anchor = parts[1]
		local bestDist = (anchor.Position - center).Magnitude
		for _, p in ipairs(parts) do
			local d = (p.Position - center).Magnitude
			if d < bestDist then
				anchor = p
				bestDist = d
			end
		end
	end
	if anchor then
		local bill = Instance.new("BillboardGui")
		bill.Name = name .. "_Text"
		bill.Adornee = anchor
		bill.AlwaysOnTop = true
		bill.Size = UDim2.new(0, 110, 0, 26)
		bill.StudsOffset = Vector3.new(0, 3, 0)
		bill.MaxDistance = 300
		bill.Parent = HighlightFolder

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = name
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.2
		label.TextSize = 14
		label.Font = Enum.Font.SourceSansBold
		label.Parent = bill
	end
end

local function getObjects()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Objects")
end

local ESP = {
	Normal = false,
	Monster = false,
	Rainbow = false,
	Item = false,
	Vending = false,
}

-- ==================== UI ====================
local win = WindUI:CreateWindow({
	Title = "游戏辅助", Icon = "aperture", Author = "by suif", Folder = "SutureHub",
	Size = UDim2.fromOffset(520, 420), MinSize = Vector2.new(460, 340), MaxSize = Vector2.new(760, 580),
	ToggleKey = Enum.KeyCode.RightShift, Transparent = true, Theme = "Dark",
	Resizable = true, SideBarWidth = 140, HideSearchBar = true,
	ScrollBarEnabled = true, NewElements = true,
	User = { Enabled = true, Anonymous = false, Callback = function() print("当前用户:", lp.Name) end }
})

win:Tag({ Title = "free", Icon = "gem", Color = Color3.fromHex("#30ff6a"), Radius = 0 })

local mainTab = win:Tab({ Title = "功能", Icon = "user", Locked = false })
local espTab = win:Tab({ Title = "视觉", Icon = "palette", Locked = false })
mainTab:Select()

-- 无限体力
local staminaEnabled = false
local cd = false

mainTab:Toggle({
	Title = "无限体力", Desc = "体力低于 100 时自动回满", Type = "Checkbox", Value = false,
	Callback = function(v)
		staminaEnabled = v
		if v then
			if not Stamina then
				warn("[无限体力] 模块未加载，无法启用")
				return
			end
			task.spawn(function()
				while staminaEnabled do
					task.wait(0.1)
					local ok, cur = pcall(function()
						return Stamina.Get()
					end)
					if ok and cur <= 100 and not cd then
						cd = true
						pcall(function()
							Stamina.DrainStamina(-100, 0, true)
						end)
						pcall(function()
							Stamina.DestroyDrainer("BaseDrain")
						end)
						task.wait(1)
						cd = false
					end
				end
			end)
		end
	end
})

-- ESP：普通（[26]，依赖 [23].Visual.Handle 存在）
espTab:Toggle({
	Title = "普通高亮", Desc = "高亮 Giver 及其同类对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Normal = v end
})

-- ESP：怪（[48].HITBOX）
espTab:Toggle({
	Title = "怪高亮", Desc = "高亮所有带 HITBOX 的对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Monster = v end
})

-- ESP：彩虹（EnchantedGiver.Main，依赖 Visual.Handle 存在）
espTab:Toggle({
	Title = "彩虹高亮", Desc = "高亮 EnchantedGiver 及其同类对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Rainbow = v end
})

-- ESP：物品（Objects[20] 及其同名对象）
espTab:Toggle({
	Title = "物品高亮", Desc = "高亮 Objects[20] 及其同名对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Item = v end
})

-- ESP：售货机（VendingMachine.Visual）
espTab:Toggle({
	Title = "售货机高亮", Desc = "高亮 VendingMachine.Visual", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Vending = v end
})

-- 夜视
local origAmbient = Lighting.Ambient
local origOutdoorAmbient = Lighting.OutdoorAmbient
espTab:Toggle({
	Title = "夜视", Desc = "地图变亮", Type = "Checkbox", Value = false,
	Callback = function(v)
		if v then
			Lighting.Ambient = Color3.new(1, 1, 1)
			Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		else
			Lighting.Ambient = origAmbient
			Lighting.OutdoorAmbient = origOutdoorAmbient
		end
	end
})

-- 除雾
local origFogStart = Lighting.FogStart
local origFogEnd = Lighting.FogEnd
espTab:Toggle({
	Title = "除雾", Desc = "移除地图雾气", Type = "Checkbox", Value = false,
	Callback = function(v)
		if v then
			Lighting.FogStart = 0
			Lighting.FogEnd = 100000
		else
			Lighting.FogStart = origFogStart
			Lighting.FogEnd = origFogEnd
		end
	end
})

-- ==================== ESP 循环（条件不满足自动停） ====================
-- 判定规则：按名字筛（普通=含 Giver 且非 EnchantedGiver，彩虹=含 EnchantedGiver），
-- 再判断该物品是否存在 Handle 子结构，存在才高亮
local function hasHandle(obj)
	return obj ~= nil and obj:FindFirstChild("Handle", true) ~= nil
end

local function isNormalName(name)
	name = string.lower(tostring(name or ""))
	return string.find(name, "giver", 1, true) ~= nil
		and string.find(name, "enchantedgiver", 1, true) == nil
end

local function isRainbowName(name)
	name = string.lower(tostring(name or ""))
	return string.find(name, "enchantedgiver", 1, true) ~= nil
end

local function getNormalCandidates()
	local objs = getObjects()
	if not objs then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if isNormalName(child.Name) and hasHandle(child) then
			table.insert(list, child)
		end
	end
	return list
end

local function getRainbowCandidates()
	local objs = getObjects()
	if not objs then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if isRainbowName(child.Name) and hasHandle(child) then
			table.insert(list, child)
		end
	end
	return list
end

local function getMonsterCandidates()
	local objs = getObjects()
	if not objs then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if child:FindFirstChild("HITBOX") then
			table.insert(list, child)
		end
	end
	return list
end

local function getItemCandidates()
	local objs = getObjects()
	local ref = objs and objs:GetChildren()[20]
	if not objs or not ref then return {} end
	local name = ref.Name
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if child.Name == name then
			table.insert(list, child)
		end
	end
	return list
end

local function getVendingCandidates()
	local objs = getObjects()
	if not objs then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if string.find(string.lower(child.Name), "vendingmachine", 1, true) then
			local visual = child:FindFirstChild("Visual")
			if visual then
				table.insert(list, visual)
			end
		end
	end
	return list
end

local function buildSignature()
	local objs = getObjects()
	local map = workspace:FindFirstChild("Map")
	local sig = ""

	if ESP.Normal and objs then
		sig = sig .. ("N" .. #getNormalCandidates())
	else
		sig = sig .. "N0"
	end

	if ESP.Monster and objs then
		sig = sig .. ("M" .. #getMonsterCandidates())
	else
		sig = sig .. "M0"
	end

	if ESP.Rainbow then
		sig = sig .. ("R" .. #getRainbowCandidates())
	else
		sig = sig .. "R0"
	end

	if ESP.Item and objs then
		sig = sig .. ("I" .. #getItemCandidates())
	else
		sig = sig .. "I0"
	end

	if ESP.Vending and objs then
		sig = sig .. ("V" .. #getVendingCandidates())
	else
		sig = sig .. "V0"
	end

	return sig
end

local function applyHighlights()
	local objs = getObjects()
	local map = workspace:FindFirstChild("Map")

	if ESP.Normal and objs then
		for _, obj in ipairs(getNormalCandidates()) do
			highlightObject(obj, Color3.fromRGB(0, 255, 90), "普通")
		end
	end

	if ESP.Monster and objs then
		for _, obj in ipairs(getMonsterCandidates()) do
			highlightObject(obj, Color3.fromRGB(255, 70, 70), "怪")
		end
	end

	if ESP.Rainbow then
		for _, obj in ipairs(getRainbowCandidates()) do
			highlightObject(obj, Color3.fromRGB(255, 0, 255), "彩虹")
		end
	end

	if ESP.Item and objs then
		for _, obj in ipairs(getItemCandidates()) do
			highlightObject(obj, Color3.fromRGB(255, 200, 0), "物品")
		end
	end

	if ESP.Vending and objs then
		for _, obj in ipairs(getVendingCandidates()) do
			highlightObject(obj, Color3.fromRGB(0, 200, 255), "售货机")
		end
	end
end

task.spawn(function()
	local lastSig = ""
	while true do
		task.wait(0.5)
		local sig = buildSignature()
		if sig ~= lastSig then
			lastSig = sig
			clearHighlights()
			applyHighlights()
		end
	end
end)

WindUI:Notify({
	Title = "游戏辅助", Content = "脚本已加载", Icon = "aperture", Duration = 2
})
