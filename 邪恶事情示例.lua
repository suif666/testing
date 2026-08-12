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
		h.FillTransparency = 0.5
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = HighlightFolder
	end

	-- 文字标签
	local anchor = obj:IsA("Model") and obj.PrimaryPart or parts[1]
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
	Title = "彩虹高亮", Desc = "高亮 Objects[12] 及其同类对象", Type = "Checkbox", Value = false,
	Callback = function(v) ESP.Rainbow = v end
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
-- 按参考对象的结构精确匹配同类（普通参考 = Objects.Giver，彩虹参考 = Objects[12]）
local function childNameSet(obj)
	local set = {}
	if obj then
		for _, c in ipairs(obj:GetChildren()) do
			set[c.Name] = true
		end
	end
	return set
end

local function sameType(a, b)
	if not a or not b then return false end
	if a.ClassName ~= b.ClassName then return false end
	local sa, sb = childNameSet(a), childNameSet(b)
	for k in pairs(sa) do
		if not sb[k] then return false end
	end
	for k in pairs(sb) do
		if not sa[k] then return false end
	end
	return true
end

local function getNormalCandidates()
	local objs = getObjects()
	local ref = objs and objs:FindFirstChild("Giver")
	if not objs or not ref then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if sameType(child, ref) then
			table.insert(list, child)
		end
	end
	return list
end

local function getRainbowCandidates()
	local objs = getObjects()
	local ref = objs and (objs:FindFirstChild("EnchantedGiver") or objs:GetChildren()[12])
	if not objs or not ref then return {} end
	local list = {}
	for _, child in ipairs(objs:GetChildren()) do
		if sameType(child, ref) then
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

local function buildSignature()
	local objs = getObjects()
	local map = workspace:FindFirstChild("Map")
	local sig = ""

	if ESP.Normal and objs then
		local dep = objs:GetChildren()[23]
		local handle = dep and dep:FindFirstChild("Visual") and dep.Visual:FindFirstChild("Handle")
		sig = sig .. (handle and ("N" .. #getNormalCandidates()) or "N0")
	else
		sig = sig .. "N0"
	end

	if ESP.Monster and objs then
		sig = sig .. ("M" .. #getMonsterCandidates())
	else
		sig = sig .. "M0"
	end

	if ESP.Rainbow then
		local objs2 = getObjects()
		local ref = objs2 and (objs2:FindFirstChild("EnchantedGiver") or objs2:GetChildren()[12])
		local dep = ref and ref:FindFirstChild("Visual") and ref.Visual:FindFirstChild("Handle")
		sig = sig .. (dep and ("R" .. #getRainbowCandidates()) or "R0")
	else
		sig = sig .. "R0"
	end

	return sig
end

local function applyHighlights()
	local objs = getObjects()
	local map = workspace:FindFirstChild("Map")

	if ESP.Normal and objs then
		local dep = objs:GetChildren()[23]
		local handle = dep and dep:FindFirstChild("Visual") and dep.Visual:FindFirstChild("Handle")
		if handle then
			for _, obj in ipairs(getNormalCandidates()) do
				highlightObject(obj, Color3.fromRGB(0, 255, 90), "普通")
			end
		end
	end

	if ESP.Monster and objs then
		for _, obj in ipairs(getMonsterCandidates()) do
			highlightObject(obj:FindFirstChild("HITBOX"), Color3.fromRGB(255, 70, 70), "怪")
		end
	end

	if ESP.Rainbow then
		local objs2 = getObjects()
		local ref = objs2 and (objs2:FindFirstChild("EnchantedGiver") or objs2:GetChildren()[12])
		local dep = ref and ref:FindFirstChild("Visual") and ref.Visual:FindFirstChild("Handle")
		if dep then
			for _, obj in ipairs(getRainbowCandidates()) do
				highlightObject(obj, Color3.fromRGB(255, 0, 255), "彩虹")
			end
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
