-- 自然灾害 远程脚本（依赖主脚本提供 WindUI 和 Tab）
-- 主脚本需设置：getgenv().Tabs.ZRZHTab（或 getgenv().SutureZRZHTab）

if getgenv().__SUTURE_ZRZH_LOADED then
	return
end
getgenv().__SUTURE_ZRZH_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.ZRZHTab) or getgenv().SutureZRZHTab
if not Tab then
	warn("[自然灾害] 未找到 Tab，请检查主脚本赋值")
	return
end

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local WindUI = getgenv().WindUI
local lp = Players.LocalPlayer

local Character = lp.Character or lp.CharacterAdded:Wait()
lp.CharacterAdded:Connect(function(char)
	Character = char
end)

local function notify(title, text)
	if WindUI and WindUI.Notify then
		pcall(function()
			WindUI:Notify({ Title = title, Content = text or "", Duration = 4, Icon = "bell" })
		end)
	else
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = title, Text = text or "", Duration = 4
			})
		end)
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
			notify(name or "脚本", "已运行")
		else
			warn("执行失败: " .. tostring(err))
		end
	end)
end

-- 龙卷风
Tab:Button({
	Title = "自然灾害 龙卷风", Desc = "大风车呀滴溜溜的转...", Icon = "shell",
	Callback = function()
		run("https://pastebin.com/raw/JR7RBh2a", "龙卷风")
	end
})

-- 未锚定部件吸附
Tab:Button({
	Title = "未锚定部件吸附", Desc = "花样龙卷风 还可以嫁祸别人 嗯对反正我用不明白", Icon = "shell",
	Callback = function()
		run("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/%E8%87%AA%E7%84%B6%E7%81%BE%E5%AE%B3%E9%BB%91%E6%B4%9E.lua", "未锚定部件吸附")
	end
})

-- 灾难名中英对照（覆盖游戏全部灾害 + 常见变体）
local disasterNames = {
	tornado = "龙卷风",
	flood = "洪水",
	earthquake = "地震",
	meteor = "陨石",
	["meteor shower"] = "陨石雨",
	volcano = "火山",
	["volcanic eruption"] = "火山喷发",
	blizzard = "暴风雪",
	deadly virus = "致命病毒",
	storm = "风暴",
	thunderstorm = "雷暴",
	sandstorm = "沙尘暴",
	thunder = "雷暴",
	["acid rain"] = "酸雨",
	acid = "酸雨",
	tsunami = "海啸",
	fire = "火灾",
	firestorm = "火风暴",
	wildfire = "野火",
	landslide = "山体滑坡",
	mudslide = "泥石流",
	rain = "大雨",
	["heavy rain"] = "暴雨",
	hurricane = "飓风",
	hailstorm = "冰雹",
	hail = "冰雹",
	lightning = "闪电",
	["lightning storm"] = "闪电风暴",
	heatwave = "热浪",
	["heat wave"] = "热浪",
	snowstorm = "暴风雪",
	snow = "暴雪",
	["dust storm"] = "沙尘暴",
}

-- 长关键词优先，模糊匹配兜底（处理大小写/多余字符）
local disasterKeys = {}
for k in pairs(disasterNames) do
	table.insert(disasterKeys, k)
end
table.sort(disasterKeys, function(a, b)
	return #a > #b
end)

local function translateDisaster(name)
	local key = string.lower(tostring(name or ""))
	if disasterNames[key] then
		return disasterNames[key]
	end
	for _, kw in ipairs(disasterKeys) do
		if string.find(key, kw, 1, true) then
			return disasterNames[kw]
		end
	end
	return name
end

-- 预测灾害
local AutoDetect = false
local updateDisasterText

Tab:Toggle({
	Title = "预测灾害", Desc = "读取 SurvivalTag 预测下一个灾难", Icon = "zap", Type = "Checkbox", Value = false,
	Callback = function(v)
		AutoDetect = v
		if v then
			local function getNext()
				local tag = Character and Character:FindFirstChild("SurvivalTag")
				return tag and tostring(tag.Value) or nil
			end
			task.spawn(function()
				local last = nil
				while AutoDetect do
					local nextDisaster = getNext()
					if nextDisaster and nextDisaster ~= last then
						last = nextDisaster
						local cn = translateDisaster(nextDisaster)
						updateDisasterText("下一个灾难：" .. cn)
						notify("下一个灾难", cn)
					end
					task.wait(1)
				end
			end)
		end
	end
})

-- 开关下方实时显示当前预测（Paragraph 的 SetDesc 可用）
local disasterText = Tab:Paragraph({ Title = "当前预测", Desc = "等待检测..." })
updateDisasterText = function(text)
	if disasterText and disasterText.SetDesc then
		disasterText:SetDesc(text)
	end
end
