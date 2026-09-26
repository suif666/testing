-- 自瞄类 远程脚本 v2（显示功能 + UI，依赖主脚本提供 AimbotTab）
--
-- 相比 v1 修掉的核心问题：
--   1. 准心一直抖  → 锁定时把 MouseDeltaSensitivity 设 0，游戏相机收不到鼠标输入，
--                    我们写的 CFrame 才不会被它每帧掰回去（Exunys V3 / Open-Aimbot 同款做法）
--   2. 准心一直抖  → 用 BindToRenderStep 绑到 Camera 优先级 +1，保证跑在游戏相机模块之后
--   3. 准心一直抖  → 目标粘滞：锁定后不每帧重选，新目标要明显更优才换
--   4. 准心一直抖  → 平滑改成帧率无关的指数逼近（原来裸 Lerp，高刷屏抖得厉害）
--   5. 有些游戏没效果 → 加鼠标模式（mousemoverel），游戏有自定义相机时用这个
--   6. 有些游戏没效果 → 部位加 R6/R15 回退链，没有 "Head" 的骨架也能瞄
--   7. 有些游戏没效果 → FOV 圆心改成鼠标位置（有黑边/自定义准心时屏幕中心不是准心）
--   8. 重复执行不再失效 → 重新加载会先清理上一个实例
--   9. 手机上 FOV 圈跑到左上角 → 手机自动改用屏幕中心（手机没有鼠标，
--      GetMouseLocation 返回的是上次触摸位置，没碰屏幕就是 0,0），并加屏幕触发按钮

local Tab = (getgenv().Tabs and getgenv().Tabs.AimbotTab) or getgenv().SutureAimbotTab
if not Tab then
	warn("[自瞄类] 未找到 AimbotTab，请检查主脚本是否正确赋值")
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local lp = Players.LocalPlayer
local mousemoverel = getgenv().mousemoverel or mousemoverel

getgenv().__SUTURE_AIMBOT_LOADED = true

-- ============ 设备检测（电脑 / 手机）============
-- 手机上 UserInputService:GetMouseLocation() 返回的是「上一次触摸的位置」，
-- 没碰屏幕时是 (0,0)，所以 FOV 圈会跑到左上角 —— 手机上必须改用屏幕中心。
-- 判断标准：有触摸但没鼠标 = 手机/平板（触摸屏笔记本有鼠标，仍算电脑）。
local function detectDevice()
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		return "手机"
	end
	return "电脑"
end
local AUTO_DEVICE = detectDevice()

-- ============ 清理上一个实例（重复执行脚本时不叠加）============
local BIND_NAME = "SutureAimbotStep"
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
if getgenv().__SUTURE_AIMBOT_CLEANUP then
	pcall(getgenv().__SUTURE_AIMBOT_CLEANUP)
	getgenv().__SUTURE_AIMBOT_CLEANUP = nil
end

-- ============ 配置 ============
local defaultAimbot = {
	Enabled = false,
	Device = "自动",             -- 自动 / 电脑 / 手机
	Mode = "自动",              -- 自动 / 相机 / 鼠标
	HoldKey = "无（一直自瞄）",
	HoldMode = true,            -- true=按住  false=按一下切换
	HoldButton = (AUTO_DEVICE == "手机"),   -- 屏幕按钮触发（手机默认开）
	ShowFov = false,
	Fov = 200,
	MaxDistance = 1000,
	Part = "Head",
	TeamCheck = false,
	WallCheck = false,
	Smooth = 0.55,              -- 越大越快，1 = 瞬间
	Prediction = 0.1,
	PingComp = false,           -- 延迟补偿
	Sticky = true,
	SwitchMargin = 0.25,
	MouseSens = 2,              -- 鼠标模式：越小越猛
	OffsetY = 0,                -- 瞄准点上下偏移
}
getgenv().SutureAimbot = getgenv().SutureAimbot or {}
for k, v in pairs(defaultAimbot) do
	if getgenv().SutureAimbot[k] == nil then
		getgenv().SutureAimbot[k] = v
	end
end
local Aimbot = getgenv().SutureAimbot
-- 兼容 v1 遗留字段
if Aimbot.Priority == nil then Aimbot.Priority = "准心优先" end

