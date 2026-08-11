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
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Character = lp.Character or lp.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid", 10)
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 10)

local function refreshCharacter(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid", 10)
	HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 10)
end
lp.CharacterAdded:Connect(refreshCharacter)

local function pivotCharacter(cf)
	if Character and Character.Parent then
		pcall(function()
			Character:PivotTo(cf)
		end)
	end
end

-- 灾难关键词扫描
local disasterKeywords = {
	"tornado", "flood", "earthquake", "meteor", "volcano", "blizzard",
	"storm", "sandstorm", "thunder", "acid", "tsunami", "fire", "slide", "rain"
}

local function scanForDisaster()
	local names = {}

	for _, obj in ipairs(workspace:GetChildren()) do
		table.insert(names, string.lower(obj.Name))
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			local text = tostring(obj.Text or "")
			if text ~= "" then
				table.insert(names, string.lower(text))
			end
		end
	end

	for _, name in ipairs(names) do
		for _, keyword in ipairs(disasterKeywords) do
			if string.find(name, keyword, 1, true) then
				return name
			end
		end
	end

	return "未知"
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

-- 自动检测灾难
local AutoDetect = false
tab:Toggle({
	Title = "自动检测灾难", Desc = "扫描地图检测灾难并通知", Type = "Checkbox", Value = false,
	Callback = function(v)
		AutoDetect = v
		if v then
			task.spawn(function()
				local last = ""
				while AutoDetect do
					local detected = scanForDisaster()
					if detected ~= last then
						last = detected
						pcall(function()
							WindUI:Notify({ Title = "检测到灾难", Content = detected, Duration = 4, Icon = "alert-triangle" })
						end)
					end
					task.wait(1)
				end
			end)
		end
	end
})

-- 无摔落伤害
local NoFallDamage = false
tab:Toggle({
	Title = "无摔落伤害", Desc = "下落不受伤", Type = "Checkbox", Value = false,
	Callback = function(v)
		NoFallDamage = v
	end
})

RunService.Heartbeat:Connect(function()
	if NoFallDamage and HumanoidRootPart and HumanoidRootPart.Parent then
		local velocity = HumanoidRootPart.AssemblyLinearVelocity
		if velocity.Y < -45 then
			HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end
end)

WindUI:Notify({
	Title = "自然灾害", Content = "功能脚本已加载", Icon = "aperture", Duration = 3
})
