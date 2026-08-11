-- 自然灾害功能脚本（WindUI 独立版，取自 Xa 源码）
-- 功能：自动赢 / 水上行走 / 岛屿悬崖可碰撞 / 自动检测灾难 / 无摔落伤害

if getgenv().SutureNatureHub then
	return
end
getgenv().SutureNatureHub = true

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

local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local Character = lp.Character or lp.CharacterAdded:Wait()

local function refreshCharacter(char)
	Character = char
end
lp.CharacterAdded:Connect(refreshCharacter)

local function pivotCharacter(cf)
	if Character and Character.Parent then
		pcall(function()
			Character:PivotTo(cf)
		end)
	end
end

-- 读取游戏预留给玩家的下一个灾难（SurvivalTag）
local function getNextDisaster()
	local tag = Character and Character:FindFirstChild("SurvivalTag")
	if tag then
		return tostring(tag.Value)
	end
	return nil
end

local win = WindUI:CreateWindow({
	Title = "自然灾害", Icon = "aperture", Author = "by suif", Folder = "SutureHub",
	Size = UDim2.fromOffset(480, 360), MinSize = Vector2.new(420, 300), MaxSize = Vector2.new(700, 500),
	ToggleKey = Enum.KeyCode.RightShift, Transparent = true, Theme = "Dark",
	Resizable = true, SideBarWidth = 160, HideSearchBar = true,
	ScrollBarEnabled = true, NewElements = true,
	User = { Enabled = true, Anonymous = false, Callback = function() print("当前用户:", lp.Name) end }
})

win:Tag({ Title = "free", Icon = "gem", Color = Color3.fromHex("#30ff6a"), Radius = 0 })

local tab = win:Tab({ Title = "功能", Icon = "user", Locked = false })
tab:Select()

-- 自动赢
local AutoFarm = false
tab:Toggle({
	Title = "自动赢", Desc = "每帧传送到固定点位", Type = "Checkbox", Value = false,
	Callback = function(v)
		AutoFarm = v
		if v then
			task.spawn(function()
				while AutoFarm do
					pivotCharacter(CFrame.new(-236, 180, 360))
					task.wait()
				end
			end)
		end
	end
})

-- 水上行走
local WaterLevel = workspace:FindFirstChild("WaterLevel")
local WaterMesh = WaterLevel and WaterLevel:FindFirstChild("Mesh")

tab:Toggle({
	Title = "水上行走", Desc = "打开后水面可站立", Type = "Checkbox", Value = false,
	Callback = function(v)
		if WaterLevel then
			WaterLevel.CanCollide = v
			WaterLevel.Size = v and Vector3.new(1000, 1, 1000) or Vector3.new(10, 1, 10)
			if WaterMesh then
				WaterMesh.Parent = v and nil or WaterLevel
			end
		end
	end
})

-- 岛屿悬崖可碰撞
tab:Toggle({
	Title = "岛屿悬崖可碰撞", Desc = "开启岛屿部件碰撞", Type = "Checkbox", Value = false,
	Callback = function(v)
		local island = workspace:FindFirstChild("Island")
		if island then
			for _, obj in ipairs(island:GetDescendants()) do
				if obj:IsA("BasePart") then
					obj.CanCollide = v
				end
			end
		end
	end
})

-- 预测灾害
local AutoDetect = false
tab:Toggle({
	Title = "预测灾害", Desc = "读取 SurvivalTag 预测下一个灾难", Type = "Checkbox", Value = false,
	Callback = function(v)
		AutoDetect = v
		if v then
			print("[灾害预测] 已开启，当前:", tostring(getNextDisaster()))
			task.spawn(function()
				local last = nil
				while AutoDetect do
					local nextDisaster = getNextDisaster()
					if nextDisaster and nextDisaster ~= last then
						last = nextDisaster
						print("[灾害预测] 下一个灾难:", nextDisaster)
						pcall(function()
							game:GetService("StarterGui"):SetCore("SendNotification", {
								Title = "下一个灾难",
								Text = nextDisaster,
								Duration = 5
							})
						end)
					end
					task.wait(1)
				end
			end)
		end
	end
})

-- 无摔落伤害（直接移除游戏自带的 FallDamageScript）
local NoFallDamage = false
local noFallConn = nil

local function disableFallDamage(char)
	pcall(function()
		local fd = char and char:FindFirstChild("FallDamageScript")
		if fd then
			fd:Destroy()
		end
	end)
end

tab:Toggle({
	Title = "无摔落伤害", Desc = "移除游戏自带的摔落伤害脚本", Type = "Checkbox", Value = false,
	Callback = function(v)
		NoFallDamage = v
		if v then
			disableFallDamage(Character)
			if not noFallConn then
				noFallConn = lp.CharacterAdded:Connect(function(char)
					task.wait(0.2)
					disableFallDamage(char)
				end)
			end
		elseif noFallConn then
			noFallConn:Disconnect()
			noFallConn = nil
		end
	end
})

WindUI:Notify({
	Title = "自然灾害", Content = "功能脚本已加载", Icon = "aperture", Duration = 3
})