-- ============ 当前设备 & 准心位置 ============
local function isMobileNow()
	local d = Aimbot.Device
	if d == "手机" then return true end
	if d == "电脑" then return false end
	return AUTO_DEVICE == "手机"
end

-- 电脑：准心 = 鼠标位置（有些游戏有黑边/自定义准心，屏幕中心不是准心）
-- 手机：没有鼠标，屏幕上又没有准心，瞄准点就是屏幕正中心
local function aimCenter(cam)
	if isMobileNow() then
		local vp = cam.ViewportSize
		return Vector2.new(vp.X / 2, vp.Y / 2)
	end
	return UIS:GetMouseLocation()
end

-- ============ FOV 圈 ============
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "AimbotFOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = false
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

local lockLabel = Instance.new("TextLabel")
lockLabel.Name = "Locked"
lockLabel.AnchorPoint = Vector2.new(0.5, 0)
lockLabel.Position = UDim2.new(0.5, 0, 1, 6)
lockLabel.Size = UDim2.fromOffset(220, 16)
lockLabel.BackgroundTransparency = 1
lockLabel.Font = Enum.Font.SourceSansBold
lockLabel.TextSize = 13
lockLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
lockLabel.TextStrokeTransparency = 0.3
lockLabel.Text = ""
lockLabel.Parent = fovRing

-- ============ 灵敏度锁（消抖关键）============
local savedSens = nil
local sensZeroed = false

local function lockSensitivity()
	if not sensZeroed then
		savedSens = UIS.MouseDeltaSensitivity
		sensZeroed = true
	end
	if UIS.MouseDeltaSensitivity ~= 0 then
		pcall(function() UIS.MouseDeltaSensitivity = 0 end)
	end
end

local function unlockSensitivity()
	if sensZeroed and savedSens ~= nil then
		pcall(function() UIS.MouseDeltaSensitivity = savedSens end)
	end
	sensZeroed = false
	savedSens = nil
end

-- ============ 部位：R6/R15 回退链 ============
local PART_FALLBACK = {
	Head = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
	HumanoidRootPart = { "HumanoidRootPart", "UpperTorso", "Torso", "Head" },
	UpperTorso = { "UpperTorso", "Torso", "HumanoidRootPart", "Head" },
	Torso = { "Torso", "UpperTorso", "HumanoidRootPart", "Head" },
}
local RANDOM_PARTS = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }

local function getAimPart(character, want)
	if not character then return nil end
	if want == "随机" then
		for _, name in ipairs(RANDOM_PARTS) do
			local p = character:FindFirstChild(name)
			if p and p:IsA("BasePart") then return p end
		end
		return nil
	end
	local chain = PART_FALLBACK[want] or { want, "Head", "HumanoidRootPart" }
	for _, name in ipairs(chain) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then return p end
	end
	return nil
end

-- 自带的 clamp：math.clamp 是 Luau 专有的，自己写一个更好测
local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- ============ 平滑：帧率无关的指数逼近 ============
local function alphaFor(s, dt)
	s = tonumber(s) or 0.55
	if s >= 0.99 then return 1 end
	local speed = 2 + 30 * s * s          -- 约 2 ~ 32 次/秒
	return 1 - math.exp(-speed * dt)
end

-- ============ 墙检：优先用相机自带的遮挡查询 ============
local function isObscured(cam, targetPos, myChar, targetChar)
	local ok, parts = pcall(function()
		return cam:GetPartsObscuringTarget({ targetPos }, { myChar, targetChar })
	end)
	if ok and parts ~= nil then
		for _, p in ipairs(parts) do
			if p and p.Transparency < 0.9 and not p:IsDescendantOf(targetChar) then
				return true
			end
		end
		return false
	end
	-- 老客户端没有 GetPartsObscuringTarget 时退回手搓射线
	local origin = cam.CFrame.Position
	local dirVec = targetPos - origin
	local dist = dirVec.Magnitude
	if dist <= 0 then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { myChar, targetChar }
	params.IgnoreWater = true
	local ray = workspace:Raycast(origin, dirVec.Unit * dist, params)
	if ray and ray.Instance then
		return ray.Instance.Transparency < 0.9 and not ray.Instance:IsDescendantOf(targetChar)
	end
	return false
