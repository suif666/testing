-- 自瞄类 远程脚本 v3（解决屏幕抽搐 / 锁不住人）
--
-- 依赖主脚本提供 AimbotTab：getgenv().Tabs.AimbotTab 或 getgenv().SutureAimbotTab
--
-- ── 抽搐的六个原因与对策（v1 版全中，v3 逐个修）──
--   1. 直接写 Camera.CFrame，游戏的 CameraModule 在同一帧稍后又算回去 → 帧级拉锯 = 抽搐
--      对策 A：改转「角色」（HumanoidRootPart + AutoRotate=false），相机是游戏自己在跟随，
--              没有任何人跟它抢 —— 这是落叶 Forsaken 自瞄用的路子，最稳
--      对策 B：转相机模式用 BindToRenderStep 绑到 RenderPriority.Camera + 1，保证比相机晚跑
--      对策 C：转相机模式可选冻结鼠标视角（默认关，靠优先级就已经不抖）
--   2. 每帧重新选目标，两个目标分数接近 / 目标在 FOV 边缘 → 视角左右来回翻转
--      对策：候选表 0.5 秒缓存 + 锁定时长 + 换目标必须新目标明显更优（默认 30%）
--   3. 裸 Lerp 按帧插值 → 240Hz 比 60Hz 快 4 倍，高刷屏上又急又抖
--      对策：指数逼近 alpha = 1 - exp(-rate * dt)，帧率无关
--   4. 「随机」部位每帧重抽，瞄准点在头/躯干之间跳
--      对策：锁定瞬间抽一次，整个锁定期内固定
--   5. 俯仰过冲振荡（目标跳/被打飞时最明显）
--      对策：转角色时 Y 分量抹成 0，只修水平偏航；转相机时钳制 pitch
--   6. 准星已经在目标身上仍继续微调 → 高频细抖
--      对策：死区，屏幕像素误差小于阈值就不动
--   7. 锁上以后拉不开（吸附力度滑块无效）
--      旧版吸附力度只是把速度乘 0.5~2 倍，而平滑度是 1~30 倍，被淹没；且无论调多少，
--      瞄准最终都会完全收敛到目标身上，所以必然被拽回去。
--      对策：吸附力度改成真正的强度混合（0=不吸）；再加「跟手程度」，
--            检测到玩家自己在转视角就把自瞄压下去，松手恢复。
--
-- ── 保留 v1 的全部选项与默认值，设置不会丢（getgenv().SutureAimbot）──
-- ── 回退：存档/自瞄/ 里有历史版本 ──

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local plrs = Players

-- 重复执行保护
-- v1 是直接 return —— 结果是主脚本重新加载时新版本永远不会生效，只能重启游戏。
-- 现在改成：先解绑上一次的渲染绑定、跑一次清理函数，再往下走。
if getgenv().__SUTURE_AIMBOT_LOADED then
	pcall(function() RunService:UnbindFromRenderStep("SutureAimbot") end)
	local cleanup = getgenv().__SUTURE_AIMBOT_CLEANUP
	if type(cleanup) == "function" then
		pcall(cleanup)
	end
end
getgenv().__SUTURE_AIMBOT_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.AimbotTab) or getgenv().SutureAimbotTab
if not Tab then
	warn("[自瞄类] 未找到 AimbotTab，请检查主脚本是否正确赋值")
	return
end

-- ============ 配置 ============
-- 保留 v1 的所有键与默认值，新增 v3 的键（老配置不会丢，新键补默认值）
local defaultAimbot = {
	-- v1 原有
	Enabled = false, ShowFov = false, Fov = 200, MaxDistance = 1000,
	Part = "Head", TeamCheck = false, WallCheck = false,
	Smooth = 0.8, Prediction = 0.1,
	LockStrength = 0.5, Priority = "准心优先",
	-- v3 新增
	Method = "转角色（推荐）",   -- 转角色 / 转相机
	LockMouse = false,          -- 转相机模式下是否冻结鼠标视角（默认关：靠渲染优先级就够了）
	PullAway = 70,              -- 玩家自己转视角时，自瞄减弱多少 %（跟手程度）
	LockTime = 0.35,            -- 锁定后多久才允许换目标
	SwitchGain = 30,            -- 新目标要比当前优多少 % 才换
	Deadzone = 6,               -- 屏幕像素死区
	YawOnly = true,             -- 只转水平（转角色时强制开）
}
getgenv().SutureAimbot = getgenv().SutureAimbot or {}
for k, v in pairs(defaultAimbot) do
	if getgenv().SutureAimbot[k] == nil then
		getgenv().SutureAimbot[k] = v
	end
