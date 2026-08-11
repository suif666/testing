-- UI 弹入动画测试（独立脚本）
-- 几十个按钮模拟大 Hub，验证 UIScale 弹入是否卡顿

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
	Title = "弹入测试", Icon = "aperture", Author = "by suif", Folder = "SutureHub",
	Size = UDim2.fromOffset(620, 460), MinSize = Vector2.new(560, 350), MaxSize = Vector2.new(900, 600),
	ToggleKey = Enum.KeyCode.RightShift, Transparent = true, Theme = "Dark",
	Resizable = true, SideBarWidth = 160, HideSearchBar = true,
	ScrollBarEnabled = true, NewElements = true,
	User = { Enabled = true, Anonymous = false, Callback = function() print("当前用户:", lp.Name) end }
})

-- ============ UIScale 弹入/弹开（同主脚本方案） ============
local PopScale = Instance.new("UIScale")
PopScale.Name = "SuturePopScale"
PopScale.Scale = 1
PopScale.Parent = win.UIElements.Main
local popTween = nil

local function setWindowVisible(visible)
	pcall(function()
		if win.UIElements and win.UIElements.Main then
			if popTween then
				popTween:Cancel()
				popTween = nil
			end
			if visible then
				win.UIElements.Main.Visible = true
				local content = win.UIElements.Main:FindFirstChild("Main")
				if content then
					content.Visible = true
				end
				PopScale.Scale = 0.92
				popTween = TweenService:Create(PopScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				popTween:Play()
			else
				popTween = TweenService:Create(PopScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.96 })
				popTween.Completed:Connect(function()
					pcall(function()
						win.UIElements.Main.Visible = false
						local content = win.UIElements.Main:FindFirstChild("Main")
						if content then
							content.Visible = false
						end
					end)
				end)
				popTween:Play()
				task.delay(0.15, function()
					pcall(function()
						win.UIElements.Main.Visible = false
					end)
				end)
			end
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

-- 每个 tab 塞 20 个按钮 + 5 个开关 + 2 个拉条，模拟大 Hub
for _, tab in ipairs({tab1, tab2}) do
	for i = 1, 20 do
		tab:Button({
			Title = "测试按钮 " .. i, Desc = "用来压测重排的按钮", Icon = "shell",
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

print("[弹入测试] 已加载，按 RightShift 开关窗口")