end

-- ============ 目标选择（带粘滞）============
local locked = nil            -- { Player=, Character=, Part= }

local function scoreOf(entry, cam)
	local part = entry.Part
	if not part then return math.huge end
	if Aimbot.Priority == "血量低优先" then
		local hum = entry.Character:FindFirstChildOfClass("Humanoid")
		return hum and hum.Health or math.huge
	elseif Aimbot.Priority == "距离优先" then
		return (cam.CFrame.Position - part.Position).Magnitude
	end
	local pos = cam:WorldToViewportPoint(part.Position)
	local center = aimCenter(cam)
	return (Vector2.new(pos.X, pos.Y) - center).Magnitude
end

local function getAimTarget(cam)
	local center = aimCenter(cam)
	local myChar = lp.Character
	local best, bestScore = nil, math.huge

	-- 用 repeat...until true + break 代替 Luau 的 continue，
	-- 这样这段代码用普通 Lua 解析器也能校验语法
	for _, p in ipairs(Players:GetPlayers()) do
		repeat
			if p == lp then break end
			local char = p.Character
			if not char then break end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then break end
			if Aimbot.TeamCheck and p.Team and lp.Team and p.Team == lp.Team then break end

			-- 锁定中的目标沿用原来那个部位，避免「随机」每帧乱跳
			local isLocked = locked and locked.Player == p
			local part
			if isLocked and locked.Part and locked.Part.Parent then
				part = locked.Part
			else
				part = getAimPart(char, Aimbot.Part)
			end
			if not part then break end

			local pos, onScreen = cam:WorldToViewportPoint(part.Position)
			if not onScreen then break end

			local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
			if screenDist > Aimbot.Fov then break end

			local worldDist = (cam.CFrame.Position - part.Position).Magnitude
			if worldDist > Aimbot.MaxDistance then break end

			if Aimbot.WallCheck and isObscured(cam, part.Position, myChar, char) then break end

			local score = scoreOf({ Player = p, Character = char, Part = part }, cam)

			-- 给当前锁定的目标打折：新目标必须明显更优才会抢走锁定
			if Aimbot.Sticky and isLocked then
				score = score * (1 - clamp(tonumber(Aimbot.SwitchMargin) or 0.25, 0, 0.9))
			end

			if score < bestScore then
				bestScore = score
				best = { Player = p, Character = char, Part = part }
			end
		until true
	end

	locked = best
	return best
end

-- ============ 鼠标模式 ============
local function aimWithMouse(cam, targetPos, dt)
	if not mousemoverel then return false end
	local pos, onScreen = cam:WorldToViewportPoint(targetPos)
	if not onScreen then return false end
	local mouse = UIS:GetMouseLocation()
	local dx, dy = pos.X - mouse.X, pos.Y - mouse.Y
	if math.abs(dx) < 0.6 and math.abs(dy) < 0.6 then return true end
	local sens = math.max(0.5, tonumber(Aimbot.MouseSens) or 2)
	local k = alphaFor(Aimbot.Smooth, dt) * 3
	pcall(function()
		mousemoverel(dx / sens * k, dy / sens * k)
	end)
	return true
end

-- ============ 相机模式 ============
local lastSetCF = nil
local cameraFightFrames = 0
local autoSwitched = false

local function cameraIsFighting(cam)
	if not lastSetCF then return false end
	local ang = math.deg(math.acos(clamp(cam.CFrame.LookVector:Dot(lastSetCF.LookVector), -1, 1)))
	local moved = (cam.CFrame.Position - lastSetCF.Position).Magnitude
	return ang > 3 or moved > 1.5
end

-- ============ 触发按键 ============
local KEY_MAP = {
	["E"] = Enum.KeyCode.E, ["Q"] = Enum.KeyCode.Q, ["C"] = Enum.KeyCode.C,
	["V"] = Enum.KeyCode.V, ["F"] = Enum.KeyCode.F, ["G"] = Enum.KeyCode.G,
	["X"] = Enum.KeyCode.X, ["Z"] = Enum.KeyCode.Z, ["T"] = Enum.KeyCode.T,
	["鼠标右键"] = Enum.UserInputType.MouseButton2,
	["鼠标左键"] = Enum.UserInputType.MouseButton1,
}
local holding = false
local toggled = false
local btnHeld = false        -- 手机屏幕按钮是否按住