end
local Aimbot = getgenv().SutureAimbot

-- ============ FOV 圈（UI 版圆环）============
-- 注意：必须 IgnoreGuiInset = true + 百分比居中，否则手机上会偏下（v1 踩过的坑）
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "AimbotFOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
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

-- ============ 状态 ============
local lock = {
	target = nil,      -- 当前锁定的角色
	part = nil,        -- 锁定的部位（随机部位在锁定时抽一次）
	partName = nil,
	lockedAt = 0,
	cache = {},        -- 候选表
	cacheAt = -1e9,    -- 负无穷：保证第一帧就扫描（写 0 的话若 tick 从 0 起，开局 0.5 秒内会空转）
	cacheLife = 0.5,   -- 候选表刷新间隔（秒）
	hum = nil,
	savedAutoRotate = nil,
	diedConn = nil,
}
local savedMouseSensitivity = nil   -- 转相机模式要还原的鼠标灵敏度
-- 玩家输入检测：不依赖鼠标/触摸事件，任何设备都能用
-- 原理：记下我们上一帧写下的相机朝向，下一帧相机模块的输出与之的差值，就是玩家自己转的那部分角度
local lookRef = nil
local inputUntil = 0

local PART_POOL = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }

local function getMyChar()
	local c = lp.Character
	if not c or not c.Parent then return nil end
	return c
end

