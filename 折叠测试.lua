-- UI 过渡测试（位移 + 遮罩淡入淡出）独立脚本

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

local TweenService = game:GetService("TweenService")
local lp = game:GetService("Players").LocalPlayer

local win = WindUI:CreateWindow({
	Title = "过渡测试", Icon = "aperture", Author = "by suif", Folder = "SutureHub",
	Size = UDim2.fromOffset(620, 460), MinSize = Vector2.new(560, 350), MaxSize = Vector2.new(900, 600),
	ToggleKey = Enum.KeyCode.RightShift, Transparent = true, Theme = "Dark",
	Resizable = true, SideBarWidth = 160, HideSearchBar = true,
	ScrollBarEnabled = true, NewElements = true,
	User = { Enabled = true, Anonymous = false, Callback = function() print("当前用户:", lp.Name) end }
})

-- ============ 过渡：位移 + 全屏遮罩淡入淡出 ============
local mainParent = win.UIElements.Main.Parent

-- 全屏遮罩（放在窗口后面）
local DimOverlay = Instance.new("Frame")
DimOverlay.Name = "SutureDimOverlay"
DimOverlay.Size = UDim2.fromScale(1, 1)
DimOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
DimOverlay.BackgroundTransparency = 1
DimOverlay.BorderSizePixel = 0
DimOverlay.ZIndex = 0
DimOverlay.Parent = mainParent

local SLIDE = 24 -- 下滑像素
local lastPos = nil
local posTween = nil
local dimTween = nil

local function setWindowVisible(visible)
	pcall(function()
		if not (win.UIElements and win.UIElements.Main) then return end
		if posTween then posTween:Cancel() posTween = nil end
		if dimTween then dimTween:Cancel() dimTween = nil end

		if visible then
			local target = lastPos or UDim2.new(0.5, 0, 0.5, 0)
			win.UIElements.Main.Visible = true
			local content = win.UIElements.Main:FindFirstChild("Main")
			if content then content.Visible = true end

			-- 从下方 24px 滑回原位
			win.UIElements.Main.Position = UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale, target.Y.Offset + SLIDE)
			posTween = TweenService:Create(win.UIElements.Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target })
			posTween:Play()

			-- 遮罩淡入
			DimOverlay.Visible = true
			dimTween = TweenService:Create(DimOverlay, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.5 })
			dimTween:Play()

			-- 保险：tween 没生效也强制还原
			task.delay(0.3, function()
				pcall(function()
					if win.UIElements and win.UIElements.Main then
						win.UIElements.Main.Position = target
					end
				end)
			end)
		else
			lastPos = win.UIElements.Main.Position
			local target = UDim2.new(lastPos.X.Scale, lastPos.X.Offset, lastPos.Y.Scale, lastPos.Y.Offset + SLIDE)

			posTween = TweenService:Create(win.UIElements.Main, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target })
			posTween.Completed:Connect(function()
				if win.Closed then
					pcall(function()
						win.UIElements.Main.Visible = false
						local content = win.UIElements.Main:FindFirstChild("Main")
						if content then content.Visible = false end
					end)
				end
			end)
			posTween:Play()

			dimTween = TweenService:Create(DimOverlay, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
			dimTween.Completed:Connect(function()
				if win.Closed then
					DimOverlay.Visible = false
				end
			end)
			dimTween:Play()

			-- 保险：tween 没跑完也强制隐藏
			task.delay(0.25, function()
				if win.Closed then
					pcall(function()
						win.UIElements.Main.Visible = false
					end)
					DimOverlay.Visible = false
				end
			end)
		end
	end)
end

function win:Open(...)
	if win.Destroyed then return end
	if win.OnOpenCallback then
		task.spawn(function() pcall(win.OnOpenCallback) end)
	end
	win.Closed = false
	win.CanDropdown = true
	win.CanResize = win.Resizable ~= false
	setWindowVisible(true)
	if win.OpenButtonMain and win.IsOpenButtonEnabled then
		pcall(function() win.OpenButtonMain:Visible(false) end)
	end
end

function win:Close(...)
	if win.Destroyed then return end
	if win.OnCloseCallback then
		task.spawn(function() pcall(win.OnCloseCallback) end)
	end
	win.Closed = true
	win.CanDropdown = false
	setWindowVisible(false)
	if win.OpenButtonMain and win.IsOpenButtonEnabled then
		pcall(function() win.OpenButtonMain:Visible(true) end)
	end
end
-- ==============================================================

local tab1 = win:Tab({ Title = "功能一", Icon = "user", Locked = false })
local tab2 = win:Tab({ Title = "功能二", Icon = "user", Locked = false })
tab1:Select()

for _, tab in ipairs({tab1, tab2}) do
	for i = 1, 20 do
		tab:Button({
			Title = "测试按钮 " .. i, Desc = "压测按钮", Icon = "shell",
			Callback = function() end
		})
	end
	for i = 1, 5 do
		tab:Toggle({
			Title = "测试开关 " .. i, Desc = "开关描述", Type = "Checkbox", Value = false,
			Callback = function() end
		})
	end
	tab:Slider({
		Title = "测试拉条", Step = 1, Value = { Min = 0, Max = 100, Default = 50 },
		Callback = function() end
	})
	tab:Slider({
		Title = "测试拉条2", Step = 1, Value = { Min = 0, Max = 100, Default = 30 },
		Callback = function() end
	})
end

print("[过渡测试] 已加载，按 RightShift 开关窗口")