local function keyDown()
	if Aimbot.HoldButton then
		-- 开了屏幕按钮就以按钮为准（手机上本来也没键盘可按）
		if Aimbot.HoldMode then return btnHeld end
		return toggled
	end
	if Aimbot.HoldKey == "无（一直自瞄）" then return true end
	if Aimbot.HoldMode then return holding end
	return toggled
end

-- 手机用的触发按钮（可拖动，不挡视线）
local touchBtn = Instance.new("TextButton")
touchBtn.Name = "AimbotTrigger"
touchBtn.Size = UDim2.fromOffset(64, 64)
touchBtn.Position = UDim2.new(1, -90, 1, -170)
touchBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
touchBtn.BackgroundTransparency = 0.35
touchBtn.Text = "自瞄"
touchBtn.TextSize = 18
touchBtn.TextColor3 = Color3.fromRGB(235, 235, 235)
touchBtn.Font = Enum.Font.SourceSansBold
touchBtn.AutoButtonColor = false
touchBtn.Visible = false
touchBtn.Active = true
touchBtn.Parent = fovGui
Instance.new("UICorner", touchBtn).CornerRadius = UDim.new(1, 0)
local touchStroke = Instance.new("UIStroke")
touchStroke.Thickness = 2
touchStroke.Color = Color3.fromRGB(255, 255, 255)
touchStroke.Transparency = 0.5
touchStroke.Parent = touchBtn