local function getAimPart(character, partName)
	if not character then return nil end
	if partName == "随机" then
		return character:FindFirstChild(PART_POOL[math.random(1, #PART_POOL)])
	end
	return character:FindFirstChild(partName)
end

-- 目标是否可见（射线首个命中体必须是目标本身）
local function isVisible(myChar, targetChar, partPos)
	local cam = workspace.CurrentCamera
	if not cam then return false end
	local origin = cam.CFrame.Position
	local dirVec = partPos - origin
	local dist = dirVec.Magnitude
	if dist <= 0 then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { myChar, targetChar }
	params.IgnoreWater = true
	local ray = workspace:Raycast(origin, dirVec.Unit * dist, params)
	if not ray or not ray.Instance then return true end
	local hit = ray.Instance
	if hit:IsDescendantOf(targetChar) then return true end
	return hit.Transparency >= 0.9
end

-- 评分：越小越好。屏幕距² 权重高，世界距² 权重低（参考 Moonlua 的加权）
local function scoreOf(screenDist, worldDist, range)
	local a = (screenDist / math.max(1, Aimbot.Fov)) ^ 2 * 1.55
	local b = (worldDist / math.max(1, range)) ^ 2 * 0.35
	return a + b
end

-- 刷新候选表（每 cacheLife 秒一次，不是每帧）
local function refreshCache()
	local now = tick()
	if now - lock.cacheAt < lock.cacheLife then return end
	lock.cacheAt = now

	local cam = workspace.CurrentCamera
	local myChar = getMyChar()
	if not cam or not myChar then
		lock.cache = {}
		return
	end

	local center = cam.ViewportSize / 2
	local list = {}

	for _, p in ipairs(plrs:GetPlayers()) do
		if p ~= lp then
			local char = p.Character
			local keep = char and char.Parent
			-- 当前锁定目标永不淘汰（防止它在别人被扫描到时掉出候选表）
			if keep or (lock.target and p.Character == lock.target) then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local sameTeam = Aimbot.TeamCheck and p.Team and lp.Team and p.Team == lp.Team
					if not sameTeam then
						local partName = lock.partName or Aimbot.Part
						local part = getAimPart(char, partName)
						if part then
							local pos, onScreen = cam:WorldToViewportPoint(part.Position)
							if onScreen then
								local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
								local worldDist = (cam.CFrame.Position - part.Position).Magnitude
								-- 当前目标放宽 1.5 倍 FOV / 1.2 倍距离，避免在边缘反复掉出
								local isCurrent = (char == lock.target)
								local fovLimit = Aimbot.Fov * (isCurrent and 1.5 or 1)
								local distLimit = Aimbot.MaxDistance * (isCurrent and 1.2 or 1)
								if screenDist <= fovLimit and worldDist <= distLimit then
									local visible = true
									if Aimbot.WallCheck then
										visible = isVisible(myChar, char, part.Position)
									end
									if visible then
										table.insert(list, {
											char = char,
											hum = hum,
											part = part,
											screenDist = screenDist,
											score = scoreOf(screenDist, worldDist, Aimbot.MaxDistance),
											priority = (Aimbot.Priority == "血量低优先" and hum.Health)
												or (Aimbot.Priority == "距离优先" and worldDist)
												or screenDist,
										})
									end
								end
							end
						end
					end
				end
			end
		end
	end

	table.sort(list, function(x, y) return x.priority < y.priority end)
	lock.cache = list
end

-- 解锁：必须干净交还控制权，不能持续对抗
local function unlockTarget()
	if lock.diedConn then
		pcall(function() lock.diedConn:Disconnect() end)
		lock.diedConn = nil
	end
	if lock.hum and lock.hum.Parent and lock.savedAutoRotate ~= nil then
		pcall(function() lock.hum.AutoRotate = lock.savedAutoRotate end)
	end
	lock.target = nil
	lock.part = nil
	lock.hum = nil
	lock.savedAutoRotate = nil
end

-- 锁定目标：只在换目标时执行，不是每帧
local function lockTarget(cand)
	if lock.target == cand.char and lock.part == cand.part then
		return
	end
	unlockTarget()
	lock.target = cand.char
	lock.part = cand.part
	lock.lockedAt = tick()
	lock.hum = cand.hum
	if cand.hum then
		lock.savedAutoRotate = cand.hum.AutoRotate
		pcall(function() cand.hum.AutoRotate = false end)
		pcall(function()
			lock.diedConn = cand.hum.Died:Connect(function()
				if lock.target == cand.char then unlockTarget() end
			end)
		end)
	end
end

-- 候选是否仍然有效：部件被移除 / 目标死亡或离开了都要剔除。
-- 不剔除的话，失效记录会一直排在候选表首位，主循环每次都选中它又立刻解锁，
-- 结果就是锁定目标死后自瞄"卡住"最多 0.5 秒（等下次缓存刷新）才去找下一个。
local function candValid(c)
	return c and c.part and c.part.Parent and c.char and c.char.Parent
		and c.hum and c.hum.Health > 0
end

-- 从候选表里挑目标：锁定期内不换，之后需要明显更优才换
local function pickTarget()
	local valid = {}
	for _, c in ipairs(lock.cache) do
		if candValid(c) then
			table.insert(valid, c)
		end
	end
	if #valid == 0 then return nil end

	-- 当前目标还在有效候选里吗？
	local current = nil
	if lock.target then
		for _, c in ipairs(valid) do
			if c.char == lock.target then current = c break end
		end
	end

	-- 当前目标死了/被移除/跑出范围 → 立刻换人，不傻等锁定期
	if not current then
		return valid[1]
	end

	-- 锁定期内死守当前目标
	if tick() - lock.lockedAt < (tonumber(Aimbot.LockTime) or 0.35) then
		return current
	end

	-- 锁定期过了：新目标要优出 SwitchGain% 才换（迟滞，压住左右横跳）
	-- 用 score 算相对优势：屏幕距²×1.55 + 世界距²×0.35，恒正且各优先级之间可比
	local best = valid[1]
	if best and best.char ~= current.char then
		local cur = math.max(1e-3, current.score)
		local gain = (cur - best.score) / cur * 100
		if gain >= (tonumber(Aimbot.SwitchGain) or 30) then
			return best
		end
	end
	return current
end

-- ============ 鼠标视角冻结（可选）============
-- 说明：转相机模式把绑定挂到 RenderPriority.Camera + 1，已经是每帧最后一次写相机，
-- 单靠这个就不会被相机模块抢回去。把 MouseDeltaSensitivity 归零是"更彻底"的做法，
-- 但副作用是玩家自己转不了视角 —— 所以做成开关，默认关闭。
local function applyMouseLock(want)
	if want then
		if savedMouseSensitivity == nil then
			savedMouseSensitivity = UIS.MouseDeltaSensitivity
		end
		if UIS.MouseDeltaSensitivity ~= 0 then
			pcall(function() UIS.MouseDeltaSensitivity = 0 end)
		end
	elseif savedMouseSensitivity ~= nil then
		pcall(function() UIS.MouseDeltaSensitivity = savedMouseSensitivity end)
		savedMouseSensitivity = nil
	end
end

local function restoreAll()
	unlockTarget()
	applyMouseLock(false)
end

-- ============ 主循环 ============
-- BindToRenderStep + Camera.Value + 1：保证在游戏相机模块之后跑，最后一次写入是我们的
local function aimLoop(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- 玩家是否正在自己转视角
	local now = tick()
	local camLook = cam.CFrame.LookVector
	if lookRef then
		local dot = lookRef:Dot(camLook)
		if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
		local movedDeg = math.deg(math.acos(dot))
		-- 阈值 0.3 度/帧（60fps 约 18 度/秒）：正常拖视角会超，相机模块自身的惯性不会
		if movedDeg > 0.3 then
			inputUntil = now + 0.15
		end
	end
	lookRef = camLook   -- 默认基线；若本帧稍后写了相机，末尾会再更新一次

	-- FOV 圈：只跟「显示FOV圈」绑定
	if Aimbot.ShowFov then
		pcall(function()
			fovRing.Visible = true
			fovRing.Size = UDim2.fromOffset(Aimbot.Fov * 2, Aimbot.Fov * 2)
			fovRing.Position = UDim2.new(0.5, 0, 0.5, 0)
		end)
	elseif fovRing.Visible then
		fovRing.Visible = false
	end

	if not Aimbot.Enabled then
		unlockTarget()
		applyMouseLock(false)
		return
	end

	local myChar = getMyChar()
	if not myChar then
		unlockTarget()
		return
	end

	-- 「随机」部位：只抽一次，之后整个锁定期固定
	-- （v1 是每帧 math.random，瞄准点在头/躯干/HRP 之间乱跳，这是抽搐的一大来源）
	if Aimbot.Part == "随机" then
		if not lock.partName then
			lock.partName = PART_POOL[math.random(1, #PART_POOL)]
		end
	else
		lock.partName = Aimbot.Part
	end

	refreshCache()
	local cand = pickTarget()
	if not cand or not cand.part or not cand.part.Parent then
		unlockTarget()
		return
	end

	-- 进锁定态（换目标时才真正执行内部逻辑）
	lockTarget(cand)

	local targetPos = cand.part.Position
	if Aimbot.Prediction > 0 then
		targetPos = targetPos + cand.part.AssemblyLinearVelocity * Aimbot.Prediction
	end

	-- 死区：准星已经在目标身上就别再微调，否则就是高频细抖
	-- 注意 Deadzone = 0 表示「关闭死区」，不能写成 screenDist <= 0 —— 否则瞄准正中时会被误判成"已在死区内"
	local dz = tonumber(Aimbot.Deadzone) or 0
	if dz > 0 then
		local screenPos = cam:WorldToViewportPoint(targetPos)
		local center = cam.ViewportSize / 2
		local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
		if screenDist <= dz then
			return
		end
	end

	-- 帧率无关的指数逼近：60Hz 和 240Hz 收敛速度一致，且永不过冲
	local speed = 1 + (tonumber(Aimbot.Smooth) or 0.8) * 29
	local alpha = 1 - math.exp(-speed * math.clamp(dt, 0, 0.1))

	-- 吸附力度 = 真正的强度混合（旧版只是把速度乘 0.5~2 倍，被平滑度淹没了，等于没用）
	--   0 = 完全不吸（自瞄失效），1 = 全速锁（配合平滑度）
	local strength = math.clamp(tonumber(Aimbot.LockStrength) or 0.5, 0, 1)
	alpha = alpha * strength

	-- 跟手：玩家自己在转视角时把自瞄压下去，松手后自动恢复
	if now < inputUntil then
		local pull = math.clamp((tonumber(Aimbot.PullAway) or 70) / 100, 0, 1)
		alpha = alpha * (1 - pull)
	end

	if alpha > 1 then alpha = 1 end
	if alpha <= 0 then return end

	local method = Aimbot.Method or "转角色（推荐）"
	if method == "转角色（推荐）" then
		---------- 转角色：相机是游戏自己在跟随，不存在抢占 ----------
		applyMouseLock(false)
		local hrp = myChar:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- Y 抹成 0：只修水平偏航，绝不动俯仰 → 目标跳/被打飞不会引起俯仰过冲
		local dx = targetPos.X - hrp.Position.X
		local dz = targetPos.Z - hrp.Position.Z
		if math.abs(dx) + math.abs(dz) < 0.05 then return end
		local flat = Vector3.new(dx, 0, dz).Unit
		local want = CFrame.new(hrp.Position, hrp.Position + flat)
		pcall(function()
			hrp.CFrame = hrp.CFrame:Lerp(want, alpha)
		end)
	else
		---------- 转相机：绑定在相机之后，是这一帧最后一次写相机 ----------
		applyMouseLock(Aimbot.LockMouse == true)
		local targetCF = CFrame.new(cam.CFrame.Position, targetPos)

		-- 钳制 pitch 在 ±80 度，杜绝过冲翻转
		local look = targetCF.LookVector
		local flatLen = math.sqrt(look.X * look.X + look.Z * look.Z)
		local pitch = math.deg(math.atan(look.Y, flatLen))
		if pitch > 80 or pitch < -80 then
			local clamped = math.clamp(pitch, -80, 80)
			local yaw = math.atan(-look.X, -look.Z)
			local cp = math.cos(math.rad(clamped))
			local dir = Vector3.new(-math.sin(yaw) * cp, math.sin(math.rad(clamped)), -math.cos(yaw) * cp)
			targetCF = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + dir)
		end

		pcall(function()
			cam.CFrame = cam.CFrame:Lerp(targetCF, alpha)
		end)
		-- 更新基线为我们刚写下的朝向：下一帧的差值就只剩玩家自己转的那部分
		lookRef = cam.CFrame.LookVector
	end
end

RunService:BindToRenderStep("SutureAimbot", Enum.RenderPriority.Camera.Value + 1, aimLoop)

-- 复活/换角色时重置锁定
lp.CharacterAdded:Connect(function()
	unlockTarget()
	lock.cache = {}
	lock.cacheAt = 0
end)

-- ============ UI（保留 v1 全部选项，新增 v3 的）============
local uiOk, uiErr = pcall(function()
	Tab:Toggle({
		Title = "自瞄开关",
		Desc = "开启后一直自动瞄准",
		Type = "Checkbox",
		Value = Aimbot.Enabled or false,
		Callback = function(s)
			Aimbot.Enabled = s
			if not s then restoreAll() end
		end
	})

	Tab:Toggle({
		Title = "显示FOV圈",
		Desc = "屏幕中心显示瞄准范围圈",
		Type = "Checkbox",
		Value = Aimbot.ShowFov or false,
		Callback = function(s)
			Aimbot.ShowFov = s
			if not s and fovRing then
				fovRing.Visible = false
			end
		end
	})

	Tab:Dropdown({
		Title = "瞄准方式",
		Desc = "转角色最稳（相机没人抢）；转相机保留自由视角；某个游戏不生效就换另一个",
		Values = { "转角色（推荐）", "转相机" },
		Value = Aimbot.Method or "转角色（推荐）",
		Callback = function(v)
			Aimbot.Method = v
			unlockTarget()
			lock.cache = {}
			lock.cacheAt = 0
		end
	})

	Tab:Toggle({
		Title = "冻结鼠标视角",
		Desc = "仅转相机模式有效。开启后自瞄期间无法自己转视角（否则不需要开，渲染优先级已经能防抢）",
		Type = "Checkbox",
		Value = Aimbot.LockMouse or false,
		Callback = function(s2)
			Aimbot.LockMouse = s2
			if not s2 then applyMouseLock(false) end
		end
	})

	Tab:Slider({
		Title = "FOV范围",
		Desc = "屏幕中心多大范围内会锁定目标",
		Step = 10,
		Value = { Min = 10, Max = 700, Default = Aimbot.Fov or 200 },
		Callback = function(v)
			Aimbot.Fov = tonumber(v) or 200
		end
	})

	Tab:Slider({
		Title = "最大距离",
		Desc = "超过该距离不锁定（米）",
		Step = 50,
		Value = { Min = 50, Max = 6000, Default = Aimbot.MaxDistance or 1000 },
		Callback = function(v)
			Aimbot.MaxDistance = tonumber(v) or 1000
		end
	})

	Tab:Dropdown({
		Title = "瞄准部位",
		Values = { "Head", "HumanoidRootPart", "随机" },
		Value = Aimbot.Part or "Head",
		Callback = function(v)
			Aimbot.Part = v
			lock.partName = nil
			unlockTarget()
		end
	})

	Tab:Dropdown({
		Title = "优先级",
		Desc = "多个目标时优先锁定谁",
		Values = { "血量低优先", "距离优先", "准心优先" },
		Value = Aimbot.Priority or "准心优先",
		Callback = function(v)
			Aimbot.Priority = v
			lock.cache = {}
			lock.cacheAt = 0
		end
	})

	Tab:Slider({
		Title = "锁定时间(秒)",
		Desc = "锁定后多久内不换目标。调大能明显压住左右横跳",
		Step = 0.05,
		Value = { Min = 0.05, Max = 1.5, Default = Aimbot.LockTime or 0.35 },
		Callback = function(v)
			Aimbot.LockTime = tonumber(v) or 0.35
		end
	})

	Tab:Slider({
		Title = "换目标门槛(%)",
		Desc = "新目标要比当前目标优出这么多才换。调大更稳，调小更跟手",
		Step = 5,
		Value = { Min = 0, Max = 100, Default = Aimbot.SwitchGain or 30 },
		Callback = function(v)
			Aimbot.SwitchGain = tonumber(v) or 30
		end
	})

	Tab:Toggle({
		Title = "队伍检测",
		Desc = "开启后跳过同队玩家",
		Type = "Checkbox",
		Value = Aimbot.TeamCheck or false,
		Callback = function(s)
			Aimbot.TeamCheck = s
			lock.cache = {}
			lock.cacheAt = 0
		end
	})

	Tab:Toggle({
		Title = "穿墙自瞄",
		Desc = "开启后有墙挡住就不会锁定",
		Type = "Checkbox",
		Value = Aimbot.WallCheck or false,
		Callback = function(s)
			Aimbot.WallCheck = s
			lock.cache = {}
			lock.cacheAt = 0
		end
	})

	Tab:Slider({
		Title = "平滑度",
		Desc = "越低越平滑，1 = 瞬间转向（已改成帧率无关）",
		Step = 0.05,
		Value = { Min = 0.1, Max = 1, Default = Aimbot.Smooth or 0.8 },
		Callback = function(v)
			Aimbot.Smooth = tonumber(v) or 0.8
		end
	})

	Tab:Slider({
		Title = "吸附力度",
		Desc = "自瞄的强度：0 = 完全不吸（等于关掉），10 = 全速锁死。拉不开准星就调小",
		Step = 1,
		Value = { Min = 0, Max = 10, Default = math.floor((Aimbot.LockStrength or 0.5) * 10) },
		Callback = function(v)
			Aimbot.LockStrength = (tonumber(v) or 5) / 10
		end
	})

	Tab:Slider({
		Title = "跟手程度(%)",
		Desc = "你自己转视角时自瞄减弱多少：0 = 自瞄不让位（最难拉开），100 = 完全让位（最好拉）",
		Step = 5,
		Value = { Min = 0, Max = 100, Default = Aimbot.PullAway or 70 },
		Callback = function(v)
			Aimbot.PullAway = tonumber(v) or 70
		end
	})

	Tab:Slider({
		Title = "预判(秒)",
		Desc = "0 = 关闭；预测移动目标的位置",
		Step = 0.05,
		Value = { Min = 0, Max = 1, Default = Aimbot.Prediction or 0.1 },
		Callback = function(v)
			Aimbot.Prediction = tonumber(v) or 0.1
		end
	})

	Tab:Slider({
		Title = "死区(像素)",
		Desc = "准星离目标小于这个距离就不动它，消除贴身细抖。0 = 关闭",
		Step = 1,
		Value = { Min = 0, Max = 40, Default = Aimbot.Deadzone or 6 },
		Callback = function(v)
			Aimbot.Deadzone = tonumber(v) or 6
		end
	})
end)

if not uiOk then
	warn("[自瞄类] Tab UI 创建失败:", uiErr)
end

print("[自瞄类] v3 已加载（转角色/转相机双模式 + 目标粘滞 + 帧率无关平滑）")
