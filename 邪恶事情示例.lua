-- 游戏辅助（无限体力 + ESP + 夜视/除雾）远程脚本
-- 主脚本需设置：getgenv().Tabs.GameTab（或 getgenv().SutureGameTab）

if getgenv().__SUTURE_GAME_LOADED then
	return
end
getgenv().__SUTURE_GAME_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.GameTab) or getgenv().SutureGameTab
if not Tab then
	warn("[游戏辅助] 未找到 Tab，请检查主脚本赋值")
	return
end

local WindUI = getgenv().WindUI
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
	warn("[游戏辅助] 未找到体力模块，无限体力不可用")
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
HighlightFolder.Name = "SutureGameESP"
local hui = getHui()
if hui then
	HighlightFolder.Parent = hui
else
	HighlightFolder.Parent = game:GetService("CoreGui")
end

local usedParts = {}
local anchorLabel

local function clearHighlights()
	for _, h in ipairs(HighlightFolder:GetChildren()) do
		h:Destroy()
	end
	usedParts = {}
end

-- whole=true 时整体单个高亮（售货机用）；否则每个部件单独高亮
-- 已标记过的部件跳过，避免重复类别互相顶掉
local function highlightObject(obj, color, name, whole)
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

	if whole then
		-- 整体单个高亮
		local h = Instance.new("Highlight")
		h.Name = name
		h.Adornee = obj:IsA("Model") and obj or parts[1]
		h.FillColor = color
		h.OutlineColor = Color3.new(1, 1, 1)
		h.FillTransparency = 0.25
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = HighlightFolder
		anchorLabel(parts, name, color)
		return
	end

	local added = 0
	for _, p in ipairs(parts) do
		if not usedParts[p] then
			usedParts[p] = true
			added = added + 1
			local h = Instance.new("Highlight")
			h.Name = name
			h.Adornee = p
			h.FillColor = color
			h.OutlineColor = Color3.new(1, 1, 1)
			h.FillTransparency = 0.25
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = HighlightFolder
		end
	end

	if added > 0 then
		anchorLabel(parts, name, color)
	end
end

-- 文字标签：挂到所有部件的包围盒中心附近的部件上
anchorLabel = function(parts, name, color)
	if not parts or #parts == 0 then return end
	local anchor = parts[1]
	local center = anchor.Position
	if #parts > 1 then
		local minP, maxP = parts[1].Position, parts[1].Position
		for _, p in ipairs(parts) do
			minP = Vector3.new(math.min(minP.X, p.Position.X), math.min(minP.Y, p.Position.Y), math.min(minP.Z, p.Position.Z))
			maxP = Vector3.new(math.max(maxP.X, p.Position.X), math.max(maxP.Y, p.Position.Y), math.max(maxP.Z, p.Position.Z))
		end
		center = (minP + maxP) / 2
	end
	local bestDist = (anchor.Position - center).Magnitude
	for _, p in ipairs(parts) do
		local d = (p.Position - center).Magnitude
		if d < bestDist then
			anchor = p
			bestDist = d
		end
	end

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

local function getObjects()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Objects")
end

-- ==================== 候选匹配 ====================
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

-- ==================== UI ====================
local ESP = {
	Normal = false,
	Monster = false,
	Rainbow = false,
	Vending = false,
}

local staminaEnabled = false
local cd = false

Tab:Toggle({
	Title = "无限体力", Desc = "体力低于 100 时自动回满", Type = "Checkbox", Value = false,
	Callback = function(v)
		staminaEnabled = v
		if v then
			if not Stamina then
				warn("[游戏辅助] 体力模块未加载，无法启用")
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

Tab:Toggle({
	Title = "普通高亮", Desc = "高亮 Giver 及其同类对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Normal = v end
})

Tab:Toggle({
	Title = "怪高亮", Desc = "高亮所有带 HITBOX 的怪物", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Monster = v end
})

Tab:Toggle({
	Title = "彩虹高亮", Desc = "高亮 EnchantedGiver 及其同类对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Rainbow = v end
})

Tab:Toggle({
	Title = "售货机高亮", Desc = "整体高亮 VendingMachine.Visual", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Vending = v end
})

local origAmbient = Lighting.Ambient
local origOutdoorAmbient = Lighting.OutdoorAmbient
Tab:Toggle({
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

local origFogStart = Lighting.FogStart
local origFogEnd = Lighting.FogEnd
Tab:Toggle({
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

-- ==================== ESP 循环 ====================
local function buildSignature()
	local objs = getObjects()
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
	if ESP.Vending and objs then
		sig = sig .. ("V" .. #getVendingCandidates())
	else
		sig = sig .. "V0"
	end
	return sig
end

local function applyHighlights()
	local objs = getObjects()

	if ESP.Normal and objs then
		for _, obj in ipairs(getNormalCandidates()) do
			highlightObject(obj, Color3.fromRGB(0, 255, 90), "普通")
		end
	end
	if ESP.Rainbow then
		for _, obj in ipairs(getRainbowCandidates()) do
			highlightObject(obj, Color3.fromRGB(255, 0, 255), "彩虹")
		end
	end
	if ESP.Monster and objs then
		for _, obj in ipairs(getMonsterCandidates()) do
			highlightObject(obj, Color3.fromRGB(255, 70, 70), "怪")
		end
	end
	if ESP.Vending and objs then
		for _, obj in ipairs(getVendingCandidates()) do
			highlightObject(obj, Color3.fromRGB(0, 200, 255), "售货机", true)
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

if WindUI and WindUI.Notify then
	pcall(function()
		WindUI:Notify({ Title = "游戏辅助", Content = "远程脚本已加载", Icon = "aperture", Duration = 2 })
	end)
end

print("[游戏辅助] 远程脚本加载完成")