local btnConns = {}
local function bindBtn(evt, fn)
	btnConns[#btnConns + 1] = evt:Connect(fn)
end
bindBtn(touchBtn.InputBegan, function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		btnHeld = true
		touchBtn.BackgroundTransparency = 0.1
		touchStroke.Transparency = 0.1
		if not Aimbot.HoldMode then toggled = not toggled end
	end
end)
bindBtn(touchBtn.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		btnHeld = false
		touchBtn.BackgroundTransparency = 0.35
		touchStroke.Transparency = 0.5
	end
end)
-- 拖动按钮（长按拖动改位置）
do
	local dragging, dragStart, startPos = false, nil, nil
	bindBtn(touchBtn.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = touchBtn.Position
		end
	end)
	bindBtn(touchBtn.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local d = input.Position - dragStart
			-- 拖动超过 8 像素才算拖，避免误触时按钮乱跑
			if math.abs(d.X) > 8 or math.abs(d.Y) > 8 then
				touchBtn.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
	bindBtn(touchBtn.InputEnded, function()
		dragging = false
	end)
end

-- ============ 主循环 ============
local Step = function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- 手机触发按钮显隐
	local wantBtn = Aimbot.HoldButton and true or false
	if touchBtn.Visible ~= wantBtn then
		touchBtn.Visible = wantBtn
		if not wantBtn then
			btnHeld = false
			touchBtn.BackgroundTransparency = 0.35
			touchStroke.Transparency = 0.5
		end
	end
	if wantBtn then
		local on = keyDown()
		touchStroke.Color = on and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(255, 255, 255)
	end

	-- FOV 圈（电脑跟鼠标，手机固定在屏幕中心）
	if Aimbot.ShowFov then
		local m = aimCenter(cam)
		fovRing.Visible = true
		fovRing.Size = UDim2.fromOffset(Aimbot.Fov * 2, Aimbot.Fov * 2)
		fovRing.Position = UDim2.new(0, m.X, 0, m.Y)
		if locked and locked.Player then
			fovStroke.Color = Color3.fromRGB(255, 210, 90)
			lockLabel.Text = "锁定: " .. locked.Player.Name
		elseif fovStroke.Color ~= Color3.fromRGB(255, 255, 255) then
			fovStroke.Color = Color3.fromRGB(255, 255, 255)
			lockLabel.Text = ""
		end
	elseif fovRing.Visible then
		fovRing.Visible = false
		fovStroke.Color = Color3.fromRGB(255, 255, 255)
		lockLabel.Text = ""
	end

	if not (Aimbot.Enabled and keyDown()) then
		if sensZeroed then unlockSensitivity() end
		locked = nil
		lastSetCF = nil
		cameraFightFrames = 0
		return
	end

	-- 决定这一帧用哪种模式
	local mode = Aimbot.Mode
	if mode == "自动" then
		-- 手机不参与自动切鼠标：手机没有 mousemoverel，切过去等于自瞄失灵
		mode = (mousemoverel and not isMobileNow() and autoSwitched) and "鼠标" or "相机"
	elseif mode == "鼠标" and (isMobileNow() or not mousemoverel) then
		-- 手机上手动选了「鼠标」也没用，直接退回相机模式，别静默失效
		mode = "相机"
	end

	-- 帧首检查：游戏有没有把我们「上一帧」设的朝向掰回去
	-- （必须在这里查，不能在设完相机之后查——那时候刚写进去，永远是「没被抢」）
	-- 手机上不检测：手机没有 mousemoverel，检测出来也没得切
	if mode == "相机" and Aimbot.Mode == "自动" and not isMobileNow()
		and not autoSwitched and lastSetCF then
		if cameraIsFighting(cam) then
			cameraFightFrames = cameraFightFrames + 1
			if cameraFightFrames > 15 then
				autoSwitched = true
				if getgenv().__sutureNotify then
					pcall(getgenv().__sutureNotify, "自瞄", "这个游戏接管了相机，已自动切到鼠标模式")
				end
			end
		else
			cameraFightFrames = math.max(0, cameraFightFrames - 1)
		end
	end

	-- 只有相机模式才锁灵敏度：鼠标模式需要游戏正常响应鼠标移动
	if mode == "相机" then
		lockSensitivity()
	elseif sensZeroed then
		unlockSensitivity()
	end

	local target = getAimTarget(cam)
	if not target or not target.Part then
		return
	end

	local targetPos = target.Part.Position + Vector3.new(0, tonumber(Aimbot.OffsetY) or 0, 0)

	-- 预判
	local lead = tonumber(Aimbot.Prediction) or 0
	if Aimbot.PingComp then
		local ok, ping = pcall(function() return lp:GetNetworkPing() end)
		if ok and type(ping) == "number" then lead = lead + ping * 0.5 end
	end
	if lead > 0 then
		local ok, vel = pcall(function() return target.Part.AssemblyLinearVelocity end)
		if ok and vel then targetPos = targetPos + vel * lead end
	end

	if mode == "鼠标" then
		aimWithMouse(cam, targetPos, dt)
		return
	end

	-- 相机模式
	cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, targetPos), alphaFor(Aimbot.Smooth, dt))
	lastSetCF = cam.CFrame
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, Step)

-- ============ 输入 ============
local inputConns = {}
local function bindInput(evt, fn)
	inputConns[#inputConns + 1] = evt:Connect(fn)
end
local function inputMatches(input)
	local want = KEY_MAP[Aimbot.HoldKey]
	if not want then return false end
	-- 直接两个都比：键盘比 KeyCode，鼠标比 UserInputType。
	-- 鼠标输入的 KeyCode 是 Unknown，不会误判成键盘键
	return input.KeyCode == want or input.UserInputType == want
end
bindInput(UIS.InputBegan, function(input, busy)
	if busy then return end
	if inputMatches(input) then
		holding = true
		if not Aimbot.HoldMode then toggled = not toggled end
	end
end)
bindInput(UIS.InputEnded, function(input)
	if inputMatches(input) then holding = false end
end)
bindInput(lp.CharacterAdded, function()
	holding = false
	btnHeld = false
	locked = nil
	lastSetCF = nil
end)

-- ============ 清理函数 ============
getgenv().__SUTURE_AIMBOT_CLEANUP = function()
	pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
	for _, c in ipairs(inputConns) do pcall(function() c:Disconnect() end) end
	for _, c in ipairs(btnConns) do pcall(function() c:Disconnect() end) end
	unlockSensitivity()
	pcall(function() fovGui:Destroy() end)
end

-- ============ UI ============
local uiOk, uiErr = pcall(function()
	Tab:Toggle({
		Title = "自瞄开关",
		Desc = "开启后按下面设置的按键自瞄（默认一直生效）",
		Type = "Checkbox",
		Value = Aimbot.Enabled or false,
		Callback = function(s) Aimbot.Enabled = s end
	})

	Tab:Dropdown({
		Title = "设备",
		Desc = "当前识别为「" .. AUTO_DEVICE .. "」。自动识别可能出错（蓝牙键鼠、模拟器），错了就手动选",
		Values = { "自动", "电脑", "手机" },
		Value = Aimbot.Device or "自动",
		Callback = function(v) Aimbot.Device = v end
	})

	Tab:Toggle({
		Title = "屏幕按钮触发",
		Desc = "手机默认开：屏幕右下角一个「自瞄」圆钮，按住才自瞄（可拖动）。关掉就回到一直自瞄",
		Type = "Checkbox",
		Value = Aimbot.HoldButton or false,
		Callback = function(s) Aimbot.HoldButton = s end
	})

	Tab:Dropdown({
		Title = "瞄准模式",
		Desc = "自动：先试相机，发现游戏接管了相机就自动切鼠标。手机上「鼠标」模式无效（没有 mousemoverel）",
		Values = { "自动", "相机", "鼠标" },
		Value = Aimbot.Mode or "自动",
		Callback = function(v)
			Aimbot.Mode = v
			autoSwitched = false
			cameraFightFrames = 0
		end
	})

	Tab:Dropdown({
		Title = "触发按键",
		Desc = "按住/切换自瞄的按键",
		Values = { "无（一直自瞄）", "E", "Q", "C", "V", "F", "G", "X", "Z", "T", "鼠标右键", "鼠标左键" },
		Value = Aimbot.HoldKey or "无（一直自瞄）",
		Callback = function(v)
			Aimbot.HoldKey = v
			holding = false
		end
	})

	Tab:Toggle({
		Title = "按住触发",
		Desc = "开：按住按键才自瞄（默认）；关：按一下切换开关",
		Type = "Checkbox",
		Value = Aimbot.HoldMode ~= false,
		Callback = function(s)
			Aimbot.HoldMode = s
			toggled = false
		end
	})

	Tab:Toggle({
		Title = "显示FOV圈",
		Desc = "圈跟着准心走，锁定时变黄并显示锁定目标名字",
		Type = "Checkbox",
		Value = Aimbot.ShowFov or false,
		Callback = function(s) Aimbot.ShowFov = s end
	})

	Tab:Slider({
		Title = "FOV范围",
		Desc = "准心周围多大范围内会锁定目标",
		Step = 10,
		Value = { Min = 10, Max = 700, Default = Aimbot.Fov or 200 },
		Callback = function(v) Aimbot.Fov = tonumber(v) or 200 end
	})

	Tab:Slider({
		Title = "最大距离",
		Desc = "超过该距离不锁定",
		Step = 50,
		Value = { Min = 50, Max = 6000, Default = Aimbot.MaxDistance or 1000 },
		Callback = function(v) Aimbot.MaxDistance = tonumber(v) or 1000 end
	})

	Tab:Dropdown({
		Title = "瞄准部位",
		Desc = "骨架没有 Head 的游戏会自动回退到别的部位",
		Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso", "随机" },
		Value = Aimbot.Part or "Head",
		Callback = function(v)
			Aimbot.Part = v
			locked = nil
		end
	})

	Tab:Slider({
		Title = "瞄准点上下偏移",
		Desc = "打不中头就往正数调（1~3）；某些游戏头判定和模型对不上",
		Step = 0.1,
		Value = { Min = -2, Max = 3, Default = Aimbot.OffsetY or 0 },
		Callback = function(v) Aimbot.OffsetY = tonumber(v) or 0 end
	})

	Tab:Dropdown({
		Title = "优先级",
		Desc = "多个目标时优先锁定谁",
		Values = { "准心优先", "距离优先", "血量低优先" },
		Value = Aimbot.Priority or "准心优先",
		Callback = function(v) Aimbot.Priority = v end
	})

	Tab:Toggle({
		Title = "目标粘滞",
		Desc = "开（推荐）：锁定后不随便换人，准心不抖；关：每帧都选最近的目标",
		Type = "Checkbox",
		Value = Aimbot.Sticky ~= false,
		Callback = function(s) Aimbot.Sticky = s end
	})

	Tab:Slider({
		Title = "换目标难度",
		Desc = "越大越难被抢走锁定（只在「目标粘滞」开启时生效）",
		Step = 0.05,
		Value = { Min = 0, Max = 0.8, Default = Aimbot.SwitchMargin or 0.25 },
		Callback = function(v) Aimbot.SwitchMargin = tonumber(v) or 0.25 end
	})

	Tab:Toggle({
		Title = "队伍检测",
		Desc = "开启后跳过同队玩家",
		Type = "Checkbox",
		Value = Aimbot.TeamCheck or false,
		Callback = function(s) Aimbot.TeamCheck = s end
	})

	Tab:Toggle({
		Title = "穿墙自瞄",
		Desc = "开启后墙挡住就不锁定",
		Type = "Checkbox",
		Value = Aimbot.WallCheck or false,
		Callback = function(s) Aimbot.WallCheck = s end
	})

	Tab:Slider({
		Title = "平滑度",
		Desc = "越大越快越硬，0.99 以上 = 瞬间锁头（帧率无关，手机和高刷屏手感一致）",
		Step = 0.05,
		Value = { Min = 0.05, Max = 1, Default = Aimbot.Smooth or 0.55 },
		Callback = function(v) Aimbot.Smooth = tonumber(v) or 0.55 end
	})

	Tab:Slider({
		Title = "鼠标模式灵敏度",
		Desc = "只在「鼠标」模式下生效：越小转得越猛，太大了会跟不上人",
		Step = 0.5,
		Value = { Min = 0.5, Max = 10, Default = Aimbot.MouseSens or 2 },
		Callback = function(v) Aimbot.MouseSens = tonumber(v) or 2 end
	})

	Tab:Slider({
		Title = "预判(秒)",
		Desc = "0 = 关闭；打移动目标预测它未来的位置",
		Step = 0.05,
		Value = { Min = 0, Max = 1, Default = Aimbot.Prediction or 0.1 },
		Callback = function(v) Aimbot.Prediction = tonumber(v) or 0.1 end
	})

	Tab:Toggle({
		Title = "延迟补偿",
		Desc = "开：按你的延迟自动多预判一点（打移动目标老打空就开这个）",
		Type = "Checkbox",
		Value = Aimbot.PingComp or false,
		Callback = function(s) Aimbot.PingComp = s end
	})

	Tab:Button({
		Title = "重置自瞄设置",
		Desc = "恢复默认（默认就是消抖的那套参数），UI 上的数字要重开脚本才同步",
		Callback = function()
			for k, v in pairs(defaultAimbot) do
				getgenv().SutureAimbot[k] = v
			end
			locked = nil
			autoSwitched = false
			cameraFightFrames = 0
			if getgenv().__sutureNotify then
				pcall(getgenv().__sutureNotify, "自瞄", "已恢复默认设置")
			end
		end
	})

	Tab:Paragraph({
		Title = "自瞄 v2 说明",
		Desc = "抖动修了什么：锁定时把鼠标灵敏度设 0（游戏相机收不到输入，我们写的朝向才留得住）、" ..
			"渲染绑在相机之后执行、锁定后不每帧换目标、平滑改成帧率无关。\n" ..
			"有些游戏没效果：那种游戏有自定义相机，把「瞄准模式」手动改成「鼠标」（手机上没有这个模式）。\n" ..
			"打不中：先调「瞄准点上下偏移」，再调「预判」和「延迟补偿」。\n" ..
			"手机：FOV 圈固定在屏幕中心（手机没有鼠标，GetMouseLocation 拿到的是上次触摸的位置，" ..
			"不修会跑到左上角）；想按住才自瞄就开「屏幕按钮触发」。"
	})
end)

if not uiOk then
	warn("[自瞄类] Tab UI 创建失败:", uiErr)
end
