local ADDON_CONFIG = {
	IncludeAddedFeatures = true, -- 包含 mspaint 开发者官方新增的功能
	SeparateTabForAddon = true, -- 在 mspaint 窗口中创建名为 Tplay 的插件的独立标签页（顺便说下，因为这个配置，Tplay 的插件中的开关和按键绑定值才能正确加载）
	AltFeatures = true, -- 创建 mspaint 中已存在的功能的替代实现（可能比 mspaint 原功能更优化）
	Debug = false,
}

-- config won't change unless you unload mspaint or just modify getgenv()._TPLAYS_ADDON_CONFIG
ADDON_CONFIG = getgenv()._TPLAYS_ADDON_CONFIG or ADDON_CONFIG
getgenv()._TPLAYS_ADDON_CONFIG = ADDON_CONFIG

function log(...)
	if ADDON_CONFIG.Debug then
		local text = table.concat({...}, " ")
		Library:Notify({
			Title = "Tplay 的插件 [调试]",
			Description = text,
			Time = math.clamp(#text/10, 2, 10)
		})
	end
end

function logprint(...)
	if ADDON_CONFIG.Debug then
		print(...)
	end
end

local Info, Variables, prefix, loaded = {}, {}, "", false

Info.AddonName = 'TplaysAddon'
Info.AddonTitle = "Tplay's Addon"
Info.AddonVersion = '2.4.0'

Info.AddonFullTitle = `{Info.AddonTitle} ({Info.AddonVersion})`

mspaint.AddonInfo = {
	Name = Info.AddonName,
	Title = Info.AddonFullTitle,
	Game = "*"
}

prefix = ADDON_CONFIG.SeparateTabForAddon and Info.AddonName:lower().."_" or ""

if getgenv()._TPLAYS_ADDON_VALUES then
	getgenv()._TPLAYS_ADDON_VALUES.Reload.Value = true
	if getgenv()._TPLAYS_ADDON_VALUES.Loaded.Value then
		getgenv()._TPLAYS_ADDON_VALUES.Loaded:GetPropertyChangedSignal("Value"):Wait()
	end
end

--wow its 'missing' function from infinite yield
function func(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

function GetFunction(fn: string, e: boolean, fs: Instance): (any) -> any
	local success, result = pcall(function()
		local result = filtergc("function", {
			Name = fn,
			IgnoreExecutor = not e,
		}, true)
		if typeof(result) == "table" and typeof(fs) == "Instance" and fs:IsA("Script") then
			for _, func in result do
				local info = debug.getinfo(func)
				if func.short_src == fs:GetFullName() then
					return func
				end
			end
		end
		return result
	end)
	return success and result
end

local oldestmethods = {}

setupvalue = func("function", debug.setupvalue or setupvalue)
readfile = func("function", readfile, function() return "" end)
writefile = func("function", writefile, function() end)
delfile = func("function", delfile, function() end)
isfile = func("function", isfile, function() end)
makefolder = func("function", makefolder, function() end)
listfiles = func("function", listfiles, function() return {} end)
cloneref = func("function", cloneref, function(...) return ... end)
isfunctionhooked = func("function", isfunctionhooked, function(...) return end)
getrawmetatable = func("function", getrawmetatable or get_raw_metatable, function(...) return end)
setreadonly = func("function", setreadonly or set_read_only)
getnamecallmethod = func("function", getnamecallmethod or get_namecall_method)
checkcaller = func("function", checkcaller or check_caller, function(...) return end)
restoremetamethod = func("function", restoremetamethod or restore_meta_method, getrawmetatable(game) and setreadonly and function(object, method)
	local oldestmethod = oldestmethods[object] and oldestmethods[object][method]
	if oldestmethod then
		local metatable = getrawmetatable(object)
		setreadonly(metatable, false)
		metatable[method] = oldestmethod
		setreadonly(metatable, true)
		oldestmethods[object][method] = nil
	end
end)
_hookmetamethod = func("function", hookmetamethod or hook_meta_method, getrawmetatable(game) and setreadonly and function(object, method, func)
	local metatable = getrawmetatable(object)
	local oldmethod = metatable[method]
	setreadonly(metatable, false)
	metatable[method] = func
	setreadonly(metatable, true)
	return oldmethod
end)

hookmetamethod = _hookmetamethod and function(object: Object, method: string, func: (any) -> any)
	local result = _hookmetamethod(object, method, func)
	if result and not (oldestmethods[object] and oldestmethods[object][method]) then
		oldestmethods[object] = oldestmethods[object] or {}
		oldestmethods[object][method] = result
	end
	return result
end

isnetworkowner = func("function", isnetworkowner, gethiddenproperty and function(part)
    local val = gethiddenproperty(part, "NetworkOwnerV3")
    return val == -1 or val == 4
end)

local function restoremetamethods()
	if not hookmetamethod then
		oldestmethods = nil
		return
	end
	for object, methods in oldestmethods do
		for methodName, method in methods do
			pcall(restoremetamethod, object, methodName)
		end
	end
	oldestmethods = nil
end

Services = setmetatable({}, {
	__index = function(self, name)
		return cloneref(game:GetService(name))
	end
})

function genName()
	local str = ""
	for _ = 1,64 do
		str ..= string.char(math.random(33,126))
	end
	return str
end

local Toggles = {}
local KeyPickers = {}

local ReloadSignals
if debug.setinfo then
	if getgenv()._TPLAYS_ADDON_VALUES then
		for _, bool in getgenv()._TPLAYS_ADDON_VALUES do
			bool:Destroy()
		end
		getgenv()._TPLAYS_ADDON_VALUES = nil
	end
	getgenv()._TPLAYS_ADDON_VALUES = {
		Loaded = Instance.new("BoolValue"),
		Reload = Instance.new("BoolValue")
	}
	getgenv()._TPLAYS_ADDON_VALUES.Loaded.Value = true
	ReloadSignals = {}
end

local function destroyUnloadSignal(name)
	for index, func in Library.UnloadSignals do
		if debug.getinfo(func).name == name then
			table.remove(Library.UnloadSignals, index)
			break
		end
	end
end

reloadConnection = getgenv()._TPLAYS_ADDON_VALUES and getgenv()._TPLAYS_ADDON_VALUES.Reload:GetPropertyChangedSignal("Value"):Connect(function()
	if getgenv()._TPLAYS_ADDON_VALUES.Reload.Value then
		reloadConnection:Disconnect()
		for name, reloadFunc in ReloadSignals do
			destroyUnloadSignal(name)
			local success, err = pcall(reloadFunc, true)
			if not success then
				Library:Notify({
					Title = '哇，重载时出了点问题',
					Description = err,
					Time = 10
				})
			end
		end
		ReloadSignals = nil
		if ADDON_CONFIG.SeparateTabForAddon then
			for _, picker in KeyPickers do
				if picker.Destroy then
					picker:Destroy()
				end
			end
			for _, toggle in Toggles do
				if toggle.Destroy then
					toggle:Destroy()
				end
			end
		end
		task.wait(.1)
		getgenv()._TPLAYS_ADDON_VALUES.Loaded.Value = false
	end
end)

Library:OnUnload(function()
	if ReloadSignals then
		ReloadSignals = nil
	else
		return -- the addon was reloaded, don't try to unload using this function
	end
	if getgenv()._TPLAYS_ADDON_VALUES then
		for _, bool in getgenv()._TPLAYS_ADDON_VALUES do
			bool:Destroy()
		end
		getgenv()._TPLAYS_ADDON_VALUES = nil
	end
	if getgenv()._TPLAYS_ADDON_CONFIG then
		getgenv()._TPLAYS_ADDON_CONFIG = nil
	end
end)

function OnUnload(func: (WasReloaded: boolean?) -> ()): ()
	if debug.setinfo then
		local funcName = genName()
		debug.setinfo(func, {name = funcName})
		Library:OnUnload(func)
		ReloadSignals[funcName] = func
	else
		Library:OnUnload(func)
	end
end

OnUnload(function()
	loaded = false
end)

local tpath = "mspaint/"..Info.AddonName
local addon = {
	makefolder = function(path: string): ()
		makefolder(`{tpath}/{path}`)
	end,
	listfiles = function(path: string): {string}
		return listfiles(`{tpath}/{path}`)
	end,
	readfile = function(path: string): string
		return readfile(`{tpath}/{path}`)
	end,
	writefile = function(path: string, str: string): ()
		writefile(`{tpath}/{path}`, str)
	end,
	delfile = function(path: string): ()
		delfile(`{tpath}/{path}`)
	end,
	isfile = function(path: string): boolean
		return isfile(`{tpath}/{path}`)
	end,
	getcustomasset = getcustomasset and function(path: string): string
		return getcustomasset(`{tpath}/{path}`)
	end,
}

makefolder(tpath)
addon.makefolder("cache")

Module = {}
Module.LoadCustomAsset = function(url: string, name: string?): string?
	if addon.getcustomasset then
		local fileName = `cache/{name}` or `cache/TMP_{tick()}`
		local success, result = pcall(addon.getcustomasset, fileName)
		result = success and result
		if result then
			return result
		elseif url:lower():sub(1, 4) == 'http' then
			addon.writefile(fileName, game:HttpGet(url))
			result = addon.getcustomasset(fileName)
			if not name then
				addon.delfile(fileName)
			end
			return result
		elseif addon.isfile(url) then
			return addon.getcustomasset(url)
		end
	else
		warn("Executor doesn't support 'getcustomasset', rbxassetid only.")
	end
	if url:find('rbxassetid') or tonumber(url) then
		return 'rbxassetid://'..url:match('%d+')
	end
	error(debug.traceback('Failed to load custom asset for:\n'..url))
end

Module.LoadCustomInstance = function(url: string, name: string?): Instance?
	local s, r = pcall(function()
		return game:GetObjects(Module.LoadCustomAsset(url, name))[1]
	end)
	return s and r or nil
end

local normal = Module.LoadCustomAsset("https://github.com/tplaygd/Tplays-Addon-Stuff/raw/main/normal2.png", "normal.png")

local Groupbox, Groupbox2 = mspaint.Groupbox, mspaint.Groupbox
local Window = Groupbox.Tab.Window
if ADDON_CONFIG.SeparateTabForAddon then
	if game.GameId == 2440500124 then
		local tabName = game.PlaceId == 6516141723 and "Practice" or "Other"
		if Groupbox.Visible then
			Groupbox:Hide()
		end
		local ReloadFunc = Groupbox.Elements[1].Func
		local Tab = Library.Tabs[Info.AddonTitle]
		local Groupboxes = Tab and Tab.Groupboxes
		local Addon = Groupboxes and Groupboxes.Addon
		Groupbox = Groupboxes and Groupboxes.Main
		Groupbox2 = Groupboxes and Groupboxes[tabName]
		if Addon then
			Addon:Destroy()
		end
		if Groupbox then
			Groupbox:Destroy()
		end
		if Groupbox2 then
			Groupbox2:Destroy()
		end
		local tab = Tab or Window:AddTab(Info.AddonTitle, normal)
		Addon = tab:AddRightGroupbox("Addon")
		Groupbox = tab:AddLeftGroupbox("Main")
		Groupbox2 = tab:AddRightGroupbox(tabName)
		Addon:AddLabel(Info.AddonFullTitle)
		local button = Addon:AddButton(prefix.."CustomReloadLol", {
			Text = "重载插件",
			Tooltip = not debug.setinfo and "Addon might be broken after reloading it on your executor",
			Func = ReloadFunc,
			Risky = not debug.setinfo,
			Disabled = true
		})
		task.delay(3, button.SetDisabled, button, false)
	else
		Groupbox2 = nil
		if Groupbox.Visible then
			Groupbox:Hide()
		end
		local ReloadFunc = Groupbox.Elements[1].Func
		local Tab = Library.Tabs[Info.AddonTitle]
		local Groupboxes = Tab and Tab.Groupboxes
		local Addon = Groupboxes and Groupboxes.Addon
		Groupbox = Groupboxes and Groupboxes.Main
		if Addon then
			Addon:Destroy()
		end
		if Groupbox then
			Groupbox:Destroy()
		end
		local tab = Tab or Window:AddTab(Info.AddonTitle, normal)
		Addon = tab:AddRightGroupbox("Addon")
		Groupbox = tab:AddLeftGroupbox("Main")
		Addon:AddLabel(Info.AddonFullTitle)
		Addon:AddButton(prefix.."CustomReloadLol", {
			Text = "重载插件",
			Tooltip = not debug.setinfo and "Addon might be broken after reloading it on your executor",
			Func = ReloadFunc,
			Risky = not debug.setinfo
		})
	end
end

if game.PlaceId == 6516141723 then
	local RemotesFolder = Services.ReplicatedStorage:WaitForChild("RemotesFolder")
	local Create = RemotesFolder.CreateElevator
	local Leave = RemotesFolder.ElevatorExit
	local Journal = RemotesFolder.JournalPresence
	local Connections = {}

	local queue_on_teleport = func("function", queue_on_teleport or queueonteleport)
	local clear_teleport_queue = func("function", clear_teleport_queue or clearteleportqueue)

	writefile("teleporthandler", [[if game.PlaceId ~= 6839171747 then return end
function GetFunction(fn: string, e: boolean, fs: Instance): (any) -> any
	local success, result = pcall(function()
		return filtergc("function", {
			Name = fn,
			Source = fs and (typeof(fs) == "string" and fs or typeof(fs) == "Instance" and fs.Name),
			IgnoreExecutor = not e,
		}, true)
	end)
	return success and result
end
local players = game:GetService("Players")
local player = players.LocalPlayer
if not player then
    players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = players.LocalPlayer
end
local tpdata = game:GetService("TeleportService"):GetLocalPlayerTeleportData()
if tpdata and tpdata.Settings and tpdata.Settings.cMode == "true" and tpdata.Host == player.UserId then
    player:SetAttribute("Observer", true)
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	workspace.CurrentRooms.ChildAdded:Once(function()
		replicatesignal(player.Kill)
	end)
	task.wait()
	while not pcall(function()GetFunction("healthChanged")(0)end)do task.wait()end
end
queue_on_teleport(readfile("teleporthandler"))]])
	local execute = readfile("teleporthandler")
	local hasteleporthandler = filtergc and queue_on_teleport and clear_teleport_queue and execute and true or false
	if hasteleporthandler then
		queue_on_teleport(execute)
	end

	Groupbox:AddDivider({
		Text = "主界面",
		MarginTop = 2,
		MarginBottom = -2
	})

	local PlayAnim, AdjustAnim, AnimPlaying, StopAnim = GetFunction("PlayAnim"), GetFunction("AdjustAnim"), GetFunction("AnimPlaying"), GetFunction("StopAnim")

	Toggles.JournalSpoof = Groupbox:AddToggle(prefix..'JournalSpoof', {
		Text = '假装读日志',
		Tooltip = '我是一个读书人',
		Default = false,
		DisabledTooltip = "当前执行器不支持",
		Disabled = not filtergc,

		Callback = function(value)
			Journal:FireServer(value, false)
			if value then
				PlayAnim("Idle", 0.2, 1, 1)
				if AnimPlaying("Open") then
					AdjustAnim("Open", 1)
				elseif AnimPlaying("Close") then
					AdjustAnim("Close", -1)
				else
					PlayAnim("Open", 0, 1, 0.85)
				end
			else
				StopAnim("Idle", 0.1)
				if AnimPlaying("Close") then
					AdjustAnim("Close", 1)
				elseif AnimPlaying("Open") then
					AdjustAnim("Open", -1)
				else
					PlayAnim("Close", 0, 1, 0.9)
				end
			end
		end
	})

	Groupbox:AddButton(prefix..'BloxfestMode', {
		Text = 'Bloxfest 战斗电梯',
		Tooltip = '用观察者权限创建战斗电梯（用于 RB Battles）',
		DisabledTooltip = "当前执行器不支持",
		Disabled = not (hasteleporthandler and filtergc),

		Func = function()
			Create:FireServer({
				Mods = {},
				Settings = {
					cMode = "true"
				},
				Destination = "Party",
				FriendsOnly = false,
				MaxPlayers = "20"
			})
		end
	})

	local button; button = Groupbox:AddButton(prefix..'Crash', {
		Text = '崩溃',
		DisabledTooltip = "崩溃中...",
		DoubleClick = true,
		Risky = true,

		Func = function()
			button:SetDisabled(true)
			local coolseed = string.rep(utf8.char(2^16), 2^6)
			while''do
				coroutine.wrap(function()
					for i = 1,100 do
						coroutine.wrap(function()
							Create:FireServer({
								Mods = i%2 == 1 and {
									"AdminPanel",
									"Chaos3",
									"Gloombat",
									"NoGuidingLight",
									"PlayerCrouchSlow",
									"TimothyMore",
									"ItemDurabilityLess",
									"AmbushMore",
									"ScreechLight",
									"ScreechFast",
									"EyesTwice",
									"EyesLevel2",
									"AmbushFaster",
									"RushFaster",
									"BackdoorHaste",
									"BackdoorVacuum",
									"BackdoorLookman",
									"SnareMoster",
									"NoKeySound",
									"BackdoorRush",
									"LightsLess",
									"LeastHidingSpots",
									"Rooms",
									"Fog",
									"GiggleMore",
									"StreamerMode",
									"DreadMost",
									"HideLevel2",
									"GoldSpawnNone",
									"FigureFaster",
									"Slippery",
									"CustomSeed",
									"Voicelines",
									"RushLevel2",
									"RushQuiet",
									"RushMore",
									"EntitiesMoster",
									"LockMore",
									"DupeMore",
									"FiredampMost",
									"PlayerDamageMore"
								} or {"AdminPanel"},
								Settings = {
									seed = coolseed,
									cMode = coolseed
								},
								Destination = "Hotel",
								FriendsOnly = false,
								MaxPlayers = "50"
							})
							Leave:FireServer()
						end)()
					end
				end)()
				task.wait()
			end
		end
	})

	Groupbox:AddDivider({
		Text = "重进",
		MarginTop = 2,
		MarginBottom = -2
	})

	local scripts = {
		HideRank = {
			source = [[while not game:GetService('ReplicatedStorage'):FindFirstChild('RemotesFolder') do
				task.wait()
			end
			while not game:GetService('ReplicatedStorage'):FindFirstChild('RemotesFolder'):FindFirstChild('CheckRank') do
				task.wait()
			end
			game:GetService('ReplicatedStorage').RemotesFolder.CheckRank:Destroy()]],
			enabled = false
		},
	}

	Toggles.HideRank = Groupbox:AddToggle(prefix..'HideRank', {
		Text = '隐藏段位',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = '装备硬核徽章时隐藏段位',
		Disabled = not hasteleporthandler,
		Default = false,

		Callback = function(value)
			scripts.HideRank.enabled = value
		end
	})

	Groupbox:AddButton(prefix..'Rejoin', {
		Text = '重进',
		DoubleClick = true,
		Func = function()
			if queue_on_teleport then
				local finalscript = ""
				for _, script in scripts do
					if script.enabled then
						finalscript ..= `task.spawn(function() {script.source} end)`
					end
				end
				queue_on_teleport(finalscript)
			end
			Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
		end
	})

	Groupbox2:AddLabel([[你的执行器应该支持 QUEUE_ON_TELEPORT，并且你要有管理员菜单才能使用以下功能
	]], true)

	Groupbox2:AddButton(prefix..'Ransom', {
		Text = 'a90练习',
		DoubleClick = true,
		Disabled = not hasteleporthandler,
		Func = function()
			Create:FireServer({
				Mods = {
					"AdminPanel"
				},
				Settings = {},
				Destination = "Hotel",
				MaxPlayers = "1"
			})

			local script = [[
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end

			print("loading ransom practice...")

			type MainCaption = {
				Caption: TextLabel,
				Type: any,
				Smooth: boolean,
				Edit: (self: MainCaption, Text: string, Type: any?, Smooth: boolean?) -> MainCaption,
				Destroy: (self: MainCaption) -> (),
				Delay: (self: MainCaption, Delay: number) -> MainCaption
			}

			local BetterCaption = {
				Captions = {}
			}

			local TweenService = game:GetService("TweenService")
			local RunService = game:GetService("RunService")
			local SoundService = game:GetService("SoundService")

			local function NewSound(Sound: {[string]: any}?)
				local SoundObj = Instance.new("Sound", SoundService)
				for Prop, Value in Sound do
					SoundObj[Prop] = Value
				end
				SoundObj.Looped = false
				return {
					Playing = false,
					Play = function(self, destroy: boolean)
						self.Playing = true
						SoundObj:Play()
						if destroy then
							SoundObj.Ended:Wait()
							self:Destroy()
						end
					end,
					Stop = function(self)
						self.Playing = false
						SoundObj:Stop()
					end,
					Destroy = function(self)
						SoundObj:Destroy()
						self = nil
					end
				}
			end

			function BetterCaption:GetCaptionIndex(Caption: MainCaption): number?
				for Index, OtherCaption in self.Captions do
					if OtherCaption.Caption == Caption.Caption then
						return Index
					end
				end
				return
			end

			function BetterCaption:Caption(Text: string, Type: any?, Smooth: boolean?, Sound: {[string]: any}?): MainCaption
				Type = Type or "info"
				if Smooth == nil or typeof(Smooth) ~= "boolean" then
					Smooth = true 
				end
				Sound = typeof(Sound) == "table" and Sound or {
					SoundId = "rbxassetid://3848738542",
					Volume = .1,
					PlaybackSpeed = 1
				}
				Sound.SoundId = Sound.SoundId or "rbxassetid://3848738542"
				if Type ~= "thought" or game.ReplicatedStorage.GameData.Floor.Value ~= "Party" then
					if Text ~= "" and (Text ~= " " and Text ~= nil) then
						local Caption = BetterCaption.MainUI.MainFrame.NewCaption:Clone()
						Caption.Name = "LiveCaption"
						Caption.Visible = true
						Caption.Text = Text
						Caption.TextTransparency = 1
						Caption.TextStrokeTransparency = 1
						Caption.BackgroundTransparency = 1
						Caption.MaxVisibleGraphemes = Smooth and 0 or -1
						local function SetType(Type)
							local first = 1
							local second = 0
							local old = Caption:GetAttribute("Active")
							Caption:SetAttribute("Active", old and old+1 or 0)
							if Type == "thought" then
								Caption.TextColor3 = Color3.fromRGB(229, 224, 218)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Light, Enum.FontStyle.Normal)
								second = .6
							elseif Type == "info" then
								Caption.TextColor3 = Color3.fromRGB(255, 222, 189)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "rgb" then
								local CurrentNumber = Caption:GetAttribute("Active")
								local Gradient = Caption:FindFirstChildOfClass("UIGradient")
								Gradient = Gradient and Gradient:Clone() or Instance.new("UIGradient")
								Gradient.Parent = Caption
								Gradient.Enabled = true
								Gradient.Rotation = 0
								Gradient.Transparency = NumberSequence.new(0)
								Gradient.Color = ColorSequence.new({
									ColorSequenceKeypoint.new(
										0, Color3.fromHSV(0,1,1)
									),
									ColorSequenceKeypoint.new(
										1/6, Color3.fromHSV(1/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1/3, Color3.fromHSV(1/3,1,1)
									),
									ColorSequenceKeypoint.new(
										1/2, Color3.fromHSV(1/2,1,1)
									),
									ColorSequenceKeypoint.new(
										2/3, Color3.fromHSV(2/3,1,1)
									),
									ColorSequenceKeypoint.new(
										5/6, Color3.fromHSV(5/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1, Color3.fromHSV(1,1,1)
									)
								})
								local c; c = RunService.RenderStepped:Connect(function(DeltaTime)
									if CurrentNumber == Caption:GetAttribute("Active") and Caption.Parent then
										local NewKeypoints = {}
										for Key, Value in Gradient.Color.Keypoints do
											local H,S,V = Value.Value:ToHSV()
											NewKeypoints[Key] = ColorSequenceKeypoint.new(Value.Time, Color3.fromHSV((H+DeltaTime)%1,S,V))
										end
										Gradient.Color = ColorSequence.new(NewKeypoints)
									else
										c:Disconnect()
										Gradient:Destroy()
									end
								end)
								Caption.TextColor3 = Color3.new(1, 1, 1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "warning" then
								Caption.TextColor3 = Color3.fromRGB(225, 177, 138)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								Caption.BackgroundColor3 = Color3.fromRGB(36, 28, 26)
								first = .75
								second = .7
							else
								local Success, Color = pcall(function()
									return typeof(Type) == "Color3" and Type or typeof(Type) == "string" and Color3.fromHex(Type)
								end)
								Caption.TextColor3 = Success and Color or Color3.new(1,1,1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							end
							return first, second
						end
						local first, second = SetType(Type)
						Caption.Parent = BetterCaption.MainUI.CaptionHolder
						local CaptionSound = NewSound(Sound)
						CaptionSound:Play()
						TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
							BackgroundTransparency = nil,
							TextTransparency = 0,
							TextStrokeTransparency = nil,
							BackgroundTransparency = first,
							TextStrokeTransparency = second
						}):Play()
						if Smooth then
							TweenService:Create(Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
								MaxVisibleGraphemes = #Text
							}):Play()
							task.delay(.25, function()
								Caption.MaxVisibleGraphemes = -1
							end)
						end
						local MainCaption = {
							Caption = Caption,
							Type = Type,
							Smooth = Smooth,
							Edit = function(self, Text: string, Type: any?, Smooth: boolean?)
								self.Caption.Text = Text
								Type = Type == nil and self.Type or Type
								Smooth = Smooth == nil and self.Smooth or Smooth
								self.Type = Type
								self.Smooth = Smooth
								local first, second = SetType(Type)
								CaptionSound:Play()
								TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
									BackgroundTransparency = nil,
									TextTransparency = 0,
									TextStrokeTransparency = nil,
									BackgroundTransparency = first,
									TextStrokeTransparency = second
								}):Play()
								if Smooth then
									self.Caption.MaxVisibleGraphemes = 0
									TweenService:Create(self.Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
										MaxVisibleGraphemes = #Text
									}):Play()
									task.delay(.25, function()
										self.Caption.MaxVisibleGraphemes = -1
									end)
								end
								return self
							end,
							Destroy = function(self)
								table.remove(BetterCaption.Captions, BetterCaption:GetCaptionIndex(self))
								local Caption = self.Caption
								self = nil
								TweenService:Create(Caption, TweenInfo.new(1.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
									BackgroundTransparency = 1,
									TextTransparency = 1,
									TextStrokeTransparency = 1
								}):Play()
								task.delay(1, function()
									CaptionSound:Destroy()
									Caption:Destroy()
								end)
							end,
							Delay = function(self, Delay: number)
								task.wait(Delay)
								return self
							end
						}
						table.insert(self.Captions, MainCaption)
						return MainCaption
					end
				end
				return nil
			end

			function BetterCaption:ClearAllCaptions()
				for _, Caption in BetterCaption.Captions do
					task.delay(.001, function()
						Caption:Destroy()
					end)
				end
			end

			BetterCaption:Caption(text, "rgb", false)

			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local ReplicatedFirst = game:GetService("ReplicatedFirst")
			local SoundService = game:GetService("SoundService")
			local Players = game:GetService("Players")
			local RunService = game:GetService("RunService")

			local LocalPlayer = Players.LocalPlayer
			local PlayerGui = LocalPlayer.PlayerGui

			task.spawn(function()
				PlayerGui:WaitForChild("DoorsAdmin", 1/0):Destroy()
			end)

			local RemotesFolder = ReplicatedStorage.RemotesFolder
			local GameData = ReplicatedStorage.GameData
			local _Loaded = ReplicatedFirst._Loaded

			local AdminPanelRunCommand = RemotesFolder.AdminPanelRunCommand
			local RequestLocalAsset = RemotesFolder.RequestLocalAsset
			local ServerTeleported = RemotesFolder.ServerTeleported
			local ToggleLoading = RemotesFolder.ToggleLoading
			local GetCurrency = RemotesFolder.GetCurrency
			local DeathHint = RemotesFolder.DeathHint
			local Crouch = RemotesFolder.Crouch
			local Lobby = RemotesFolder.Lobby

			local LatestRoom = GameData.LatestRoom

			local limit = 6

			local function getNilInstanceByName(name: string): Instance?
				for i,v in getnilinstances() do
					if v.Name == name then
						return v
					end
				end
				return nil
			end

			local ready = false
			task.spawn(function()
				while not ready do
					local Main = SoundService:FindFirstChild("Main")
					if Main then
						Main.Volume = 0
					end
					_Loaded.Value = false
					task.wait()
				end
				local MainUI = PlayerGui.MainUI
				local TopbarUI = PlayerGui.TopbarUI
				BetterCaption.MainUI = MainUI
				TopbarUI.ButtonsLeft.PanelButton.Visible = false
				TopbarUI.Topbar.Modifiers.Visible = false
				task.spawn(function()
					local TempMods = MainUI:WaitForChild("TempMods", 1/0)
					if TempMods then
						TempMods:Destroy()
					end
				end)
				SoundService.Main.Volume = 1
				_Loaded.Value = true
			end)

			local function lerp(a,b,c)
				return a * (1 - c) + b * c
			end

			local lerpProgress = LatestRoom.Value

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local TravelText = LoadingUI.Loading.LoadingText.TravelText
				while math.round(lerpProgress/limit*100) < 100 do
					local dt = task.wait()
					lerpProgress = lerp(lerpProgress, LatestRoom.Value, math.clamp(dt*8, 0, 1))
					local text = `Loading progress: {math.round(lerpProgress/limit*100)}%`
					TravelText.Text = text
					TravelText.TravelShadow.Text = text
				end
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				while math.round(lerpProgress/limit*100) < 100 do
					if not LoadingUI.Enabled then
						LoadingUI.Enabled = true
						LoadingUI.Loading.Visible = true
						LoadingUI.Loading.BackgroundTransparency = 0
						LoadingUI.Loading.FloorBackground.ImageTransparency = 0.75
						LoadingUI.Loading.LoadingText.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.Shadow.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TextTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TravelShadow.TextTransparency = 0
					end
					task.wait()
				end
				ToggleLoading:Fire(false)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = true
			})

			local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
			
			task.wait(.5)
			
			AdminPanelRunCommand:FireServer("Fly", {})

			local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
			while LatestRoom.Value < limit do
				Crouch:FireServer(true,true)
				Character:PivotTo(Room and Room:FindFirstChild("Door") and Room.Door:GetPivot() or Character:GetPivot())
				RequestLocalAsset:InvokeServer({{}})
				Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				if LatestRoom.Value >= limit then break end
				AdminPanelRunCommand:FireServer("SkipRoom", {})
			end

			while math.round(lerpProgress/limit*100) < 100 do
				task.wait()
			end

			AdminPanelRunCommand:FireServer("Fly", {})
			Crouch:FireServer()

			ready = true

			local End = false

			task.spawn(function()
				while not End do
					task.wait()
				end
				for _, door in workspace.CurrentRooms:QueryDescendants("> Model > #Door") do
					door:Clone().Parent = door.Parent
					door:Destroy()
				end
				workspace.CurrentRooms.DescendantAdded:Connect(function(door)
					if door.Name == "Door" and door.Parent:IsA("Model") and door.Parent.Parent == workspace.CurrentRooms then
						door:Clone().Parent = door.Parent
						door:Destroy()
					end
				end)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 50,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 50,
				["Allow Jumping"] = false,
				["God Mode"] = false
			})

			RequestLocalAsset:InvokeServer({{}})

			AdminPanelRunCommand:FireServer("RansomPlayer", {
				Players = {}
			})

			local currentGold = 0
			local currency; currency = GetCurrency.OnClientEvent:Connect(function(_,gold,str)
				if str == "RansomGold" then
					currentGold += gold
					if currentGold >= 150 then
						currency:Disconnect()
						End = true
						task.wait(5)
						BetterCaption:Caption("Teleporting to Lobby in 3 seconds...", "rgb", false):Delay(3)
						Lobby:FireServer()
					end
				end
			end)

			local texts = table.create(10000, "Teleporting to Lobby in 10 seconds...")
			Character.Humanoid.Died:Once(function()
				End = true
				firesignal(DeathHint.OnClientEvent, texts, "Glitch")
				task.wait(3.33)
				task.wait(10)
				Lobby:FireServer()
			end)

			workspace:WaitForChild("Ransom", 1/0)
			task.wait(.4)

			firesignal(ServerTeleported.OnClientEvent, Character:GetPivot().Position+Character:GetPivot().LookVector, -workspace.CurrentCamera.CFrame.LookVector)
			task.wait(.6)
			firesignal(ServerTeleported.OnClientEvent, Character:GetPivot().Position+Character:GetPivot().LookVector, -workspace.CurrentCamera.CFrame.LookVector)
			]]

			queue_on_teleport(script)
		end
	})

	Groupbox2:AddButton(prefix..'FirstSeekHotel', {
		Text = '酒店seek追逐战联系[第一次]',
		DoubleClick = true,
		Disabled = not hasteleporthandler,
		Func = function()
			Create:FireServer({
				Mods = {
					"AdminPanel"
				},
				Settings = {},
				Destination = "Hotel",
				MaxPlayers = "1"
			})

			local script = [[
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end

			print("loading first seek hotel...")

			type MainCaption = {
				Caption: TextLabel,
				Type: any,
				Smooth: boolean,
				Edit: (self: MainCaption, Text: string, Type: any?, Smooth: boolean?) -> MainCaption,
				Destroy: (self: MainCaption) -> (),
				Delay: (self: MainCaption, Delay: number) -> MainCaption
			}

			local BetterCaption = {
				Captions = {}
			}

			local TweenService = game:GetService("TweenService")
			local RunService = game:GetService("RunService")
			local SoundService = game:GetService("SoundService")

			local function NewSound(Sound: {[string]: any}?)
				local SoundObj = Instance.new("Sound", SoundService)
				for Prop, Value in Sound do
					SoundObj[Prop] = Value
				end
				SoundObj.Looped = false
				return {
					Playing = false,
					Play = function(self, destroy: boolean)
						self.Playing = true
						SoundObj:Play()
						if destroy then
							SoundObj.Ended:Wait()
							self:Destroy()
						end
					end,
					Stop = function(self)
						self.Playing = false
						SoundObj:Stop()
					end,
					Destroy = function(self)
						SoundObj:Destroy()
						self = nil
					end
				}
			end

			function BetterCaption:GetCaptionIndex(Caption: MainCaption): number?
				for Index, OtherCaption in self.Captions do
					if OtherCaption.Caption == Caption.Caption then
						return Index
					end
				end
				return
			end

			function BetterCaption:Caption(Text: string, Type: any?, Smooth: boolean?, Sound: {[string]: any}?): MainCaption
				Type = Type or "info"
				if Smooth == nil or typeof(Smooth) ~= "boolean" then
					Smooth = true 
				end
				Sound = typeof(Sound) == "table" and Sound or {
					SoundId = "rbxassetid://3848738542",
					Volume = .1,
					PlaybackSpeed = 1
				}
				Sound.SoundId = Sound.SoundId or "rbxassetid://3848738542"
				if Type ~= "thought" or game.ReplicatedStorage.GameData.Floor.Value ~= "Party" then
					if Text ~= "" and (Text ~= " " and Text ~= nil) then
						local Caption = BetterCaption.MainUI.MainFrame.NewCaption:Clone()
						Caption.Name = "LiveCaption"
						Caption.Visible = true
						Caption.Text = Text
						Caption.TextTransparency = 1
						Caption.TextStrokeTransparency = 1
						Caption.BackgroundTransparency = 1
						Caption.MaxVisibleGraphemes = Smooth and 0 or -1
						local function SetType(Type)
							local first = 1
							local second = 0
							local old = Caption:GetAttribute("Active")
							Caption:SetAttribute("Active", old and old+1 or 0)
							if Type == "thought" then
								Caption.TextColor3 = Color3.fromRGB(229, 224, 218)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Light, Enum.FontStyle.Normal)
								second = .6
							elseif Type == "info" then
								Caption.TextColor3 = Color3.fromRGB(255, 222, 189)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "rgb" then
								local CurrentNumber = Caption:GetAttribute("Active")
								local Gradient = Caption:FindFirstChildOfClass("UIGradient")
								Gradient = Gradient and Gradient:Clone() or Instance.new("UIGradient")
								Gradient.Parent = Caption
								Gradient.Enabled = true
								Gradient.Rotation = 0
								Gradient.Transparency = NumberSequence.new(0)
								Gradient.Color = ColorSequence.new({
									ColorSequenceKeypoint.new(
										0, Color3.fromHSV(0,1,1)
									),
									ColorSequenceKeypoint.new(
										1/6, Color3.fromHSV(1/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1/3, Color3.fromHSV(1/3,1,1)
									),
									ColorSequenceKeypoint.new(
										1/2, Color3.fromHSV(1/2,1,1)
									),
									ColorSequenceKeypoint.new(
										2/3, Color3.fromHSV(2/3,1,1)
									),
									ColorSequenceKeypoint.new(
										5/6, Color3.fromHSV(5/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1, Color3.fromHSV(1,1,1)
									)
								})
								local c; c = RunService.RenderStepped:Connect(function(DeltaTime)
									if CurrentNumber == Caption:GetAttribute("Active") and Caption.Parent then
										local NewKeypoints = {}
										for Key, Value in Gradient.Color.Keypoints do
											local H,S,V = Value.Value:ToHSV()
											NewKeypoints[Key] = ColorSequenceKeypoint.new(Value.Time, Color3.fromHSV((H+DeltaTime)%1,S,V))
										end
										Gradient.Color = ColorSequence.new(NewKeypoints)
									else
										c:Disconnect()
										Gradient:Destroy()
									end
								end)
								Caption.TextColor3 = Color3.new(1, 1, 1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "warning" then
								Caption.TextColor3 = Color3.fromRGB(225, 177, 138)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								Caption.BackgroundColor3 = Color3.fromRGB(36, 28, 26)
								first = .75
								second = .7
							else
								local Success, Color = pcall(function()
									return typeof(Type) == "Color3" and Type or typeof(Type) == "string" and Color3.fromHex(Type)
								end)
								Caption.TextColor3 = Success and Color or Color3.new(1,1,1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							end
							return first, second
						end
						local first, second = SetType(Type)
						Caption.Parent = BetterCaption.MainUI.CaptionHolder
						local CaptionSound = NewSound(Sound)
						CaptionSound:Play()
						TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
							BackgroundTransparency = nil,
							TextTransparency = 0,
							TextStrokeTransparency = nil,
							BackgroundTransparency = first,
							TextStrokeTransparency = second
						}):Play()
						if Smooth then
							TweenService:Create(Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
								MaxVisibleGraphemes = #Text
							}):Play()
							task.delay(.25, function()
								Caption.MaxVisibleGraphemes = -1
							end)
						end
						local MainCaption = {
							Caption = Caption,
							Type = Type,
							Smooth = Smooth,
							Edit = function(self, Text: string, Type: any?, Smooth: boolean?)
								self.Caption.Text = Text
								Type = Type == nil and self.Type or Type
								Smooth = Smooth == nil and self.Smooth or Smooth
								self.Type = Type
								self.Smooth = Smooth
								local first, second = SetType(Type)
								CaptionSound:Play()
								TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
									BackgroundTransparency = nil,
									TextTransparency = 0,
									TextStrokeTransparency = nil,
									BackgroundTransparency = first,
									TextStrokeTransparency = second
								}):Play()
								if Smooth then
									self.Caption.MaxVisibleGraphemes = 0
									TweenService:Create(self.Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
										MaxVisibleGraphemes = #Text
									}):Play()
									task.delay(.25, function()
										self.Caption.MaxVisibleGraphemes = -1
									end)
								end
								return self
							end,
							Destroy = function(self)
								table.remove(BetterCaption.Captions, BetterCaption:GetCaptionIndex(self))
								local Caption = self.Caption
								self = nil
								TweenService:Create(Caption, TweenInfo.new(1.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
									BackgroundTransparency = 1,
									TextTransparency = 1,
									TextStrokeTransparency = 1
								}):Play()
								task.delay(1, function()
									CaptionSound:Destroy()
									Caption:Destroy()
								end)
							end,
							Delay = function(self, Delay: number)
								task.wait(Delay)
								return self
							end
						}
						table.insert(self.Captions, MainCaption)
						return MainCaption
					end
				end
				return nil
			end

			function BetterCaption:ClearAllCaptions()
				for _, Caption in BetterCaption.Captions do
					task.delay(.001, function()
						Caption:Destroy()
					end)
				end
			end

			BetterCaption:Caption(text, "rgb", false)

			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local ReplicatedFirst = game:GetService("ReplicatedFirst")
			local SoundService = game:GetService("SoundService")
			local Players = game:GetService("Players")
			local RunService = game:GetService("RunService")

			local LocalPlayer = Players.LocalPlayer
			local PlayerGui = LocalPlayer.PlayerGui

			task.spawn(function()
				PlayerGui:WaitForChild("DoorsAdmin", 1/0):Destroy()
			end)

			local RemotesFolder = ReplicatedStorage.RemotesFolder
			local GameData = ReplicatedStorage.GameData
			local _Loaded = ReplicatedFirst._Loaded

			local AdminPanelRunCommand = RemotesFolder.AdminPanelRunCommand
			local RequestLocalAsset = RemotesFolder.RequestLocalAsset
			local ToggleLoading = RemotesFolder.ToggleLoading
			local DeathHint = RemotesFolder.DeathHint
			local Crouch = RemotesFolder.Crouch
			local Lobby = RemotesFolder.Lobby

			local LatestRoom = GameData.LatestRoom

			local function getNilInstanceByName(name: string): Instance?
				for i,v in getnilinstances() do
					if v.Name == name then
						return v
					end
				end
				return nil
			end

			local ready = false
			task.spawn(function()
				while not ready do
					local Main = SoundService:FindFirstChild("Main")
					if Main then
						Main.Volume = 0
					end
					_Loaded.Value = false
					task.wait()
				end
				local MainUI = PlayerGui.MainUI
				local TopbarUI = PlayerGui.TopbarUI
				BetterCaption.MainUI = MainUI
				TopbarUI.ButtonsLeft.PanelButton.Visible = false
				TopbarUI.Topbar.Modifiers.Visible = false
				task.spawn(function()
					local TempMods = MainUI:WaitForChild("TempMods", 1/0)
					if TempMods then
						TempMods:Destroy()
					end
				end)
				SoundService.Main.Volume = 1
				_Loaded.Value = true
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local TravelText = LoadingUI.Loading.LoadingText.TravelText
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while (not Room or Room:GetAttribute("RawName") ~= "Hotel_SeekIntro") and task.wait() do
					local text = `Heading to first Seek Chase in Hotel (Room {LatestRoom.Value})`
					TravelText.Text = text
					TravelText.TravelShadow.Text = text
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while not Room or Room:GetAttribute("RawName") ~= "Hotel_SeekIntro" do
					if not LoadingUI.Enabled then
						LoadingUI.Enabled = true
						LoadingUI.Loading.Visible = true
						LoadingUI.Loading.BackgroundTransparency = 0
						LoadingUI.Loading.FloorBackground.ImageTransparency = 0.75
						LoadingUI.Loading.LoadingText.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.Shadow.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TextTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TravelShadow.TextTransparency = 0
					end
					task.wait()
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
				ToggleLoading:Fire(false)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = true
			})

			local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

			task.delay(.5, function()
				AdminPanelRunCommand:FireServer("Fly", {})
			end)

			task.spawn(function()
				while task.wait(.1) do
					AdminPanelRunCommand:FireServer("DELETE ALL", {})
				end
			end)

			local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
			while not Room or Room:GetAttribute("RawName") ~= "Hotel_SeekIntro" do
				Crouch:FireServer(true,true)
				Character:PivotTo(Room and Room:FindFirstChild("Door") and Room.Door:GetPivot() or Character:GetPivot())
				RequestLocalAsset:InvokeServer({{}})
				Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				if not (not Room or Room:GetAttribute("RawName") ~= "Hotel_SeekIntro") then break end
				AdminPanelRunCommand:FireServer("SkipRoom", {})
			end

			AdminPanelRunCommand:FireServer("Fly", {})
			Crouch:FireServer()

			ready = true

			local End = false
			local goodend = true

			task.spawn(function()
				while not End do
					task.wait()
				end
				task.spawn(function()
					if not goodend then return end
					BetterCaption:Caption("Teleporting to Lobby in 5 seconds...", "rgb", false):Delay(5)
					Lobby:FireServer()
				end)
				for _, door in workspace.CurrentRooms:QueryDescendants("> Model > #Door") do
					door:Clone().Parent = door.Parent
					door:Destroy()
				end
				workspace.CurrentRooms.DescendantAdded:Connect(function(door)
					if door.Name == "Door" and door.Parent:IsA("Model") and door.Parent.Parent == workspace.CurrentRooms then
						door:Clone().Parent = door.Parent
						door:Destroy()
					end
				end)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = false
			})

			local texts = table.create(10000, "Teleporting to Lobby in 10 seconds...")
			Character.Humanoid.Died:Once(function()
				goodend = false
				End = true
				firesignal(DeathHint.OnClientEvent, texts, "Glitch")
				task.wait(3.33)
				task.wait(10)
				Lobby:FireServer()
			end)

			local endRoom = LatestRoom.Value+6
			repeat task.wait() until LatestRoom.Value >= endRoom
			End = true
			]]

			queue_on_teleport(script)
		end
	})

	Groupbox2:AddButton(prefix..'FirstSeekMines', {
		Text = '矿井seek追逐战练习[第一次]',
		DoubleClick = true,
		Disabled = not hasteleporthandler,
		Func = function()
			Create:FireServer({
				Mods = {
					"AdminPanel"
				},
				Settings = {},
				Destination = "Mines",
				MaxPlayers = "1"
			})

			local script = [[
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end

			print("loading first seek mines...")

			type MainCaption = {
				Caption: TextLabel,
				Type: any,
				Smooth: boolean,
				Edit: (self: MainCaption, Text: string, Type: any?, Smooth: boolean?) -> MainCaption,
				Destroy: (self: MainCaption) -> (),
				Delay: (self: MainCaption, Delay: number) -> MainCaption
			}

			local BetterCaption = {
				Captions = {}
			}

			local TweenService = game:GetService("TweenService")
			local RunService = game:GetService("RunService")
			local SoundService = game:GetService("SoundService")

			local function NewSound(Sound: {[string]: any}?)
				local SoundObj = Instance.new("Sound", SoundService)
				for Prop, Value in Sound do
					SoundObj[Prop] = Value
				end
				SoundObj.Looped = false
				return {
					Playing = false,
					Play = function(self, destroy: boolean)
						self.Playing = true
						SoundObj:Play()
						if destroy then
							SoundObj.Ended:Wait()
							self:Destroy()
						end
					end,
					Stop = function(self)
						self.Playing = false
						SoundObj:Stop()
					end,
					Destroy = function(self)
						SoundObj:Destroy()
						self = nil
					end
				}
			end

			function BetterCaption:GetCaptionIndex(Caption: MainCaption): number?
				for Index, OtherCaption in self.Captions do
					if OtherCaption.Caption == Caption.Caption then
						return Index
					end
				end
				return
			end

			function BetterCaption:Caption(Text: string, Type: any?, Smooth: boolean?, Sound: {[string]: any}?): MainCaption
				Type = Type or "info"
				if Smooth == nil or typeof(Smooth) ~= "boolean" then
					Smooth = true 
				end
				Sound = typeof(Sound) == "table" and Sound or {
					SoundId = "rbxassetid://3848738542",
					Volume = .1,
					PlaybackSpeed = 1
				}
				Sound.SoundId = Sound.SoundId or "rbxassetid://3848738542"
				if Type ~= "thought" or game.ReplicatedStorage.GameData.Floor.Value ~= "Party" then
					if Text ~= "" and (Text ~= " " and Text ~= nil) then
						local Caption = BetterCaption.MainUI.MainFrame.NewCaption:Clone()
						Caption.Name = "LiveCaption"
						Caption.Visible = true
						Caption.Text = Text
						Caption.TextTransparency = 1
						Caption.TextStrokeTransparency = 1
						Caption.BackgroundTransparency = 1
						Caption.MaxVisibleGraphemes = Smooth and 0 or -1
						local function SetType(Type)
							local first = 1
							local second = 0
							local old = Caption:GetAttribute("Active")
							Caption:SetAttribute("Active", old and old+1 or 0)
							if Type == "thought" then
								Caption.TextColor3 = Color3.fromRGB(229, 224, 218)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Light, Enum.FontStyle.Normal)
								second = .6
							elseif Type == "info" then
								Caption.TextColor3 = Color3.fromRGB(255, 222, 189)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "rgb" then
								local CurrentNumber = Caption:GetAttribute("Active")
								local Gradient = Caption:FindFirstChildOfClass("UIGradient")
								Gradient = Gradient and Gradient:Clone() or Instance.new("UIGradient")
								Gradient.Parent = Caption
								Gradient.Enabled = true
								Gradient.Rotation = 0
								Gradient.Transparency = NumberSequence.new(0)
								Gradient.Color = ColorSequence.new({
									ColorSequenceKeypoint.new(
										0, Color3.fromHSV(0,1,1)
									),
									ColorSequenceKeypoint.new(
										1/6, Color3.fromHSV(1/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1/3, Color3.fromHSV(1/3,1,1)
									),
									ColorSequenceKeypoint.new(
										1/2, Color3.fromHSV(1/2,1,1)
									),
									ColorSequenceKeypoint.new(
										2/3, Color3.fromHSV(2/3,1,1)
									),
									ColorSequenceKeypoint.new(
										5/6, Color3.fromHSV(5/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1, Color3.fromHSV(1,1,1)
									)
								})
								local c; c = RunService.RenderStepped:Connect(function(DeltaTime)
									if CurrentNumber == Caption:GetAttribute("Active") and Caption.Parent then
										local NewKeypoints = {}
										for Key, Value in Gradient.Color.Keypoints do
											local H,S,V = Value.Value:ToHSV()
											NewKeypoints[Key] = ColorSequenceKeypoint.new(Value.Time, Color3.fromHSV((H+DeltaTime)%1,S,V))
										end
										Gradient.Color = ColorSequence.new(NewKeypoints)
									else
										c:Disconnect()
										Gradient:Destroy()
									end
								end)
								Caption.TextColor3 = Color3.new(1, 1, 1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "warning" then
								Caption.TextColor3 = Color3.fromRGB(225, 177, 138)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								Caption.BackgroundColor3 = Color3.fromRGB(36, 28, 26)
								first = .75
								second = .7
							else
								local Success, Color = pcall(function()
									return typeof(Type) == "Color3" and Type or typeof(Type) == "string" and Color3.fromHex(Type)
								end)
								Caption.TextColor3 = Success and Color or Color3.new(1,1,1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							end
							return first, second
						end
						local first, second = SetType(Type)
						Caption.Parent = BetterCaption.MainUI.CaptionHolder
						local CaptionSound = NewSound(Sound)
						CaptionSound:Play()
						TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
							BackgroundTransparency = nil,
							TextTransparency = 0,
							TextStrokeTransparency = nil,
							BackgroundTransparency = first,
							TextStrokeTransparency = second
						}):Play()
						if Smooth then
							TweenService:Create(Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
								MaxVisibleGraphemes = #Text
							}):Play()
							task.delay(.25, function()
								Caption.MaxVisibleGraphemes = -1
							end)
						end
						local MainCaption = {
							Caption = Caption,
							Type = Type,
							Smooth = Smooth,
							Edit = function(self, Text: string, Type: any?, Smooth: boolean?)
								self.Caption.Text = Text
								Type = Type == nil and self.Type or Type
								Smooth = Smooth == nil and self.Smooth or Smooth
								self.Type = Type
								self.Smooth = Smooth
								local first, second = SetType(Type)
								CaptionSound:Play()
								TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
									BackgroundTransparency = nil,
									TextTransparency = 0,
									TextStrokeTransparency = nil,
									BackgroundTransparency = first,
									TextStrokeTransparency = second
								}):Play()
								if Smooth then
									self.Caption.MaxVisibleGraphemes = 0
									TweenService:Create(self.Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
										MaxVisibleGraphemes = #Text
									}):Play()
									task.delay(.25, function()
										self.Caption.MaxVisibleGraphemes = -1
									end)
								end
								return self
							end,
							Destroy = function(self)
								table.remove(BetterCaption.Captions, BetterCaption:GetCaptionIndex(self))
								local Caption = self.Caption
								self = nil
								TweenService:Create(Caption, TweenInfo.new(1.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
									BackgroundTransparency = 1,
									TextTransparency = 1,
									TextStrokeTransparency = 1
								}):Play()
								task.delay(1, function()
									CaptionSound:Destroy()
									Caption:Destroy()
								end)
							end,
							Delay = function(self, Delay: number)
								task.wait(Delay)
								return self
							end
						}
						table.insert(self.Captions, MainCaption)
						return MainCaption
					end
				end
				return nil
			end

			function BetterCaption:ClearAllCaptions()
				for _, Caption in BetterCaption.Captions do
					task.delay(.001, function()
						Caption:Destroy()
					end)
				end
			end

			BetterCaption:Caption(text, "rgb", false)

			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local ReplicatedFirst = game:GetService("ReplicatedFirst")
			local SoundService = game:GetService("SoundService")
			local Players = game:GetService("Players")
			local RunService = game:GetService("RunService")

			local LocalPlayer = Players.LocalPlayer
			local PlayerGui = LocalPlayer.PlayerGui

			task.spawn(function()
				PlayerGui:WaitForChild("DoorsAdmin", 1/0):Destroy()
			end)

			local RemotesFolder = ReplicatedStorage.RemotesFolder
			local GameData = ReplicatedStorage.GameData
			local _Loaded = ReplicatedFirst._Loaded

			local AdminPanelRunCommand = RemotesFolder.AdminPanelRunCommand
			local RequestLocalAsset = RemotesFolder.RequestLocalAsset
			local ToggleLoading = RemotesFolder.ToggleLoading
			local DeathHint = RemotesFolder.DeathHint
			local Crouch = RemotesFolder.Crouch
			local Lobby = RemotesFolder.Lobby

			local LatestRoom = GameData.LatestRoom

			local function getNilInstanceByName(name: string): Instance?
				for i,v in getnilinstances() do
					if v.Name == name then
						return v
					end
				end
				return nil
			end

			local ready = false
			task.spawn(function()
				while not ready do
					local Main = SoundService:FindFirstChild("Main")
					if Main then
						Main.Volume = 0
					end
					_Loaded.Value = false
					task.wait()
				end
				local MainUI = PlayerGui.MainUI
				local TopbarUI = PlayerGui.TopbarUI
				BetterCaption.MainUI = MainUI
				TopbarUI.ButtonsLeft.PanelButton.Visible = false
				TopbarUI.Topbar.Modifiers.Visible = false
				task.spawn(function()
					local TempMods = MainUI:WaitForChild("TempMods", 1/0)
					if TempMods then
						TempMods:Destroy()
					end
				end)
				SoundService.Main.Volume = 1
				_Loaded.Value = true
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local TravelText = LoadingUI.Loading.LoadingText.TravelText
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while (not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart") and task.wait() do
					local text = `Heading to first Seek Chase in Mines (Room {LatestRoom.Value})`
					TravelText.Text = text
					TravelText.TravelShadow.Text = text
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart" do
					if not LoadingUI.Enabled then
						LoadingUI.Enabled = true
						LoadingUI.Loading.Visible = true
						LoadingUI.Loading.BackgroundTransparency = 0
						LoadingUI.Loading.FloorBackground.ImageTransparency = 0.75
						LoadingUI.Loading.LoadingText.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.Shadow.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TextTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TravelShadow.TextTransparency = 0
					end
					task.wait()
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
				ToggleLoading:Fire(false)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = true
			})

			local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

			task.delay(.5, function()
				AdminPanelRunCommand:FireServer("Fly", {})
			end)

			task.spawn(function()
				while task.wait(.1) do
					AdminPanelRunCommand:FireServer("DELETE ALL", {})
				end
			end)

			local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
			while not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart" do
				Crouch:FireServer(true,true)
				Character:PivotTo(Room and Room:FindFirstChild("Door") and Room.Door:GetPivot() or Character:GetPivot())
				RequestLocalAsset:InvokeServer({{}})
				Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				if not (not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart") then break end
				AdminPanelRunCommand:FireServer("SkipRoom", {})
			end

			AdminPanelRunCommand:FireServer("Fly", {})
			Crouch:FireServer()

			ready = true

			local End = false
			local goodend = true

			task.spawn(function()
				while not End do
					task.wait()
				end
				task.spawn(function()
					if not goodend then return end
					BetterCaption:Caption("Teleporting to Lobby in 5 seconds...", "rgb", false):Delay(5)
					Lobby:FireServer()
				end)
				for _, door in workspace.CurrentRooms:QueryDescendants("> Model > #Door") do
					door:Clone().Parent = door.Parent
					door:Destroy()
				end
				workspace.CurrentRooms.DescendantAdded:Connect(function(door)
					if door.Name == "Door" and door.Parent:IsA("Model") and door.Parent.Parent == workspace.CurrentRooms then
						door:Clone().Parent = door.Parent
						door:Destroy()
					end
				end)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = false
			})

			local texts = table.create(10000, "Teleporting to Lobby in 10 seconds...")
			Character.Humanoid.Died:Once(function()
				goodend = false
				End = true
				firesignal(DeathHint.OnClientEvent, texts, "Glitch")
				task.wait(3.33)
				task.wait(10)
				Lobby:FireServer()
			end)

			local endRoom = 49
			repeat task.wait() until LatestRoom.Value >= endRoom
			End = true
			]]

			queue_on_teleport(script)
		end
	})

	Groupbox2:AddButton(prefix..'EyestalkChase', {
		Text = '户外追逐战联系[滚木]',
		DoubleClick = true,
		Disabled = not hasteleporthandler,
		Func = function()
			Create:FireServer({
				Mods = {
					"AdminPanel"
				},
				Settings = {},
				Destination = "Garden",
				MaxPlayers = "1"
			})

			local script = [[
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end

			print("loading eyestalk chase...")

			type MainCaption = {
				Caption: TextLabel,
				Type: any,
				Smooth: boolean,
				Edit: (self: MainCaption, Text: string, Type: any?, Smooth: boolean?) -> MainCaption,
				Destroy: (self: MainCaption) -> (),
				Delay: (self: MainCaption, Delay: number) -> MainCaption
			}

			local BetterCaption = {
				Captions = {}
			}

			local TweenService = game:GetService("TweenService")
			local RunService = game:GetService("RunService")
			local SoundService = game:GetService("SoundService")

			local function NewSound(Sound: {[string]: any}?)
				local SoundObj = Instance.new("Sound", SoundService)
				for Prop, Value in Sound do
					SoundObj[Prop] = Value
				end
				SoundObj.Looped = false
				return {
					Playing = false,
					Play = function(self, destroy: boolean)
						self.Playing = true
						SoundObj:Play()
						if destroy then
							SoundObj.Ended:Wait()
							self:Destroy()
						end
					end,
					Stop = function(self)
						self.Playing = false
						SoundObj:Stop()
					end,
					Destroy = function(self)
						SoundObj:Destroy()
						self = nil
					end
				}
			end

			function BetterCaption:GetCaptionIndex(Caption: MainCaption): number?
				for Index, OtherCaption in self.Captions do
					if OtherCaption.Caption == Caption.Caption then
						return Index
					end
				end
				return
			end

			function BetterCaption:Caption(Text: string, Type: any?, Smooth: boolean?, Sound: {[string]: any}?): MainCaption
				Type = Type or "info"
				if Smooth == nil or typeof(Smooth) ~= "boolean" then
					Smooth = true 
				end
				Sound = typeof(Sound) == "table" and Sound or {
					SoundId = "rbxassetid://3848738542",
					Volume = .1,
					PlaybackSpeed = 1
				}
				Sound.SoundId = Sound.SoundId or "rbxassetid://3848738542"
				if Type ~= "thought" or game.ReplicatedStorage.GameData.Floor.Value ~= "Party" then
					if Text ~= "" and (Text ~= " " and Text ~= nil) then
						local Caption = BetterCaption.MainUI.MainFrame.NewCaption:Clone()
						Caption.Name = "LiveCaption"
						Caption.Visible = true
						Caption.Text = Text
						Caption.TextTransparency = 1
						Caption.TextStrokeTransparency = 1
						Caption.BackgroundTransparency = 1
						Caption.MaxVisibleGraphemes = Smooth and 0 or -1
						local function SetType(Type)
							local first = 1
							local second = 0
							local old = Caption:GetAttribute("Active")
							Caption:SetAttribute("Active", old and old+1 or 0)
							if Type == "thought" then
								Caption.TextColor3 = Color3.fromRGB(229, 224, 218)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Light, Enum.FontStyle.Normal)
								second = .6
							elseif Type == "info" then
								Caption.TextColor3 = Color3.fromRGB(255, 222, 189)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "rgb" then
								local CurrentNumber = Caption:GetAttribute("Active")
								local Gradient = Caption:FindFirstChildOfClass("UIGradient")
								Gradient = Gradient and Gradient:Clone() or Instance.new("UIGradient")
								Gradient.Parent = Caption
								Gradient.Enabled = true
								Gradient.Rotation = 0
								Gradient.Transparency = NumberSequence.new(0)
								Gradient.Color = ColorSequence.new({
									ColorSequenceKeypoint.new(
										0, Color3.fromHSV(0,1,1)
									),
									ColorSequenceKeypoint.new(
										1/6, Color3.fromHSV(1/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1/3, Color3.fromHSV(1/3,1,1)
									),
									ColorSequenceKeypoint.new(
										1/2, Color3.fromHSV(1/2,1,1)
									),
									ColorSequenceKeypoint.new(
										2/3, Color3.fromHSV(2/3,1,1)
									),
									ColorSequenceKeypoint.new(
										5/6, Color3.fromHSV(5/6,1,1)
									),
									ColorSequenceKeypoint.new(
										1, Color3.fromHSV(1,1,1)
									)
								})
								local c; c = RunService.RenderStepped:Connect(function(DeltaTime)
									if CurrentNumber == Caption:GetAttribute("Active") and Caption.Parent then
										local NewKeypoints = {}
										for Key, Value in Gradient.Color.Keypoints do
											local H,S,V = Value.Value:ToHSV()
											NewKeypoints[Key] = ColorSequenceKeypoint.new(Value.Time, Color3.fromHSV((H+DeltaTime)%1,S,V))
										end
										Gradient.Color = ColorSequence.new(NewKeypoints)
									else
										c:Disconnect()
										Gradient:Destroy()
									end
								end)
								Caption.TextColor3 = Color3.new(1, 1, 1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							elseif Type == "warning" then
								Caption.TextColor3 = Color3.fromRGB(225, 177, 138)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								Caption.BackgroundColor3 = Color3.fromRGB(36, 28, 26)
								first = .75
								second = .7
							else
								local Success, Color = pcall(function()
									return typeof(Type) == "Color3" and Type or typeof(Type) == "string" and Color3.fromHex(Type)
								end)
								Caption.TextColor3 = Success and Color or Color3.new(1,1,1)
								Caption.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
								second = .7
							end
							return first, second
						end
						local first, second = SetType(Type)
						Caption.Parent = BetterCaption.MainUI.CaptionHolder
						local CaptionSound = NewSound(Sound)
						CaptionSound:Play()
						TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
							BackgroundTransparency = nil,
							TextTransparency = 0,
							TextStrokeTransparency = nil,
							BackgroundTransparency = first,
							TextStrokeTransparency = second
						}):Play()
						if Smooth then
							TweenService:Create(Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
								MaxVisibleGraphemes = #Text
							}):Play()
							task.delay(.25, function()
								Caption.MaxVisibleGraphemes = -1
							end)
						end
						local MainCaption = {
							Caption = Caption,
							Type = Type,
							Smooth = Smooth,
							Edit = function(self, Text: string, Type: any?, Smooth: boolean?)
								self.Caption.Text = Text
								Type = Type == nil and self.Type or Type
								Smooth = Smooth == nil and self.Smooth or Smooth
								self.Type = Type
								self.Smooth = Smooth
								local first, second = SetType(Type)
								CaptionSound:Play()
								TweenService:Create(Caption, TweenInfo.new(.05, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
									BackgroundTransparency = nil,
									TextTransparency = 0,
									TextStrokeTransparency = nil,
									BackgroundTransparency = first,
									TextStrokeTransparency = second
								}):Play()
								if Smooth then
									self.Caption.MaxVisibleGraphemes = 0
									TweenService:Create(self.Caption, TweenInfo.new(.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
										MaxVisibleGraphemes = #Text
									}):Play()
									task.delay(.25, function()
										self.Caption.MaxVisibleGraphemes = -1
									end)
								end
								return self
							end,
							Destroy = function(self)
								table.remove(BetterCaption.Captions, BetterCaption:GetCaptionIndex(self))
								local Caption = self.Caption
								self = nil
								TweenService:Create(Caption, TweenInfo.new(1.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
									BackgroundTransparency = 1,
									TextTransparency = 1,
									TextStrokeTransparency = 1
								}):Play()
								task.delay(1, function()
									CaptionSound:Destroy()
									Caption:Destroy()
								end)
							end,
							Delay = function(self, Delay: number)
								task.wait(Delay)
								return self
							end
						}
						table.insert(self.Captions, MainCaption)
						return MainCaption
					end
				end
				return nil
			end

			function BetterCaption:ClearAllCaptions()
				for _, Caption in BetterCaption.Captions do
					task.delay(.001, function()
						Caption:Destroy()
					end)
				end
			end

			BetterCaption:Caption(text, "rgb", false)

			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local ReplicatedFirst = game:GetService("ReplicatedFirst")
			local SoundService = game:GetService("SoundService")
			local Players = game:GetService("Players")
			local RunService = game:GetService("RunService")

			local LocalPlayer = Players.LocalPlayer
			local PlayerGui = LocalPlayer.PlayerGui

			task.spawn(function()
				PlayerGui:WaitForChild("DoorsAdmin", 1/0):Destroy()
			end)

			local RemotesFolder = ReplicatedStorage.RemotesFolder
			local GameData = ReplicatedStorage.GameData
			local _Loaded = ReplicatedFirst._Loaded

			local AdminPanelRunCommand = RemotesFolder.AdminPanelRunCommand
			local RequestLocalAsset = RemotesFolder.RequestLocalAsset
			local ToggleLoading = RemotesFolder.ToggleLoading
			local DeathHint = RemotesFolder.DeathHint
			local Cutscene = RemotesFolder.Cutscene
			local Crouch = RemotesFolder.Crouch
			local Lobby = RemotesFolder.Lobby

			local LatestRoom = GameData.LatestRoom

			local function getNilInstanceByName(name: string): Instance?
				for i,v in getnilinstances() do
					if v.Name == name then
						return v
					end
				end
				return nil
			end

			local ready = false
			task.spawn(function()
				while not ready do
					local Main = SoundService:FindFirstChild("Main")
					if Main then
						Main.Volume = 0
					end
					_Loaded.Value = false
					task.wait()
				end
				local MainUI = PlayerGui.MainUI
				local TopbarUI = PlayerGui.TopbarUI
				BetterCaption.MainUI = MainUI
				TopbarUI.ButtonsLeft.PanelButton.Visible = false
				TopbarUI.Topbar.Modifiers.Visible = false
				task.spawn(function()
					local TempMods = MainUI:WaitForChild("TempMods", 1/0)
					if TempMods then
						TempMods:Destroy()
					end
				end)
				SoundService.Main.Volume = 1
				_Loaded.Value = true
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local TravelText = LoadingUI.Loading.LoadingText.TravelText
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while (not Room or Room:GetAttribute("RawName") ~= "Garden_EyestalkStart") and task.wait() do
					local text = `Heading to Eyestalk Chase (Room {LatestRoom.Value})`
					TravelText.Text = text
					TravelText.TravelShadow.Text = text
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
			end)

			task.spawn(function()
				local LoadingUI = PlayerGui.LoadingUI
				local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				while not Room or Room:GetAttribute("RawName") ~= "Garden_EyestalkStart" do
					if not LoadingUI.Enabled then
						LoadingUI.Enabled = true
						LoadingUI.Loading.Visible = true
						LoadingUI.Loading.BackgroundTransparency = 0
						LoadingUI.Loading.FloorBackground.ImageTransparency = 0.75
						LoadingUI.Loading.LoadingText.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.Shadow.ImageTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TextTransparency = 0
						LoadingUI.Loading.LoadingText.TravelText.TravelShadow.TextTransparency = 0
					end
					task.wait()
					Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				end
				ToggleLoading:Fire(false)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = true
			})

			local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

			task.delay(.5, function()
				AdminPanelRunCommand:FireServer("Fly", {})
			end)

			task.spawn(function()
				while task.wait(.1) do
					AdminPanelRunCommand:FireServer("DELETE ALL", {})
				end
			end)

			local Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
			while not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart" do
				Crouch:FireServer(true,true)
				Character:PivotTo(Room and Room:FindFirstChild("Door") and Room.Door:GetPivot() or Character:GetPivot())
				RequestLocalAsset:InvokeServer({{}})
				Room = workspace.CurrentRooms:FindFirstChild(LatestRoom.Value)
				if not (not Room or Room:GetAttribute("RawName") ~= "Mines_SeekStart") then break end
				AdminPanelRunCommand:FireServer("SkipRoom", {})
			end

			AdminPanelRunCommand:FireServer("Fly", {})
			Crouch:FireServer()

			ready = true

			local End = false
			local goodend = true

			task.spawn(function()
				while not End do
					task.wait()
				end
				task.spawn(function()
					if not goodend then return end
					BetterCaption:Caption("Teleporting to Lobby in 30 seconds...", "rgb", false):Delay(30)
					Lobby:FireServer()
				end)
				for _, door in workspace.CurrentRooms:QueryDescendants("> Model > #Door") do
					door:Clone().Parent = door.Parent
					door:Destroy()
				end
				workspace.CurrentRooms.DescendantAdded:Connect(function(door)
					if door.Name == "Door" and door.Parent:IsA("Model") and door.Parent.Parent == workspace.CurrentRooms then
						door:Clone().Parent = door.Parent
						door:Destroy()
					end
				end)
			end)

			AdminPanelRunCommand:FireServer("Apply Changes", {
				Players = {},
				["Max Health"] = 100,
				["Allow Sliding"] = false,
				["Star Shield"] = 0,
				["Speed Boost"] = 0,
				Health = 100,
				["Allow Jumping"] = false,
				["God Mode"] = false
			})

			local texts = table.create(10000, "Teleporting to Lobby in 10 seconds...")
			Character.Humanoid.Died:Once(function()
				goodend = false
				End = true
				firesignal(DeathHint.OnClientEvent, texts, "Glitch")
				task.wait(3.33)
				task.wait(10)
				Lobby:FireServer()
			end)

			Cutscene.OnClientEvent:Connect(function(name)
				if name == "EyestalkOutro" then
					End = true
				end
			end)
			]]

			queue_on_teleport(script)
		end
	})

	OnUnload(function(wasReloaded)
		local success = 0
		local connections = 0
		for _, toggle in Toggles do
			if toggle.Value then
				pcall(toggle.Callback, false)
			end
		end
		for _, connection in Connections do
			pcall(function()
				connection:Disconnect()
				success += 1
			end)
			connections += 1
		end
		if hasteleporthandler then
			clear_teleport_queue()
		end
		restoremetamethods()
		print(`[{Info.AddonTitle}]: {wasReloaded and "reloaded" or "unloaded"}!{connections > 0 and ` (disconnected {success} connections out of {connections})` or ""}`)
	end)
elseif game.GameId == 2440500124 then
	local Camera = workspace.CurrentCamera
	local RemotesFolder = Services.ReplicatedStorage:WaitForChild("RemotesFolder", 999)
	local GameData = Services.ReplicatedStorage:WaitForChild("GameData", 999)
	local Projectiles = Services.ReplicatedStorage:WaitForChild("Projectiles", 999)
	local ReplicaDataModule = require(Services.ReplicatedStorage:WaitForChild("ReplicaDataModule", 999))
	local Floor = GameData:WaitForChild("FloorDestination", 999).Value
	local FloorSpecific = GameData:WaitForChild("FloorDestinationSpecific", 999).Value
	local LatestRoom = GameData:WaitForChild("LatestRoom", 999)
	local OpenedFirstDoor = GameData:WaitForChild("OpenedFirstDoor", 999)
	local PlayerRigs = Services.ReplicatedStorage:WaitForChild("PlayerRigs", 999)

	local TPPath = Services.PathfindingService:CreatePath({
		AgentRadius = 1,
		AgentHeight = 1,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 3
	})

	local Crouch = RemotesFolder.Crouch
	local FireToolProjectile = RemotesFolder.FireToolProjectile
	local DropItem = RemotesFolder.DropItem
	local Revive = RemotesFolder.Revive
	local RequestLocalAsset = RemotesFolder.RequestLocalAsset
	local ObtainGiftedRevive = RemotesFolder.ObtainGiftedRevive
	local Footstep = RemotesFolder.FootstepRemoteThatWeNeed
	local DeathHint = RemotesFolder.DeathHint
	local Statistics = RemotesFolder.Statistics
	local RippleStatistics = RemotesFolder.RippleStatistics
	local MotorReplication = RemotesFolder.MotorReplication
	local ServerTeleported = RemotesFolder.ServerTeleported
	local UpdateMinecartNodes = RemotesFolder.UpdateMinecartNodes
	local MinecartPos = RemotesFolder.MinecartPos
	local MinecartResult = RemotesFolder.MinecartResult
	local ReplicateAnimation = RemotesFolder.ReplicateAnimation
	local TargetCameraDirection = RemotesFolder.TargetCameraDirection
	local Cutscene = RemotesFolder.Cutscene
	local ContinueOrSave = RemotesFolder.ContinueOrSave
	local PlayAgain = RemotesFolder.PlayAgain
	local SurgeRemote = RemotesFolder.SurgeRemote
	local CartControl = RemotesFolder.CartControl

	local LocalPlayer = Services.Players.LocalPlayer
	local PlayerGui = LocalPlayer.PlayerGui
	local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

	local CurrentRooms = workspace:WaitForChild('CurrentRooms', 999)
	local LiveEntities = workspace:WaitForChild('LiveEntities', 999)
	local Drops = workspace:WaitForChild('Drops', 999)
	local Misc = workspace:WaitForChild('Misc', 999)
	
	local teleportdata = Services.TeleportService:GetLocalPlayerTeleportData()
	
	local main_game = PlayerGui:WaitForChild("MainUI", 999):WaitForChild("Initiator", 999):WaitForChild("Main_Game", 999)
	local required_main_game = require(main_game)

	local Connections = {}
	local ItemsFromAddon = {}
	local StuffToRemoveLater = {}

	local thinkanims = {'18885101321', '18885098453', '18885095182'}

	type Weld = {
		Destroy: (self: Weld) -> ()
	}

	function WeldTo(TargetPart: BasePart, Offset: CFrame): Weld
		local Root = Character and Character:WaitForChild("HumanoidRootPart", 10)
		if not Root then return end
		if not TargetPart then return end

		local Weld = {}
		local Connection = nil
		local OldAllowSleep = settings().Physics.AllowSleep

		settings().Physics.AllowSleep = false
		Connection = Services.RunService.Heartbeat:Connect(function()
			if not Character.Parent or not TargetPart.Parent then
				if Weld and Weld.Destroy then Weld:Destroy() end
				return
			end
			local clamp = Vector3.new(math.clamp(TargetPart.AssemblyLinearVelocity.X,-10,10),0,math.clamp(TargetPart.AssemblyLinearVelocity.Z,-10,10))
			Character:PivotTo(TargetPart.CFrame * Offset + clamp / 10)
			Root.AssemblyLinearVelocity = Vector3.zero
			Root.AssemblyAngularVelocity = Vector3.zero
			if sethiddenproperty then
				pcall(sethiddenproperty, Root, "PhysicsRepRootPart", TargetPart)
			end
		end)

		Weld.OldAllowSleep = OldAllowSleep

		function Weld:Destroy()
			if Connection then Connection:Disconnect() end
			if Root then
				Root.AssemblyLinearVelocity = Vector3.zero
				Root.AssemblyAngularVelocity = Vector3.zero
			end
			if sethiddenproperty then
				pcall(sethiddenproperty, Root, "PhysicsRepRootPart", nil)
			end
			self.Destroy = nil
		end

		return Weld
	end

	function inWhatRoom(object: Object): number?
		local parent = object.Parent
		while not parent or parent.Name:match("%d+") ~= parent.Name do
			parent = parent.Parent
		end
		return parent and parent.Parent == CurrentRooms and tonumber(parent.Name)
	end

	function decodeBase64(str: string)
		return buffer.tostring(Services.EncodingService:Base64Decode(buffer.fromstring(str)))
	end

	StuffToRemoveLater.ObtainedRevive = PlayerGui:WaitForChild("MainUI", 99):WaitForChild("ObtainedRevive", 99):Clone()
	StuffToRemoveLater.ObtainedRevive.Confirm.Size = UDim2.fromScale(.3,.2)
	StuffToRemoveLater.ObtainedRevive.Close.Size = UDim2.fromScale(.3,.2)
	StuffToRemoveLater.ObtainedRevive.Confirm.Position = UDim2.fromScale(.3,1)
	StuffToRemoveLater.ObtainedRevive.Close.Position = UDim2.fromScale(.7,1)
	StuffToRemoveLater.ObtainedRevive.Confirm.Text = "KEEP"

	Variables.Keep = StuffToRemoveLater.ObtainedRevive.Confirm:Clone()
	Variables.Keep.Parent = StuffToRemoveLater.ObtainedRevive
	Variables.Keep.AnchorPoint = Vector2.new(.5,1)
	Variables.Keep.Position = UDim2.fromScale(.5,1)
	Variables.Keep.Size = UDim2.fromScale(1/3,.2)
	Variables.Keep.BackgroundColor3 = Color3.fromRGB(165, 168, 207)
	Variables.Keep.Name = "Keep"
	Variables.Keep.Text = "KEEP 1X"
	Variables.Keep = nil

	Variables.pendingGiftedRevives = {}
	Variables.pendingGiftedRevivesALL = {}
	Variables.blacklisted = {}
	Variables.infYield = Instance.new("BindableFunction")

	Variables.disableGifting = false
	function OnReviveObtain(name)
		if Variables.disableGifting or Variables.blacklisted[name] then
			Variables.infYield:Invoke()
			return false
		elseif not (main_game and require(main_game).dead) then
			return false
		end

		local guid = Services.HttpService:GenerateGUID(false)
		local player = Services.Players:FindFirstChild(name)
		Variables.pendingGiftedRevives[name] = Variables.pendingGiftedRevives[name] or {}
		table.insert(Variables.pendingGiftedRevives[name], guid)

		local LiveRevive = PlayerGui.MainUI:FindFirstChild("FriendReviveLive")
		if LiveRevive and LiveRevive:GetAttribute("name") == name then
			LiveRevive.Keep.Text = `KEEP {#Variables.pendingGiftedRevives[name]}X`
		end

		table.insert(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
		local index = table.find(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
		while index and index > 1 do
			index = table.find(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
			task.wait()
		end

		local FriendRevive = ObtainedRevive:Clone()
		FriendRevive:SetAttribute("name", name)
		FriendRevive.Name = "FriendReviveLive"
		FriendRevive.Parent = PlayerGui.MainUI
		FriendRevive.Player.Username.Text = name
		FriendRevive.Keep.Text = `KEEP {#pendingGiftedRevives[name]}X`

		task.spawn(function()
			local success, userId = pcall(function()
				return player and player.UserId or Services.Players:GetUserIdFromNameAsync(name)
			end)
			userId = success and userId
			FriendRevive.Player.PlayerIcon.Image = `rbxthumb://type=AvatarHeadShot&id={userId or 1}&w=150&h=150`
		end)

		FriendRevive.Timer.Text = "inf"
		FriendRevive.Visible = true

		local accepted = nil
		FriendRevive.Confirm.MouseButton1Down:Once(function()
			accepted = 1
			FriendRevive.Visible = false
		end)
		FriendRevive.Keep.MouseButton1Down:Once(function()
			accepted = 2
			FriendRevive.Visible = false
		end)
		FriendRevive.Close.MouseButton1Down:Once(function()
			accepted = false
			FriendRevive.Visible = false
		end)
		index = table.find(Variables.pendingGiftedRevives[name], guid)
		while Variables.pendingGiftedRevives[name] and Variables.pendingGiftedRevives[name][index] == guid and accepted == nil do
			task.wait()
		end
		if not (Variables.pendingGiftedRevives[name] and Variables.pendingGiftedRevives[name][index]) then
			return not (Variables.blacklisted[name] or LocalPlayer:GetAttribute("Alive"))
		end
		if accepted ~= 2 then
			pcall(table.remove, Variables.pendingGiftedRevives[name], index)
			index = table.find(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
			pcall(table.remove, Variables.pendingGiftedRevivesALL, index)
		elseif accepted == false then
			Variables.blacklisted[name] = true
			for _, guid in Variables.pendingGiftedRevives[name] do
				local oIndex = table.find(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
				pcall(table.remove, Variables.pendingGiftedRevives[name], index)
				pcall(table.remove, Variables.pendingGiftedRevivesALL, oIndex)
			end
			Variables.pendingGiftedRevives[name] = {}
		else
			for _, guid in Variables.pendingGiftedRevives[name] do
				local oIndex = table.find(Variables.pendingGiftedRevivesALL, `{name}-[{guid}]`)
				pcall(table.remove, Variables.pendingGiftedRevives[name], index)
				pcall(table.remove, Variables.pendingGiftedRevivesALL, oIndex)
			end
			Variables.pendingGiftedRevives[name] = {}
		end
		return not not accepted
	end

	Connections.CameraChanged = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = workspace.CurrentCamera
	end)

	function isModifierEnabled(modifier)
		return not not(teleportdata and teleportdata.Modifiers and table.find(teleportdata.Modifiers, modifier))
	end

	local ScreenGui, delulucaption, spawncaption, script1
	task.spawn(function()
		ScreenGui = Instance.new('ScreenGui', PlayerGui)
		ScreenGui.Name = 'DeluluCaption'
		ScreenGui.DisplayOrder = PlayerGui.MainUI.DisplayOrder
		ScreenGui.ResetOnSpawn = false
		ScreenGui.IgnoreGuiInset = true
		delulucaption = Module.LoadCustomInstance('https://github.com/tplaygd/Tplays-Addon-Stuff/raw/main/caption.rbxm', "caption.rbxm")

		if delulucaption then
			delulucaption.Parent = ScreenGui
			script1 = Instance.new('LocalScript', delulucaption)
			local v_u_1 = Services.TweenService
			local v_u_2 = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local tbas = Instance.new('Sound')
			tbas.SoundId = 'rbxassetid://6895079853'

			spawncaption = function(p3, p4, p5, p6, p7)
				local v8 = p3:Clone()
				v8.Parent = p4
				v8:WaitForChild('MainText').Text = ''
				local v9 = v8.Size
				v8.Size = UDim2.new(0, 0, 1, 0)
				v8.Visible = true
				Services.SoundService:PlayLocalSound(tbas)
				v_u_1:Create(v8, v_u_2, {
					['Size'] = v9
				}):Play()
				local v10 = Instance.new('Sound')
				v10.Parent = script1
				if p6 ~= nil and p6 ~= 'none' then
					v10.SoundId = p6
				else
					v10.SoundId = 'rbxassetid://7107161936'
				end
				if p7 ~= nil and p7 ~= 'none' then
					v8:WaitForChild('MainText').TextColor3 = p7
				end
				Services.Debris:AddItem(v8, 3.1+1+(0.0175*#p5))
				task.wait(0.4)
				v8:WaitForChild('MainText').Visible = true
				for v11 = 1, #p5 do
					v8:WaitForChild('MainText').Text = p5:sub(1, v11)
					Services.SoundService:PlayLocalSound(v10)
					task.wait(0.0175)
				end
				task.wait(2.5)
				Services.TweenService:Create(v8:WaitForChild('MainText'), TweenInfo.new(0.2), {
					['TextTransparency'] = 1
				}):Play()
				Services.TweenService:Create(v8:WaitForChild('MainText'):WaitForChild('UIStroke'), TweenInfo.new(0.2), {
					['Transparency'] = 1
				}):Play()
				task.wait(0.2)
				v_u_1:Create(v8, v_u_2, {
					['Size'] = UDim2.new(0, 0, 1, 0)
				}):Play()
			end
		end
	end)

	Variables.doorReach = false
	Variables.oldUpValues = {}
	Connections.coolconn = LocalPlayer.CharacterAdded:Connect(function(character)
		main_game = PlayerGui:WaitForChild("MainUI", 999):WaitForChild("Initiator", 999):WaitForChild("Main_Game", 999)
		if Toggles.Freecam.Value then
			Toggles.Freecam:SetValue(false)
		end
		required_main_game = require(main_game)
		if Toggles.Stun.Value then
			Toggles.Stun.Callback(false, true)
		end
		if Toggles.SlideSpeedHack.Value then
			Crouch:FireServer(Character:GetAttribute("Crouching"), true)
		end
		if Toggles.UpsideDown.Value then
			pcall(Toggles.UpsideDown.Callback, false, true)
			task.spawn(function()
				Character:WaitForChild("CollisionPart", 1/0)
				task.delay(.1, Toggles.UpsideDown.Callback, true)
			end)
		end
		Character = character
		if Connections.OnCharacterStun then
			Connections.OnCharacterStun:Disconnect()
		end
		Connections.OnCharacterStun = Character:GetAttributeChangedSignal('Stunned'):Connect(function()
			Toggles.Stun.Callback(Character:GetAttribute('Stunned'), true)
		end)
		Variables.blacklisted = {}
		Variables.pendingGiftedRevives = {}
		Variables.pendingGiftedRevivesALL = {}
	end)

	Connections.OnCharacterStun = Character:GetAttributeChangedSignal('Stunned'):Connect(function()
		Toggles.Stun.Callback(Character:GetAttribute('Stunned'), true)
	end)

	local success, username = pcall(function()
		return Services.Players:GetNameFromUserIdAsync(teleportdata.Host)
	end)

	Groupbox:AddDivider({
		Text = "游戏信息",
		MarginTop = 2,
		MarginBottom = -2
	})
	if teleportdata.Host and success and username then
		local player = Services.Players:GetPlayerByUserId(teleportdata.Host)
		Groupbox:AddLabel('Host UserId: '..teleportdata.Host or "???")
		Groupbox:AddLabel('Host Username: '..Services.Players:GetNameFromUserIdAsync(teleportdata.Host) or "???")
		local status = Groupbox:AddLabel('Status: '..(player and 'In-game' or 'Left'))
		if player then
			Connections.OnHostLeft = Services.Players.ChildRemoved:Connect(function(leftPlayer)
				if leftPlayer == player then
					Connections.OnHostLeft:Disconnect()
					Connections.OnHostLeft = nil
					status:SetText('Status: Left')
				end
			end)
		end
	else
		Groupbox:AddLabel('HOST NOT FOUND')
	end

	Groupbox:AddDivider({
		Margin = -6
	})

	Variables.playersInGame = Groupbox:AddLabel(`Players: {#Services.Players:GetPlayers()}/{#PlayerRigs:GetChildren()}`)
	Connections.OnPlayerLeft = Services.Players.ChildRemoved:Connect(function()
		Variables.playersInGame:SetText(`Players: {#Services.Players:GetPlayers()}/{#PlayerRigs:GetChildren()}`)
	end)

	Groupbox:AddDivider({
		Text = "主界面",
		MarginTop = 2,
		MarginBottom = -2
	})

	Variables.motorReplicaAbuse = {
		methods = {
			HandsUp = {
				number = 72000,
				static = false,
				methodType = "Number"
			},
			Zombie = {
				number = -36000,
				static = false,
				methodType = "Number"
			},
			BodyInLegs = {
				number = 3600,
				static = false,
				methodType = "Number"
			},
			BrokenSpine = {
				number = 1800,
				static = true,
				methodType = "Number"
			},
			Spin = function()
				local currentLVY = 0
				local v1 = os.clock()+1/30
				local v2 = 0
				return Services.RunService.RenderStepped:Connect(function(dt)
					if os.clock() < v1 then v2 += dt return end
					currentLVY = currentLVY+v2*7200*Variables.MotorSpeed.Value
					MotorReplication:FireServer(-currentLVY)
					v1 = os.clock()+1/30
					v2 = 0
				end)
			end,
			CrazySpin = function()
				local currentLVY = 0
				local mode = 1
				local v1 = os.clock()+1/30
				local v2 = 0
				local v3 = -1
				return Services.RunService.RenderStepped:Connect(function(dt)
					if os.clock() < v1 then v2 += dt return end
					currentLVY = currentLVY+v2*7200*Variables.MotorSpeed.Value
					if mode == 1 and currentLVY >= 7200 then
						mode = -1
						currentLVY *= -1
					elseif mode == -1 and currentLVY >= 0 then
						mode = 1
					end
					MotorReplication:FireServer(currentLVY*v3)
					v3 *= -1
					v1 = os.clock()+1/30
					v2 = 0
				end)
			end
		},
		method = "BrokenSpine",
		enabled = false
	}
	Variables.showPathfind = false
	Variables.cogAlt = false
	Variables.slideSH = false
	Variables.noReviveCutscene = false
	Variables.noSpread = false
	Variables.fastThrow = false
	Variables.minecartTp = false
	Variables.propsFastSpeed = {
		Bomb = 300,
		BigBomb = 300,
		Knockbomb = 250,
		GoldBullet = 10000,
		Bullet = 10000,
		PaperPlane = 150
	}
	Variables.hook = hookmetamethod and hookmetamethod(game, "__namecall", function(self, ...)
		local args, method = {...}, getnamecallmethod()
		if self == Crouch and method == "FireServer" then
			if Variables.cogAlt then
				args[1] = true
			end
			if Variables.slideSH then
				args[2] = true
			end
		end
		--[[if not checkcaller() and self == Footstep and method == "FireServer" and antiFigure then
			return
		end]]
		local name = ...
		if not checkcaller() and method == "WaitForChild" then
			if (name == "PathfindNodes" and Variables.showPathfind) or (name == "ReviveCutscene" and Variables.noReviveCutscene) then
				return
			end
		end
		if not checkcaller() and self == MinecartPos and getnamecallmethod() == "FireServer" and Variables.minecartTp then
			local cframe = ...
			local latestroom = LatestRoom.Value
			if latestroom < 50 then
				local room = workspace.CurrentRooms:FindFirstChild(latestroom)
				local door = room and room:FindFirstChild("Door")
				if door then
					cframe = door:GetPivot()
					workspace.CurrentCamera.MinecartRig:PivotTo(cframe)
					door.ClientOpen:FireServer()
				end
			else
				task.delay(.5, function()
					MinecartResult:FireServer("Derail", "NestCutscene")
				end)
			end
			return Variables.hook(self, cframe)
		end
		if Variables.motorReplicaAbuse.enabled and self == MotorReplication and method == "FireServer" then
			local value = Variables.motorReplicaAbuse.methods[Variables.motorReplicaAbuse.method]
			if typeof(value) == "table" and value.methodType == "Number" then
				args[1] = value.number+(not value.static and args[1] or 0)
			elseif not checkcaller() then
				return
			end
		end
		if self == FireToolProjectile and method == "Fire" then
			--args[1] = args[1] == "GoldBullet" and "Bullet" or args[1]
			args[3] = Variables.noSpread and Camera.CFrame.Position or args[3]
			args[4] = Variables.noSpread and Camera.CFrame.LookVector or args[4]
			args[5] = Variables.fastThrow and (Variables.propsFastSpeed[args[1]] or 500) or args[5]
		end
		return Variables.hook(self, unpack(args))
	end)

	Variables.AllPathfindNodes = {}
	CurrentRooms.ChildAdded:Connect(function(room)
		local PathfindNodes = Variables.showPathfind and room:WaitForChild("PathfindNodes", 1)
		if PathfindNodes then
			table.insert(Variables.AllPathfindNodes, PathfindNodes)
			for _, node in PathfindNodes:GetChildren() do
				node.Transparency = .5
			end
		end
	end)

	StuffToRemoveLater.body = Instance.new("BodyVelocity")
	StuffToRemoveLater.body.MaxForce = Vector3.new(1/0, 1/0, 1/0)

	function NoAltFeatures()
		if ADDON_CONFIG.AltFeatures then
			return nil
		else
			return {
				Value = false,
				Disabled = false,
				SetDisabled = function(self, value)
					self.Disabled = value
				end
			}
		end
	end

	function NoAlrAddedFeatures()
		if ADDON_CONFIG.IncludeAddedFeatures then
			return nil
		else
			return {
				Value = false,
				Disabled = false,
				SetDisabled = function(self, value)
					self.Disabled = value
				end
			}
		end
	end

	function FindChair(attachment)
		for _, base in Misc:QueryDescendants(`> #{Floor}OfficeChair > #Base`) do
			local align = base:FindFirstChild("CartAlignPosition")
			local collider = base.Parent:FindFirstChild("Collider")
			if collider and (align or isnetworkowner(collider)) then
				return base.Parent
			end
		end
		return nil
	end

	function FindAlingsForChairOrCart(attachment)
		for _, base in Misc:QueryDescendants(`> #{Floor}OfficeChair > #Base, > #ShoppingCart > #Base, > #TV_Stand > #Base`) do
			local alignPos = base:FindFirstChild("CartAlignPosition")
			local alignRot = base:FindFirstChild("CartAlignOrientation")
			if alignPos and alignRot then
				return alignPos, alignRot, base.Parent
			end
		end
		return nil, nil
	end

	Variables.ConnectingChair = false
	function ConnectChair(chair, promptBlock, restoring)
		if Variables.ConnectingChair then return end
		Variables.ConnectingChair = true
		if restoring then
			while (function()
				for _, descendant in Character:QueryDescendants("> #CollisionPart > #CartTargetAttachment") do
					if descendant:IsA("Attachment") then
						return false
					end
				end
				return true
			end)() do
				chair:PivotTo(Character:GetPivot()+Character:GetPivot().LookVector*5)
				fireproximityprompt(chair.Attachment.CartPrompt)
				task.wait()
			end
		end
		local collider = chair.Collider
		CartControl:FireServer()
		task.wait()
		local doo = true
		task.spawn(function()
			while doo do
				fireproximityprompt(collider.SeatPrompt)
				task.wait()
			end
		end)
		Character:GetAttributeChangedSignal("SeatedInSeat"):Wait()
		doo = false
		Character:SetAttribute("SeatedInSeat", false)
		task.wait()
		if Variables.ACBypassNotify then
			Variables.ACBypassNotify:Destroy()
			Variables.ACBypassNotify = nil
		end
		Library:Notify({
			Title = "Tplay 的插件",
			Description = "反作弊已被绕过！",
			Time = 3
		})
		Variables.ConnectingChair = false
		local val = 0
		Connections.ChairConnection = Services.RunService.Heartbeat:Connect(function(dt)
			val = (val + dt * 3600) % 360
			collider.AssemblyLinearVelocity = Vector3.new(0,10000,0)
			chair:PivotTo(Character:GetPivot())
			Services.RunService.RenderStepped:Wait()
			chair:PivotTo(Character:GetPivot()-Vector3.new(0,-100,0))
		end)
		while Connections.ChairConnection and chair:IsDescendantOf(workspace) and isnetworkowner(promptBlock) and Character.Parent and Character:GetAttribute("SeatedInSeat") ~= nil do
			task.wait()
		end
		if Connections.ChairConnection and chair:IsDescendantOf(workspace) and isnetworkowner(promptBlock) and Character.Parent and Character:GetAttribute("DeathReason") ~= "Impact" then
			Character:SetAttribute("DeathReason", "_Impact")
			Variables.ACBypassNotify = Library:Notify({
				Title = "Tplay 的插件 [警告]",
				Description = "反作弊绕过被破坏了，正在尝试恢复",
				Persist = true
			})
			log("WE CAN RESTORE!!!")
			ConnectChair(chair, promptBlock, true)
		else
			log(Connections.ChairConnection or "nil", chair:IsDescendantOf(workspace), isnetworkowner(promptBlock), Character.Parent or "nil")
			Variables.ACBypassNotify = Library:Notify({
				Title = "Tplay 的插件 [警告]",
				Description = "反作弊绕过被破坏了，再抓一把椅子来恢复",
				Persist = true
			})
		end
		if Connections.ChairConnection then
			Connections.ChairConnection:Disconnect()
			Connections.ChairConnection = nil
		end
	end

	Toggles.AnticheatBypassAndFling = NoAlrAddedFeatures() or ((Floor ~= "Archives" and Floor ~= "Stairwell") and {Value = false}) or Groupbox:AddToggle(prefix..'AnticheatBypassAndFling', {
		Text = '反作弊绕过',
		Tooltip = `Bypasses anticheat with {Floor} Chair`,
		Default = false,
			Callback = function(value, noNotify)
			if value then
				Variables.ACBypassNotify = Library:Notify({
					Title = "Tplay 的插件",
					Description = "抓一把椅子来绕过反作弊",
					Persist = true
				})
				Connections.OnChairGrab = Character.DescendantAdded:Connect(function(descendant)
					if not Connections.ChairConnection and (not Toggles.FlingCreak.Value or Variables.ChairThatFlingsCreak) and descendant:IsA("Attachment") and descendant.Name == "CartTargetAttachment" and descendant.Parent.Name == "CollisionPart" then
						local chair = FindChair(descendant)
						local promptBlock = chair and chair:FindFirstChild("PromptBlocker")
						if promptBlock then
							ConnectChair(chair, promptBlock)
						end
					end
				end)
			else
				if Connections.OnChairGrab then
					Connections.OnChairGrab:Disconnect()
					Connections.OnChairGrab = nil
				end
				if Connections.ChairConnection then
					Connections.ChairConnection:Disconnect()
					Connections.ChairConnection = nil
				end
			end
		end
	})

	Connections.NotificationFix = Services.RunService.RenderStepped:Connect(function()
		if not Toggles.AnticheatBypassAndFling.Value and Variables.ACBypassNotify then
			Variables.ACBypassNotify:Destroy()
			Variables.ACBypassNotify = nil
		end
	end)

	Variables.noclipOn = false
	Variables.Noclip = Library.Toggles.Noclip
	Toggles.AnticheatManipulationAlt = NoAltFeatures() or Groupbox:AddToggle(prefix..'AnticheatManipulationAlt', {
		Text = '反作弊操作替代',
		Tooltip = "反作弊操作的替代方法（来源：Abysall）",
		Default = false,

		Callback = function(value)
			if value then
				StuffToRemoveLater.body.Parent = Character.HumanoidRootPart
				Connections.ACMA = Services.RunService.RenderStepped:Connect(function()
					StuffToRemoveLater.body.Velocity = Camera.CFrame.LookVector * 2.25
				end)
				if Variables.Noclip.Value then
					Variables.noclipOn = true
				else
					pcall(Variables.Noclip.SetValue, Variables.Noclip, true)
				end
				pcall(Variables.Noclip.SetDisabled, Variables.Noclip, true)
			else
				StuffToRemoveLater.body.Parent = nil
				if Connections.ACMA then
					Connections.ACMA:Disconnect()
					Connections.ACMA = nil
				end
				pcall(Variables.Noclip.SetDisabled, Variables.Noclip, false)
				if not Variables.noclipOn then
					pcall(Variables.Noclip.SetValue, Variables.Noclip, false)
				end
				Variables.noclipOn = false
			end
		end
	})

	Variables.Groundskeepers = {}
	Variables.FigureRigs = {}

	Variables.stopTauntTimes = 0
	Variables.lastTaunt = -1/0

	function addGS(gs)
		if gs.Name == "Groundskeeper" and gs:WaitForChild("HumanoidRootPart", 1) then
			table.insert(Variables.Groundskeepers, gs)
			gs:WaitForChild("Head", 1/0).ChildAdded:Connect(function(child)
				if Toggles.GSNotifier.Value and child.Name:sub(1,7) == "gkgrunt" then
					lastTaunt = os.clock()
					Variables.stopTauntTimes += 1
					task.spawn(function()
						local staticTauntTimes = Variables.stopTauntTimes
						while staticTauntTimes == Variables.stopTauntTimes and lastTaunt < os.clock()-3 do
							task.wait()
						end
						if staticTauntTimes == Variables.stopTauntTimes then
							Variables.stopTauntTimes = 0
							if staticTauntTimes >= 3 then
								Library:Notify({
									Title = Info.AddonTitle.." [Groundskeeper]",
									Description = "园丁不再卡住了！",
									Time = 3
								})
							end
						end
					end)
					if Variables.stopTauntTimes == 3 then
						Library:Notify({
							Title = Info.AddonTitle.." [Groundskeeper]",
							Description = "园丁卡住了哈哈",
							Time = 3
						})
					end
				end
			end)
		end
	end

	local function addFR(fr)
		if fr.Name == "FigureRig" and fr:WaitForChild("Root", 1) then
			table.insert(Variables.FigureRigs, fr)
		end
	end

	for _, c in CurrentRooms:QueryDescendants("#Groundskeeper") do
		task.spawn(addGS, c)
	end
	for _, c in CurrentRooms:QueryDescendants("#FigureRig") do
		task.spawn(addFR, c)
	end
	CurrentRooms.DescendantAdded:Connect(addGS)
	CurrentRooms.DescendantAdded:Connect(addFR)
	CurrentRooms.DescendantRemoving:Connect(function(c)
		local foundGS = table.find(Variables.Groundskeepers, c)
		local foundFR = table.find(Variables.FigureRigs, c)
		if foundGS then
			table.remove(Variables.Groundskeepers, foundGS)
		end
		if foundFR then
			table.remove(Variables.FigureRigs, foundFR)
		end
	end)

	function ShouldSpoofGS(hrp)
		for _, gs in Variables.Groundskeepers do
			gs = gs:FindFirstChild("HumanoidRootPart")
			if gs and (gs.Position*Vector3.new(1,5,1)-hrp.Position*Vector3.new(1,5,1)).Magnitude < 90 then
				return true
			end
		end
		return false
	end

	function ShouldSpoofFR(hrp)
		for _, fr in Variables.FigureRigs do
			fr = fr:FindFirstChild("Root")
			if fr and (fr.Position*Vector3.new(1,0,1)-hrp.Position*Vector3.new(1,0,1)).Magnitude < 20 then
				return true
			end
		end
		return false
	end

	Groupbox:AddDivider({
		Margin = -6
	})

	Toggles.NoSpread = NoAlrAddedFeatures() or Groupbox:AddToggle(prefix..'NoSpread', {
		Text = '无扩散',
		Tooltip = '精准投掷道具',
		DisabledTooltip = "当前执行器不支持",
		Disabled = not Variables.hook,
		Default = false,

		Callback = function(value)
			Variables.accurateAim = value
		end
	})
		Toggles.FastThrow = NoAlrAddedFeatures() or Groupbox:AddToggle(prefix..'FastThrow', {
		Text = '快速投掷',
		Tooltip = '像黄金子弹一样快速投掷道具',
		DisabledTooltip = "当前执行器不支持",
		Disabled = not Variables.hook,
		Default = false,

		Callback = function(value)
			Variables.fastThrow = value
		end
	})

	Toggles.DeleteProps = Groupbox:AddToggle(prefix..'DeleteProps', {
		Text = '删除道具',
		Tooltip = '删除你拾取的每个道具（仅战斗模式生效）',

		Callback = function(value)
			if value then
				Connections.DeletePropsConnection = Character.ChildAdded:Connect(function(child)
					if child.Name == "BigPropTool" then
						child.Parent = LocalPlayer.Backpack
					end
				end)
			else
				if Connections.DeletePropsConnection then
					Connections.DeletePropsConnection:Disconnect()
					Connections.DeletePropsConnection = nil
				end
			end
		end
	})

	function GetEquippedTool(player: Player)
		return player and player.Character and player.Character:FindFirstChildOfClass("Tool")
	end

	Variables.reason = {
		Durability = "Gold Blaster should have Durability '1'",
		AlreadyBroken = "Gold Blaster is already broken"
	}

	Groupbox:AddDivider({
		Margin = -6
	})

	Toggles.ShowPathfind = Groupbox:AddToggle(prefix..'ShowPathfind', {
		Text = '显示寻路节点',
		Tooltip = '显示突袭、伏击等实体用来移动的寻路节点',
		DisabledTooltip = '当前执行器不支持',
		Default = false,
		Disabled = not Variables.hook,

		Callback = function(value)
			Variables.showPathfind = value
			if not value then
				for _, PathfindNodes in Variables.AllPathfindNodes do
					PathfindNodes:Destroy()
				end
				Variables.AllPathfindNodes = {}
			end
		end
	})

	Variables.DoorReach = Library.Toggles.DoorReach
	Toggles.DoorReachAlt = NoAltFeatures() or Groupbox:AddToggle(prefix..'DoorReachAlt', {
		Text = '门距离替代',
		DisabledTooltip = '当前执行器不支持',
		Default = false,
		Disabled = not filtergc,

		Callback = function(value)
			Variables.doorReach = value
			main_game:WaitForChild("Updated", 9e9)
			if value then
				if Variables.DoorReach.Value then
					pcall(Variables.DoorReach.SetValue, Variables.DoorReach, false)
				end
				pcall(Variables.DoorReach.SetDisabled, Variables.DoorReach, true)
				local lastOpened = {Time = -1/0}
				while Variables.doorReach do
					local Root = Character and Character.PrimaryPart or Character:FindFirstChild("HumanoidRootPart")
					local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
					local Door = Room and Room:FindFirstChild("Door")
					local DoorPart = Door and Door.PrimaryPart
					if Root and DoorPart and not Door:FindFirstChild("Lock") then
						if (Root.Position-DoorPart.Position).Magnitude < 30 and (not lastOpened.Door == Door or lastOpened.Time < os.clock()-1/3) then
							lastOpened.Door = Door
							lastOpened.Time = os.clock()
							Door.ClientOpen:FireServer()
						end
					end
					Services.RunService.RenderStepped:Wait()
				end
			else
				pcall(Variables.DoorReach.SetDisabled, Variables.DoorReach, false)
			end
		end
	})

	Toggles.FastChairAndCart = Groupbox:AddToggle(prefix..'FastChairAndCart', {
		Text = '快速椅子与推车',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = `Similar to No Acceleration but for chairs and shopping carts`,
		Default = false,
		Disabled = not hookfunction,

		Callback = function(value, noNotify)
			if value then
				Connections.OnChairOrCartGrab = Character.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("Attachment") and descendant.Name == "CartTargetAttachment" and descendant.Parent.Name == "CollisionPart" then
						local alignPos, alingRot, chair = FindAlingsForChairOrCart(descendant)
						if alignPos and alingRot and chair then
							alignPos:Destroy()
							alingRot:Destroy()
							while descendant.Parent do
								chair:PivotTo(Character:GetPivot() * CFrame.new(0,0,-3.75) - Vector3.new(0,1.3,0))
								chair.Base.AssemblyLinearVelocity = Character.PrimaryPart.AssemblyLinearVelocity
								chair.Base.AssemblyAngularVelocity = Character.PrimaryPart.AssemblyAngularVelocity
								Services.RunService.RenderStepped:Wait()
							end
						end
					end
				end)
			else
				if Connections.OnChairOrCartGrab then
					Connections.OnChairOrCartGrab:Disconnect()
					Connections.OnChairOrCartGrab = nil
				end
			end
		end
	})

	Groupbox:AddDivider({
		Margin = -6
	})

	StuffToRemoveLater.NilConstraint = Instance.new("PrismaticConstraint")
	function disconnectDrawer(drawer)
		(drawer:WaitForChild("Constraint", 1) or StuffToRemoveLater.NilConstraint).Enabled = true
		local drawer = Connections.DrawersConnections[drawer]
		for index, connection in drawer or {} do
			connection:Disconnect()
		end
		drawer = nil
	end

	function handleDrawer(drawer)
		local constraint, main
		if drawer:IsA("Model") and drawer.Name == "DrawerContainer" then
			main = drawer:WaitForChild("Main", 1)
			if not main then
				return
			end
			constraint = drawer:WaitForChild("Constraint", 1)
			if not constraint then
				return
			end
		else
			return
		end
		Connections.DrawersConnections = Connections.DrawersConnections or {}
		if Connections.DrawersConnections[drawer] then
			return
		end
		Connections.DrawersConnections[drawer] = {
			AncestryChanged1 = drawer.AncestryChanged:Connect(function()
				if not drawer.Parent then
					disconnectDrawer(drawer)
				end
			end),
			AncestryChanged2 = main.AncestryChanged:Connect(function()
				if not main.Parent then
					disconnectDrawer(drawer)
				end
			end),
			BringLoop = Services.RunService.RenderStepped:Connect(function()
				if isnetworkowner(main) and not main.Anchored then
					constraint.Enabled = false
					if Toggles.AutoFloor.Value then
						main.CFrame = Character:GetPivot()
					else
						main.CFrame = Character:GetPivot()*CFrame.Angles(0,math.rad(180),0)+Character:GetPivot().LookVector*3
					end
					main.AssemblyLinearVelocity = Vector3.zero
					main.AssemblyAngularVelocity = Vector3.zero
				else
					constraint.Enabled = true
				end
			end)
		}
		if Toggles.AutoLoot.Value then
			Connections.DrawersConnections[drawer].AutoLoot = Services.RunService.RenderStepped:Connect(function()
				if isnetworkowner(main) and not main.Anchored then
					local key = drawer:FindFirstChild("KeyObtain")
					local prompt = key and key:FindFirstChild("ModulePrompt", true)
					if prompt then
						fireproximityprompt(prompt)
					end
					local stardust = drawer:FindFirstChild("Stardust", true)
					local prompt = stardust and stardust:FindFirstChild("ModulePrompt", true)
					if prompt then
						fireproximityprompt(prompt)
					end
					local prompt = drawer:FindFirstChild("ActivateEventPrompt", true)
					if prompt then
						fireproximityprompt(prompt)
					end
				end
			end)
		end
	end

	Toggles.BringDrawers = Groupbox:AddToggle(prefix..'BringDrawers', {
		Text = '拉来抽屉',
		Default = false,

		Callback = function(value)
			if value then
				toggleNetworkOwner(true)
				if Toggles.OnlyDrawerWithKey.Disabled then
					Toggles.OnlyDrawerWithKey:SetDisabled(false)
				end
				if Toggles.AutoLoot.Disabled then
					Toggles.AutoLoot:SetDisabled(false)
				end
				for _, drawer in CurrentRooms:QueryDescendants("#DrawerContainer") do
					if Toggles.OnlyDrawerWithKey.Value then
							task.spawn(function()
							local key = drawer:WaitForChild("KeyObtain", 1)
							if key then
								log("FOUND KEY IN DRAWER")
								handleDrawer(drawer)
							end
						end)
					else
						handleDrawer(drawer)
					end
				end
				Connections.DrawerAdded = CurrentRooms.DescendantAdded:Connect(function(drawer)
					if drawer.Name == "DrawerContainer" then
						if Toggles.OnlyDrawerWithKey.Value then
							task.wait(.33)
							local key = drawer:WaitForChild("KeyObtain", 1)
							if key then
								log("FOUND KEY IN DRAWER")
								handleDrawer(drawer)
							end
						else
							handleDrawer(drawer)
						end
					end
				end)
			else
				toggleNetworkOwner(false)
				if not Toggles.OnlyDrawerWithKey.Disabled then
					Toggles.OnlyDrawerWithKey:SetDisabled(true)
				end
				if not Toggles.AutoLoot.Disabled then
					Toggles.AutoLoot:SetDisabled(true)
				end
				if Connections.DrawerAdded then
					Connections.DrawerAdded:Disconnect()
					Connections.DrawerAdded = nil
				end
				for drawer, _ in Connections.DrawersConnections or {} do
					task.spawn(disconnectDrawer, drawer)
				end
				Connections.DrawersConnections = nil
			end
		end
	})

	Toggles.AutoLoot = Groupbox:AddToggle(prefix..'AutoLoot', {
		Text = '自动拾取',
		Default = false,
		Disabled = true,

		Callback = function()
			if Toggles.BringDrawers.Value then
				Toggles.BringDrawers:SetValue(false)
				task.wait()
				Toggles.BringDrawers:SetValue(true)
			end
		end
	})

	Toggles.OnlyDrawerWithKey = (Floor ~= "Hotel" and Floor ~= "Backdoor" and Floor ~= "Endless" and not (Floor == "Ripple" and FloorSpecific == "Daily_Default")) and {Value = false, Disabled = true, SetDisabled = function(self, value) self.Disabled = value end} or Groupbox:AddToggle(prefix..'OnlyDrawerWithKey', {
		Text = '仅带钥匙的抽屉',
		Default = false,
		Disabled = true,

		Callback = function()
			if Toggles.BringDrawers.Value then
				Toggles.BringDrawers:SetValue(false)
				task.wait()
				Toggles.BringDrawers:SetValue(true)
			end
		end
	})

	Variables.Decode = require(Services.ReplicatedStorage.NodeObject.MinecartNodes).Decode
	Variables.MinecartTeleport = Library.Toggles.MinecartTeleport
	Toggles.MinecartChaseSkip = (not Variables.MinecartTeleport and {Value = false}) or NoAltFeatures() or Groupbox:AddToggle(prefix..'MinecartChaseSkip', {
		Text = '跳过矿车追逐战',
		DisabledTooltip = '当前执行器不支持',
		Default = false,
		Disabled = not (hookfunction and Variables.hook and isfunctionhooked and restorefunction),

		Callback = function(value)
			Variables.minecartTp = value
			if value then
				if Variables.MinecartTeleport.Value then
					Variables.MinecartTeleport:SetValue(false)
				end
				Variables.MinecartTeleport:SetDisabled(true)
				local hook; hook = hookfunction(Variables.Decode, function(nodes, folder, start)
					assert(folder, "wheres the folder?!?!") -- yea
					if folder and folder.Parent and (tonumber(folder.Parent.Name) or 0) < 50 then
						return nil
					end
					return hook(nodes, folder, start)
				end)
			else
				Variables.MinecartTeleport:SetDisabled(false)
				if isfunctionhooked and isfunctionhooked(Variables.Decode) then
					restorefunction(Variables.Decode)
				end
			end
		end
	})

	StuffToRemoveLater.partwow = Instance.new("Part")
	StuffToRemoveLater.partwow.Transparency = 1
	StuffToRemoveLater.partwow.Color = Color3.new(1)
	StuffToRemoveLater.partwow.Material = "Glass"
	StuffToRemoveLater.partwow.CanCollide = false
	StuffToRemoveLater.partwow.CanQuery = false
	StuffToRemoveLater.partwow.CanTouch = false
	StuffToRemoveLater.partwow.Anchored = true
	StuffToRemoveLater.partwow.Size = Vector3.new(2,2,1)

	StuffToRemoveLater.highlight = Instance.new("Highlight", StuffToRemoveLater.partwow)
	StuffToRemoveLater.highlight.FillTransparency = .75
	StuffToRemoveLater.highlight.OutlineTransparency = .75
	StuffToRemoveLater.highlight = nil

	local function CreateCoolPart(cframe)
		if not ADDON_CONFIG.Debug then return end
		local supercoolpart = StuffToRemoveLater.partwow:Clone()
		supercoolpart.Parent = workspace
		supercoolpart.CFrame = cframe
		Services.Debris:AddItem(supercoolpart, 3)
	end

	local function getTpFunction()
		local connections = getconnections and getconnections(ServerTeleported.OnClientEvent)
		local connection = connections and connections[1]
		return connection and connection.Function
	end

	Toggles.AntiTeleport = Groupbox:AddToggle(prefix..'AntiTeleport', {
		Text = '反传送 [不稳定]',
		Tooltip = "尝试阻止来自服务器的任何传送",
		Default = false,
		Risky = true,

		Callback = function(value, yea)
			if value then
				Toggles.AntiTeleportRaknet:SetValue(false)
				Toggles.AntiTeleportRaknet:SetDisabled(true)
				Variables.tpFunction = getTpFunction()
				if hookfunction then
					if Variables.tpFunction then
						local tp; tp = hookfunction(Variables.tpFunction, function(...)
							if checkcaller() then
								tp(...)
							end
						end)
					end
					local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
						if not checkcaller() then
							hookfunction(func, function()end)
							Variables.tpFunction = func
						end
						return hook(self, func)
					end)
				end
				Connections.AntiTeleportConnection = Services.RunService.Heartbeat:Connect(function()
					local root = Character and Character:FindFirstChild("HumanoidRootPart")
					local human = Character and Character:FindFirstChild("Humanoid")
					if root and human then
						local oldCFrame = root.CFrame
						local oldVelocity = root.AssemblyLinearVelocity
						Services.RunService.Heartbeat:Wait()
						if (oldCFrame.Position-root.Position).Magnitude > human.WalkSpeed/100*2.5 then
							CreateCoolPart(root.CFrame)
							Character:PivotTo(oldCFrame)
							root.AssemblyLinearVelocity = oldVelocity
						end
					end 
				end)
			else
				Toggles.AntiTeleportRaknet:SetDisabled(false)
				if isfunctionhooked and restorefunction then
					if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
						restorefunction(Variables.tpFunction)
					end
					if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
						restorefunction(ServerTeleported.OnClientEvent.Connect)
					end
				end
				if Connections.AntiTeleportConnection then
					Connections.AntiTeleportConnection:Disconnect()
					Connections.AntiTeleportConnection = nil
				end
				if yea then
					task.spawn(pcall, function()
						Services.RunService.RenderStepped:Wait()
						Toggles.AntiTeleport:SetValue(true)
					end)
				end
			end
		end
	})

	Variables.validPacket = {131, 3}
	local function isPacketValid(packet)
    	for i,v in Variables.validPacket do
        	if v ~= -1 and v ~= packet.AsArray[i] then
        	    return false
        	end
    	end
    	return true
	end

	Variables.confirmed_at = false
	Variables.raknet_at_hook = raknet and raknet.remove_receive_hook and raknet.get_instance_by_id and function(packet)
    	if isPacketValid(packet) then
        	local instance = raknet.get_instance_by_id(1, buffer.readu32(packet.AsBuffer, 3))
        	if instance and instance:IsA("Status") then
        	    local humanoid = instance.Parent
        	    local character = humanoid and humanoid:IsA("Humanoid") and humanoid.Parent
        	    if character and character == Character then
        	        packet:Block()
					Character:PivotTo(Character:GetPivot())
					log("blocked teleport packet")
        	    end
        	end
    	end
	end
	Variables.raknet_at_hooked = false
	Toggles.AntiTeleportRaknet = Groupbox:AddToggle(prefix..'AntiTeleportRaknet', {
		Text = '反传送 [RAKNET]',
		Tooltip = "尝试阻止来自服务器的任何传送（使用 raknet 方式）",
		DisabledTooltip = not Variables.raknet_at_hook and 'Executor is not supported',
		Disabled = not Variables.raknet_at_hook,
		Default = false,
		Risky = true,

		Callback = function(value, yea)
			if value then
				if not Variables.confirmed_at then
					Variables.confirmed_at = nil
					Window:AddDialog("AntiTeleportRaknetWarning", {
						Title = "警告！",
						Description = "此功能因使用 raknet 库可能导致封号，如果仍想使用 raknet 方式请按确认",
						AutoDismiss = true,
						OutsideClickDismiss = true,
						FooterButtons = {
							Cancel = {
								Title = "取消",
								Variant = "Primary",
								Order = 1,
								Callback = function()
									Variables.confirmed_at = false
								end
							},
							Confirm = {
								Title = "确认",
								Variant = "Destructive",
								WaitTime = 2,
								Order = 2,
								Callback = function(self)
									Variables.confirmed_at = true
								end
							}
						}
					})
					while Variables.confirmed_at == nil do task.wait() end
					if not Variables.confirmed_at then
						Toggles.AntiTeleportRaknet:SetValue(false)
						Toggles.AntiTeleportRaknet:SetDisabled(true)
						task.wait(1)
						Toggles.AntiTeleportRaknet:SetDisabled(false)
						return
					end
				end
				Toggles.AntiTeleport:SetValue(false)
				Toggles.AntiTeleport:SetDisabled(true)
				local success, response = pcall(function()
					raknet.addreceivehook(Variables.raknet_at_hook)
					Variables.raknet_at_hooked = true
				end)
				if not success then
					if response:find("raknet not allowed") or not (raknet.is_enabled and raknet.is_enabled()) then
						Library:Notify({
							Title = Info.AddonTitle.." [Error]",
							Description = 'raknet 未启用（请在执行器设置中启用）',
							Time = 4
						})
					else
						Library:Notify({
							Title = Info.AddonTitle.." [Error]",
							Description = '启用反传送时出错',
							Time = 3
						})
					end
					Toggles.AntiTeleportRaknet:SetValue(false)
					return
				end
				Variables.tpFunction = getTpFunction()
				if hookfunction then
					if Variables.tpFunction then
						local tp; tp = hookfunction(Variables.tpFunction, function(...)
							if checkcaller() then
								tp(...)
							end
						end)
					end
					local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
						if not checkcaller() then
							hookfunction(func, function()end)
							Variables.tpFunction = func
						end
						return hook(self, func)
					end)
				end
			else
				Toggles.AntiTeleport:SetDisabled(false)
				if isfunctionhooked and restorefunction then
					if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
						restorefunction(Variables.tpFunction)
					end
					if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
						restorefunction(ServerTeleported.OnClientEvent.Connect)
					end
				end
				if Variables.raknet_at_hooked then
					raknet.removereceivehook(Variables.raknet_at_hook)
					Variables.raknet_at_hooked = false
				end
				if yea then
					task.spawn(pcall, function()
						Services.RunService.RenderStepped:Wait()
						Toggles.AntiTeleportRaknet:SetValue(true)
					end)
				end
			end
		end
	})

	function DoStuffWithAntiTp()
		if Toggles.AntiTeleportRaknet.Value then
			pcall(Toggles.AntiTeleportRaknet.Callback, false, true)
		elseif Toggles.AntiTeleport.Value then
			pcall(Toggles.AntiTeleport.Callback, false, true)
		end
	end

	Variables.walkspeed = 15
	Variables.ladderspeed = 15
	Variables.SpeedHack = Library.Toggles.EnableSpeedHack

	function StartWSConnection()
		Connections.WalkSpeed = Services.RunService.RenderStepped:Connect(function()
			if Character and Character:FindFirstChild("Humanoid") and Character.Parent then
				Character:SetAttribute("SpeedBoostBehind", Variables.ladderspeed-15)
				Character.Humanoid.WalkSpeed = Variables.walkspeed
			end
		end)
	end

	Variables.confirmed_sh = false
	Variables.raknet_sh_hook = raknet and function(packet)
		if packet.PacketId == 0x1B then
			local data = packet.AsBuffer
			buffer.writeu32(data, 1, 0xFFFFFFFF)
			buffer.writeu32(data, 2, 0xFFFFFFFF)
			packet:SetData(data)
		end
	end
	Variables.raknet_sh_hooked = false
	Toggles.RakNetSpeedHack = Groupbox:AddToggle(prefix..'RakNetSpeedHack', {
		Text = '速度作弊 RakNet 方式',
		Tooltip = "我不建议你使用此功能，试试滑行速度作弊方式代替",
		DisabledTooltip = Variables.raknet_sh_hook and 'Please wait...' or 'Executor is not supported',
		Disabled = not Variables.raknet_sh_hook,
		Default = false,
		Risky = true,

		Callback = function(value)
			if value then
				if not Variables.confirmed_sh then
					Variables.confirmed_sh = nil
					Window:AddDialog("RakNetSpeedHackWarning", {
						Title = "警告！",
						Description = "此功能因使用 raknet 库可能导致封号，如果仍想使用 raknet 方式请按确认",
						AutoDismiss = true,
						OutsideClickDismiss = true,
						FooterButtons = {
							Cancel = {
								Title = "取消",
								Variant = "Primary",
								Order = 1,
								Callback = function()
									Variables.confirmed_sh = false
								end
							},
							Confirm = {
								Title = "确认",
								Variant = "Destructive",
								WaitTime = 2,
								Order = 2,
								Callback = function(self)
									Variables.confirmed_sh = true
								end
							}
						}
					})
					while Variables.confirmed_sh == nil do task.wait() end
					if not Variables.confirmed_sh then
						Toggles.RakNetSpeedHack:SetValue(false)
						Toggles.RakNetSpeedHack:SetDisabled(true)
						task.wait(1)
						Toggles.RakNetSpeedHack:SetDisabled(false)
						return
					end
				end
				if Variables.SpeedHack.Value then
					pcall(Variables.SpeedHack.SetValue, Variables.SpeedHack, false)
				end
				pcall(Variables.SpeedHack.SetDisabled, Variables.SpeedHack, true)
				if Toggles.SlideSpeedHack.Value then
					Toggles.SlideSpeedHack:SetValue(false)
				end
				Toggles.SlideSpeedHack:SetDisabled(true)
				Toggles.RakNetSpeedHack:SetDisabled(true)
				local success, response = pcall(function()
					raknet.addsendhook(Variables.raknet_sh_hook)
					Variables.raknet_sh_hooked = true
				end)
				if not success then
					if response:find("raknet not allowed") or not (raknet.is_enabled and raknet.is_enabled()) then
						Library:Notify({
							Title = Info.AddonTitle.." [Error]",
							Description = 'raknet 未启用（请在执行器设置中启用）',
							Time = 4
						})
					else
						Library:Notify({
							Title = Info.AddonTitle.." [Error]",
							Description = '加载速度绕过时出了点问题',
							Time = 3
						})
					end
					Toggles.RakNetSpeedHack:SetDisabled(false)
					Toggles.RakNetSpeedHack:SetValue(false)
					return
				end
				StartWSConnection()
				Character:PivotTo(CFrame.new(0,1500000,0))
				Library:Notify({
					Title = Info.AddonTitle,
					Description = '速度绕过正在加载，请稍候...',
					Time = 3
				})
				while Character.Collision.Position.Y > 1000000 do
					Character.Collision.AssemblyLinearVelocity = Vector3.new(0,0,0)
					Services.RunService.RenderStepped:Wait()
				end
				Toggles.RakNetSpeedHack:SetDisabled(false)
				Library:Notify({
					Title = Info.AddonTitle,
					Description = '速度绕过已加载',
					Time = 2
				})
			else
				if Variables.raknet_sh_hooked then
					raknet.removesendhook(Variables.raknet_sh_hook)
					Variables.raknet_sh_hooked = false
				end
				if Connections.WalkSpeed then
					Connections.WalkSpeed:Disconnect()
				end
				Character:SetAttribute("SpeedBoostBehind", 0)
				Character.Humanoid.WalkSpeed = 15
				pcall(Variables.SpeedHack.SetDisabled, Variables.SpeedHack, false)
				Toggles.SlideSpeedHack:SetDisabled(false)
			end
		end
	})

	Toggles.SlideSpeedHack = NoAlrAddedFeatures() or Groupbox:AddToggle(prefix..'SlideSpeedHack', {
		Text = '速度作弊 滑行方式',
		Tooltip = "mspaint 已有（速度绕过方式由 @nahhthatscrazy 发现）",
		Default = Variables.slideSH,

		Callback = function(value)
			if value then
				Variables.slideSH = true
				if Variables.SpeedHack.Value then
					pcall(Variables.SpeedHack.SetValue, Variables.SpeedHack, false)
				end
				pcall(Variables.SpeedHack.SetDisabled, Variables.SpeedHack, true)
				if Toggles.RakNetSpeedHack.Value then
					Toggles.RakNetSpeedHack:SetValue(false)
				end
				Toggles.RakNetSpeedHack:SetDisabled(true)
				StartWSConnection()
				if Variables.hook then
					Crouch:FireServer(Character:GetAttribute("Crouching"), true)
				else
					while Variables.slideSH do
						Crouch:FireServer(Character:GetAttribute("Crouching"), true)
						task.wait()
					end
				end
			else
				Variables.slideSH = false
				if Connections.WalkSpeed then
					Connections.WalkSpeed:Disconnect()
				end
				Character:SetAttribute("SpeedBoostBehind", 0)
				Character.Humanoid.WalkSpeed = 15
				pcall(Variables.SpeedHack.SetDisabled, Variables.SpeedHack, false)
				Toggles.RakNetSpeedHack:SetDisabled(not raknet)
			end
		end
	})

	Groupbox:AddSlider(prefix.."TWalkSpeed", {
		Text = "行走速度",
		Default = Variables.walkspeed,
		Min = 0,
		Max = 75,
		Rounding = 0,
		Compact = true,
		Callback = function(ws)
			Variables.walkspeed = ws
		end
	})

	Groupbox:AddSlider(prefix.."TLadderSpeed", {
		Text = "爬梯速度",
		Default = Variables.ladderspeed,
		Min = 0,
		Max = 75,
		Rounding = 0,
		Compact = true,
		Callback = function(ls)
			Variables.ladderspeed = ls
		end
	})

	Groupbox:AddDivider({
		Margin = -3
	})

	Variables.reviveGhost1 = Groupbox:AddButton(prefix..'ReviveAsGhost1', {
		Text = '以幽灵复活[貌似无效]',
		Tooltip = "需要在 0 号门执行，效果类似假复活但稳定得多，且不会在任何过场动画后被破坏\n任何过场动画后反作弊绕过都会停止工作（但你仍将无敌）\n要与硬币、星尘、衣柜、抽屉等互动，你需要先获得某种治疗",
		DisabledTooltip = not (require and replicatesignal and fireproximityprompt and firetouchinterest) and 'Executor is not supported' or 'Better Fake Death is already executed',
		DoubleClick = true,
		Disabled = not (require and replicatesignal and fireproximityprompt and firetouchinterest) or LocalPlayer:GetAttribute("_GhostRevived"),

		Func = function()
			if OpenedFirstDoor.Value then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = "第一扇门已打开，此方法不再生效",
					Time = 3
				})
				return
			elseif Floor == "Mines" then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = "此方法在矿山中无效",
					Time = 2
				})
				return
			end
			Variables.reviveGhost1:SetDisabled(true)
			Variables.reviveGhost2:SetDisabled(true)
			Library:Notify({
				Title = Info.AddonTitle,
				Description = '请稍候...',
				Time = 2
			})
			local deadCharacter
			local lock = false
			local room = CurrentRooms:GetChildren()[1]
			local door = room and room.Door
			if door:FindFirstChild("Lock") then
				lock = true
			elseif not door then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = "未找到门",
					Time = 2
				})
				return
			end
			task.spawn(function()
				while not deadCharacter do
					Crouch:FireServer(nil,true)
					task.wait()
				end
			end)
			local key = lock and (Character:FindFirstChild("Key") or LocalPlayer.Backpack:FindFirstChild("Key"))
			if lock and not key then
				local keyObtain = room.Assets.KeyObtain
				Character:PivotTo(keyObtain.Hitbox.CFrame)
				fireproximityprompt(keyObtain.ModulePrompt)
				key = Character:FindFirstChild("Key") or LocalPlayer.Backpack:FindFirstChild("Key")
				while not key do
					task.wait()
					Character:PivotTo(keyObtain.Hitbox.CFrame)
					fireproximityprompt(keyObtain.ModulePrompt)
					key = Character:FindFirstChild("Key") or LocalPlayer.Backpack:FindFirstChild("Key")
				end
				key.Parent = Character
			elseif key then
				key.Parent = Character
			end
			local Delay = os.clock()
			RequestLocalAsset:InvokeServer({{}})
			Delay = os.clock()-Delay
			deadCharacter = Character
			replicatesignal(LocalPlayer.Kill)
			task.wait(math.clamp(Delay-.01, 0, 1/0))
			if lock then
				task.spawn(function()
					deadCharacter:PivotTo(door.Door.CFrame)
					if door.Lock:FindFirstChild("UnlockPrompt") then
						fireproximityprompt(door.Lock.UnlockPrompt)
					else
						for _, prompt in workspace:FindFirstChild("Folder") and workspace.Folder:GetChildren() or {} do
							if prompt:IsA("ProximityPrompt") and prompt.Name == "UnlockPrompt" then
								fireproximityprompt(prompt) -- thanks mspaint devs for making my life harder and placing unlockprompt into folder that was created my mspaint
							end
						end
					end
					while deadCharacter.Parent do
						task.wait()
						deadCharacter:PivotTo(door.Door.CFrame)
						if door.Lock:FindFirstChild("UnlockPrompt") then
							fireproximityprompt(door.Lock.UnlockPrompt)
						else
							for _, prompt in workspace:FindFirstChild("Folder") and workspace.Folder:GetChildren() or {} do
								if prompt:IsA("ProximityPrompt") and prompt.Name == "UnlockPrompt" then
									fireproximityprompt(prompt)
								end
							end
						end
					end
				end)
			else
				task.spawn(function()
					local emptyPart = Instance.new("Part")
					deadCharacter.HumanoidRootPart.CFrame = (door:FindFirstChild("Collision") or door:FindFirstChild("Hidden") or emptyPart).CFrame
					firetouchinterest(deadCharacter.HumanoidRootPart, door:FindFirstChild("Collision") or door:FindFirstChild("Hidden") or emptyPart, 0)
					firetouchinterest(deadCharacter.HumanoidRootPart, door.Collision, 1)
					while deadCharacter.Parent do
						task.wait()
						deadCharacter.HumanoidRootPart.CFrame = (door:FindFirstChild("Collision") or door:FindFirstChild("Hidden") or emptyPart).CFrame
						firetouchinterest(deadCharacter.HumanoidRootPart, door:FindFirstChild("Collision") or door:FindFirstChild("Hidden") or emptyPart, 0)
						firetouchinterest(deadCharacter.HumanoidRootPart, door:FindFirstChild("Collision") or door:FindFirstChild("Hidden") or emptyPart, 1)
					end
					emptyPart:Destroy()
				end)
			end
			local character
			task.spawn(function()
				character = LocalPlayer.CharacterAdded:Wait()
			end)
			replicatesignal(LocalPlayer.Kill)
			while not character and task.wait() do
				replicatesignal(LocalPlayer.Kill)
			end
			if not OpenedFirstDoor.Value then
				reviveGhost1:SetDisabled(false)
				reviveGhost2:SetDisabled(false)
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = '打开第一扇门失败，重试中...',
					Time = 3
				})
				task.wait(.1)
				reviveGhost1.Func()
				return
			end
			LocalPlayer:SetAttribute("Alive", true)
			LocalPlayer:GetAttributeChangedSignal("Alive"):Connect(function()
				LocalPlayer:SetAttribute("Alive", true)
			end)
			LocalPlayer:SetAttribute("_GhostRevived", true)
			local humanoid = character:WaitForChild("Humanoid", 9e9)
			local function nodead()
				pcall(humanoid.SetStateEnabled, humanoid, Enum.HumanoidStateType.Dead, false) -- if i do it using humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) for some reason humanoid will turn into a CoreGui.Obsidian.Frame.Frame
			end
			nodead()
			Services.RunService.RenderStepped:Connect(nodead)
			if _hookmetamethod then
				local oi; oi = _hookmetamethod(humanoid, "__index", function(self, key)
					if not checkcaller() and self == humanoid and key == "Health" then
						local maxhealth = humanoid.MaxHealth
						return maxhealth <= 0 and 1 or maxhealth
					end
					return oi(self, key)
				end)
				local oni; oni = _hookmetamethod(humanoid, "__newindex", function(self, key, new)
					if not checkcaller() and self == humanoid and key == "Health" then
						local maxhealth = humanoid.MaxHealth
						new = maxhealth <= 0 and 1 or maxhealth
					end
					return oni(self, key, new)
				end)
			else
				humanoid.Health = 100
				humanoid:GetPropertyChangedSignal("Health"):Connect(function()
					nodead()
					humanoid.Health = 100
				end)
			end
			if hookfunction and filtergc then
				hookfunction(GetFunction("healthChanged") or function() end, function() end)
			end
			Library:Notify({
				Title = Info.AddonTitle,
				Description = '成功以幽灵复活',
				Time = 3
			})
		end
	})

	Variables.reviveGhost2 = Groupbox:AddButton(prefix..'ReviveAsGhost2', {
		Text = '以幽灵复活',
		Tooltip = "至少需要 1 次复活，效果类似假复活但稳定得多，且不会在任何过场动画后被破坏\n此功能有时会浪费你的复活次数 + 任何过场动画后反作弊绕过都会停止工作（但你仍将无敌）\n要与硬币、星尘、衣柜、抽屉等互动，你需要先获得某种治疗",
		DisabledTooltip = not (require and replicatesignal) and 'Executor is not supported' or 'Better Fake Death is already executed',
		DoubleClick = true,
		Disabled = not (require and replicatesignal) or LocalPlayer:GetAttribute("_GhostRevived"),

		Func = function()
			local data = Services.ReplicatedStorage:FindFirstChild("ReplicaDataModule") and require(Services.ReplicatedStorage.ReplicaDataModule)
			if Floor ~= "Hotel" and Floor ~= "Mines" then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = "此方法在子楼层无效",
					Time = 3
				})
				return
			elseif not OpenedFirstDoor.Value then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = '请先打开第一扇门',
					Time = 2
				})
				return
			elseif not (data and data.data) or (data.data.Revives or 0) <= 0 then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = '你至少需要 1 个复活',
					Time = 3
				})
				return
			end
			Variables.reviveGhost1:SetDisabled(true)
			Variables.reviveGhost2:SetDisabled(true)
			Library:Notify({
				Title = Info.AddonTitle,
				Description = '请稍候...',
				Time = 2
			})
			replicatesignal(LocalPlayer.Kill)
			task.wait(3)
			local character
			task.spawn(function()
				character = LocalPlayer.CharacterAdded:Wait()
			end)
			Revive:FireServer()
			replicatesignal(LocalPlayer.Kill)
			while not character and task.wait() do
				replicatesignal(LocalPlayer.Kill)
			end
			LocalPlayer:SetAttribute("Alive", true)
			LocalPlayer:GetAttributeChangedSignal("Alive"):Connect(function()
				LocalPlayer:SetAttribute("Alive", true)
			end)
			LocalPlayer:SetAttribute("_GhostRevived", true)
			local humanoid = character:WaitForChild("Humanoid", 9e9)
			local function nodead()
				pcall(humanoid.SetStateEnabled, humanoid, Enum.HumanoidStateType.Dead, false) -- if i do it using humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) for some reason humanoid will turn into a CoreGui.Obsidian.Frame.Frame
			end
			nodead()
			Services.RunService.RenderStepped:Connect(nodead)
			if _hookmetamethod then
				local oi; oi = _hookmetamethod(humanoid, "__index", function(self, key)
					if not checkcaller() and self == humanoid and key == "Health" then
						return 100
					end
					return oi(self, key)
				end)
				local oni; oni = _hookmetamethod(humanoid, "__newindex", function(self, key, new)
					if not checkcaller() and self == humanoid and key == "Health" then
						new = 100
					end
					return oni(self, key, new)
				end)
			else
				humanoid.Health = 100
				humanoid:GetPropertyChangedSignal("Health"):Connect(function()
					nodead()
					humanoid.Health = 100
				end)
			end
			if hookfunction and filtergc then
				hookfunction(GetFunction("healthChanged") or function() end, function() end)
			end
			Library:Notify({
				Title = Info.AddonTitle,
				Description = '成功以幽灵复活',
				Time = 3
			})
		end
	})

	function SetMethod(value)
		Variables.reviveGhost1:SetVisible(value == "Method #1")
		Variables.reviveGhost2:SetVisible(value == "Method #2")
	end

	local dropdown = Groupbox:AddDropdown(prefix..'GhostReviveMethod', {
		Text = '方式',
		Values = {
			"Method #1",
			"Method #2",
		},
		Default = "Method #1",
		Callback = SetMethod
	})

	SetMethod(dropdown.Value)

	Groupbox2:AddDivider({
		Text = "便捷功能",
		MarginTop = 2,
		MarginBottom = -2
	})

	Toggles.Freecam = Groupbox2:AddToggle(prefix..'Freecam', {
		Text = '自由视角',
		DisabledTooltip = '当前执行器不支持',
		Default = false,
		Disabled = not (firesignal or require),

		Callback = function(value)
			required_main_game.noclip = value
			required_main_game.freecam = value
			required_main_game.hideplayers = value and -1 or 0
		end
	})

	Groupbox2:AddDivider({
		Margin = -6
	})

	Toggles.NoWardrobeVignette = Groupbox2:AddToggle(prefix..'NoWardrobeVignette', {
		Text = '无衣柜暗角',
		Default = false,

		Callback = function(value)
			local vignette = PlayerGui.MainUI.MainFrame.HideVignette
			if value then
				vignette.Size = UDim2.new(0,0,0,0)
			else
				vignette.Size = UDim2.new(1,0,1,0)
			end
		end
	})

	Toggles.RemoveAmbience = Groupbox2:AddToggle(prefix..'RemoveAmbience', {
		Text = '无随机环境音',
		Default = false,

		Callback = function(value)
			if value then
				Connections.RemoveAmbience = workspace.Terrain.ChildAdded:Connect(function(child)
					if child:IsA('Attachment') then
						child:Destroy()
					end
				end)
			else
				if not Connections.RemoveAmbience then return end
				Connections.RemoveAmbience:Disconnect()
			end
		end
	})

	Toggles.AntiGreenEffect = Groupbox2:AddToggle(prefix..'AntiGreenEffect', {
		Text = '反 Gween 苏打效果',
		Default = false,

		Callback = function(value)
			if value then
				if Camera:FindFirstChild("Im green... No... NOOO!!!!") then
					Camera["Im green... No... NOOO!!!!"]:Destroy()
				end
				Connections.OnGreenEffectAdded = Camera.ChildAdded:Connect(function(child)
					if child.Name == "Im green... No... NOOO!!!!" then
						child:Destroy()
					end
				end)
			elseif Connections.OnGreenEffectAdded then
				Connections.OnGreenEffectAdded:Disconnect()
				Connections.OnGreenEffectAdded = nil
			end
		end
	})

	Variables.EndingCutscene = Floor == "Hotel" and "Elevator1" or Floor == "Mines" and "MinesFinale" or Floor == "Garden" and "GardenEnding"
	if Variables.EndingCutscene then
		Toggles.FastEnding = Groupbox2:AddToggle(prefix.."FastEnding", {
			Text = "快速结局",
			Tooltip = "完成楼层后立即获得奖励",
			Default = false,

			Callback = function(value)
				if value then
					Connections.OnCutsceneFPA = Cutscene.OnClientEvent:Connect(function(name)
						if name == Variables.EndingCutscene then
							task.wait(.1)
							Statistics:FireServer()
						end
					end)
				else
					if Connections.OnCutsceneFPA then
						Connections.OnCutsceneFPA:Disconnect()
					end
				end
			end
		})
	end

	Toggles.NoReviveCutscene = Groupbox2:AddToggle(prefix..'NoReviveCutscene', {
		Text = '无复活过场',
		Default = false,

		Callback = function(value)
			Variables.noReviveCutscene = value
		end
	})

	Toggles.NoMedalAutoclip = Groupbox2:AddToggle(prefix..'NoMedalAutoclip', {
		Text = '无 Medal 自动剪辑',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = '当你被某人杀死或通关时禁用 Medal 自动剪辑（可在 medal 设置中为 roblox 禁用自动剪辑，此功能仅用于测试）',
		Default = false,
		Disabled = not hookfunction or not restorefunction,

		Callback = function(value)
			if value then
				local realPrint; realPrint = hookfunction(print, function(...)
					local args = {...}
					if not checkcaller() and args[1] == "[_MAPIEvent][v1/event/invoke]" then
						local success, result = pcall(function()
							return Services.HttpService:JSONDecode(decodeBase64(args[2]))
						end)
						result = success and result
						if result and typeof(result.triggerActions) == "table" and table.find(result.triggerActions, "SaveClip") then
							return
						end
					end
					return realPrint(...)
				end)
			else
				if isfunctionhooked(print) then
					restorefunction(print)
				end
			end
		end
	})

	Variables.ClientFuncRemote = Services.ReplicatedStorage:FindFirstChild("FloorReplicated")
	Variables.ClientFuncRemote = Variables.ClientFuncRemote and Variables.ClientFuncRemote:FindFirstChild("ClientRemote")
	Variables.ClientFuncRemote = Variables.ClientFuncRemote and Variables.ClientFuncRemote:FindFirstChild("StreamVoteClientFunction")
	Variables.ClientFuncRemote = Variables.ClientFuncRemote and Variables.ClientFuncRemote:FindFirstChild("Remote")
	Variables.currentFuncToHook = Variables.ClientFuncRemote and getconnections(Variables.ClientFuncRemote.OnClientEvent)[1].Function
	Toggles.NoRandomClientEvents = not Variables.ClientFuncRemote and {Value = false} or Groupbox2:AddToggle(prefix..'NoRandomClientEvents', {
		Text = '无随机客户端事件',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = '禁用所有随机客户端事件（混沌模式）',
		Default = false,
		Disabled = not (hookfunction and restorefunction),

		Callback = function(value)
			if value then
				local randomConnect, randomConnect = hookfunction(Variables.ClientFuncRemote.OnClientEvent.Connect, function(self, func)
					if not checkcaller() then
						hookfunction(func, function()end)
						currentFuncToHook = func
					end
					return randomConnect(self, func)
				end)
			else
				if Variables.ClientFuncRemote and isfunctionhooked(Variables.ClientFuncRemote.OnClientEvent and Variables.ClientFuncRemote.OnClientEvent.Connect or function()end) then
					restorefunction(Variables.ClientFuncRemote.OnClientEvent.Connect)
				end
				if isfunctionhooked(Variables.currentFuncToHook or function()end) then
					restorefunction(Variables.currentFuncToHook)
				end
			end
		end
	})

	Groupbox2:AddDivider({
		Margin = -6
	})

	function rn2ht(c)
		return 10+(10/3-10)*c/100
	end

	function update(arg)
		if Variables.annoying_notification then
			if Floor == "Hotel" then
				Variables.annoying_notification:ChangeDescription(`Current hide time: {arg==50 and 20 or arg==100 and "Infinite" or math.clamp(math.round((rn2ht(arg)+(arg>=90 and 1.2 or 0))*1000)/1000, -1/0, isModifierEnabled("HideTime") and 4 or 1/0)}`)
			elseif Floor == "Mines" then
				Variables.annoying_notification:ChangeDescription(`Current hide time: {math.clamp(math.round((rn2ht(arg)+(arg>=61 and 1.4 or 0))*1000)/1000, -1/0, isModifierEnabled("HideTime") and 4 or 1/0)}`)
			end
		end
	end

	Toggles.CurrentHideTime = Floor ~= "Hotel" and Floor ~= "Mines" and {Value = false} or Groupbox2:AddToggle(prefix..'CurrentHideTime', {
		Text = '当前隐藏时间',
		Default = false,

		Callback = function(value)
			if value then
				Variables.annoying_notification = Library:Notify({
					Title = Info.AddonTitle,
					Description = '当前隐藏时间: ?',
					Persist = true
				})
				update(LatestRoom.Value)
				Connections.HideTimeChanged = CurrentRooms.ChildAdded:Connect(function(child)
					update(LatestRoom.Value)
				end)
			else
				if Variables.annoying_notification then
					Variables.annoying_notification:Destroy()
				end
				if Connections.HideTimeChanged then
					Connections.HideTimeChanged:Disconnect()
				end
			end
		end
	})

	Toggles.HidingRoomNotify = Groupbox2:AddToggle(prefix..'HidingRoomNotify', {
		Text = '隐藏房间通知',
		Tooltip = '可能预测突袭或伏击何时生成',
		Default = false,

		Callback = function(value)
			if value then
				Connections.EntityPrediction = CurrentRooms.ChildAdded:Connect(function(child)
					if child:GetAttribute('HidingRoom') and not workspace:FindFirstChild('RushMoving') and not workspace:FindFirstChild('AmbushMoving') then
						Library:Notify({
							Title = Info.AddonTitle,
							Description = '下一个房间是隐藏房间',
							Time = 2
						})
					end
				end)
			else
				if not Connections.EntityPrediction then return end
				Connections.EntityPrediction:Disconnect()
			end
		end
	})

	Groupbox2:AddDivider({
		Margin = -6
	})

	task.spawn(function()
		Variables.CARRemote = Services.ReplicatedStorage:WaitForChild("ClientAnimationReceiver", 1/0):WaitForChild("RemoteEvent", 1/0)
	end)

	Toggles.GSNotifier = Groupbox2:AddToggle(prefix..'GSNotifier', {
		Text = '园丁通知器',
		DisabledTooltip = '请稍候...',
		Tooltip = '当园丁想要杀死或杀死了某人时收到通知',
		Default = false,
		Disabled = not Variables.CARRemote,
	})

	function playerName(player)
		return `{player.DisplayName}{player.DisplayName == player.Name and "" or ` (@{player.Name})`}`
	end

	function getNameFromPartInLookAtAction(part)
		local player = part and part.Parent and Services.Players:GetPlayerFromCharacter(part.Parent)
		if player then
			return playerName(player)
		elseif part and part.Name == "Root" and part.Parent and part.Parent.Name == "Mandrake" then
			return "Mandrake"
		else
			return "Someone"
		end
	end

	task.spawn(function()
		while not Variables.CARRemote do
			task.wait()
		end
		Toggles.GSNotifier:SetDisabled(false)
		Connections.GroundskeeperWatcher = Variables.CARRemote.OnClientEvent:Connect(function(action, _, name, part)
			if not Toggles.GSNotifier.Value then return end
			if action == "ClientAction" and name == "LookAt" then
				Variables.lastLookAt = part
			elseif action == "PlayAnimation" then
				if name == "start_sprint" then
					Variables.sprintTo = Variables.lastLookAt
					Library:Notify({
						Title = Info.AddonTitle.." [Groundskeeper]",
						Description = `Groundskeeper is sprinting to {getNameFromPartInLookAtAction(Variables.lastLookAt)}!`,
						Time = 3,
					})
				elseif name == "end_sprint" then
					Library:Notify({
						Title = Info.AddonTitle.." [Groundskeeper]",
						Description = sprintTo and `Groundskeeper doesn't sprint to {getNameFromPartInLookAtAction(Variables.sprintTo)} now` or "Groundskeeper doesn't sprint now",
						Time = 3,
					})
					Variables.sprintTo = nil
				elseif name == "crucifix" then
					Library:Notify({
						Title = Info.AddonTitle.." [Groundskeeper]",
						Description = `Someone used crucifix on Groundskeeper, wtf?????`,
						Time = 3,
					})
					Variables.sprintTo = nil
				end
			elseif action == "StopAllAnimations" and not Variables.lastLookAt and Variables.sprintTo then
				Library:Notify({
					Title = Info.AddonTitle.." [Groundskeeper]",
					Description = `{getNameFromPartInLookAtAction(Variables.sprintTo)} was killed by Groundskeeper`,
					Time = 3,
				})
				Variables.sprintTo = nil
			end
		end)
	end)

	Variables.MonumentNotifier = false
	Toggles.MonumentNotifier = Groupbox2:AddToggle(prefix..'MonumentNotifier', {
		Text = '纪念碑通知器',
		Tooltip = '当纪念碑杀死某人时收到通知',
		Default = false,

		Callback = function(value)
			Variables.MonumentNotifier = Value
		end
	})

	Connections.MonumentWatcher = ReplicateAnimation.OnClientEvent:Connect(function(character, animation)
		if character ~= Character and Variables.MonumentNotifier then
			local player = Services.Players:GetPlayerFromCharacter(character)
			local isMonumentAnim = animation.Parent and animation.Parent.Name == "MonumentClient"
			if player and isMonumentAnim and animation.Name == "KillPlayerAnimation" then
				Library:Notify({
					Title = Info.AddonTitle.." [Monument]",
					Description = `{playerName(player)} was killed by Monument`,
					Time = 3,
				})
			end
		end
	end)

	Groupbox2:AddDivider({
		Margin = -6
	})

	Variables.betterObtain = false
	Variables.currentFunction = getcallbackvalue or getcallbackvalue(ObtainGiftedRevive, "OnClientInvoke") or function(...)end
	Variables.obtain = hookmetamethod and hookmetamethod(game, "__newindex", function(...)
		local self, key, originalFunc = ...
		if not checkcaller() and self == ObtainGiftedRevive and key == "OnClientInvoke" then
			if Variables.betterObtain then
				hookfunction(originalFunc, OnReviveObtain)
			end
			Variables.currentFunction = originalFunc
		end
		return Variables.obtain(...)
	end)

	Toggles.BetterRevivesObtain = Groupbox2:AddToggle(prefix..'BetterRevivesObtain', {
		Text = '更好的复活获取',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = '让你保留玩家赠送的复活，并可多次接收复活礼物而不会被门取消',
		Default = Variables.betterObtain,
		Disabled = not (Variables.obtain and restorefunction),

		Callback = function(value)
			Variables.betterObtain = value
			local success, hooked = pcall(isfunctionhooked, Variables.currentFunction)
			hooked = success and hooked
			if value and not hooked then
				hookfunction(Variables.currentFunction, OnReviveObtain)
			elseif not value and hooked then
				restorefunction(Variables.currentFunction)
			end
			task.spawn(function()
				if Variables.disableGifting then
					Toggles.DisableReviveGifting:SetValue(false)
				end
				Toggles.DisableReviveGifting:SetDisabled(not value)
				Variables.disableGifting = false
			end)
		end
	})

	Toggles.DisableReviveGifting = Groupbox2:AddToggle(prefix..'DisableReviveGifting', {
		Text = '禁用复活赠送',
		Tooltip = '阻止玩家赠送你复活',
		Default = false,
		Disabled = true,

		Callback = function(value)
			Variables.disableGifting = value
		end
	})

	Variables.adminLoaded = false

	if isModifierEnabled("AdminPanel") then
		local hook2; hook2 = hookmetamethod and hookmetamethod(game, '__index', function(...)
			local self, key = ...
			if self == game and key == 'GameId' and not checkcaller() and Variables.adminLoaded then
				return 3833818265
			end
			return hook2(...)
		end)

		Variables.admin = PlayerGui:FindFirstChild('DoorsAdmin')
		local Event = RemotesFolder.AdminPanelRunCommand
		local Stuff = {}

		function SetDisabled(bool)
			for name, stuff in Stuff do
				stuff:SetDisabled(bool)
			end
		end

		PlayerGui.ChildAdded:Connect(function(child)
			if child.Name == 'DoorsAdmin' and not admin then
				Variables.admin = child
				SetDisabled(false)
				Stuff.AdminPanelDebug:SetDisabled(false)
				Variables.admin.AncestryChanged:Once(function()
					Variables.admin = PlayerGui:FindFirstChild("DoorsAdmin")
					Variables.adminLoaded = not not Variables.admin
					SetDisabled(not Variables.admin)
				end)
			end
		end)

		Groupbox2:AddDivider({
			Text = "管理员面板",
			MarginTop = 2,
			MarginBottom = -2
		})

		Stuff.AdminPanelDebug = Groupbox2:AddButton(prefix..'AdminPanelDebug', {
			Text = '加载调试管理面板',
			DisabledTooltip = '无管理面板',
			Tooltip = '在管理面板中添加调试与开发内容',
			DoubleClick = true,
			Disabled = not Variables.admin,
			Func = function()
				if Variables.adminLoaded then return end
				Stuff.AdminPanelDebug:SetDisabled(true)
				Variables.adminLoaded = true
				ItemsFromAddon = {}
				LocalPlayer:SetAttribute('ServerAdmin', 4)
				function AddItem(item, name, icon)
					if Variables.admin.AdminPanel.Items:FindFirstChild(item) then
						logprint(item, "already exist")
						return
					end
					local itemFolder = Instance.new('Folder', Variables.admin.AdminPanel.Items)
					itemFolder.Name = item
					itemFolder:SetAttribute('DisplayName', `{name} [unavailable]`)
					itemFolder:SetAttribute('Image', icon)
					ItemsFromAddon[#ItemsFromAddon+1] = itemFolder
				end
				AddItem('Stem', 'Stem', 'rbxassetid://80334088426896')
				AddItem('SecretCD', 'Disc', 'rbxassetid://102651623741266')
				AddItem('CartPushTool', 'CartPushTool', 'rbxassetid://14098615241')
				AddItem('GweenSodaPack', 'Pack of Gween Soda', 'rbxassetid://75397946540493')
				AddItem('LargeScrew', 'Large Screw', 'rbxassetid://108745295669342')
				AddItem('BrokenMonitor', 'Broken Monitor', 'rbxassetid://122841415160190')
				AddItem('JerryCan', 'Jerry Can', 'rbxassetid://112188613409282')
				AddItem('DinkyLamp', 'Lamp', 'rbxassetid://94390736027821')
				AddItem('AbrahamHat', 'Damaged Hat', 'rbxassetid://127613603093961')
				AddItem('BottleCrate', 'Crate of Bottles', 'rbxassetid://128967620334283')
				AddItem('Flares', 'Flare', 'rbxassetid://131318338880701')
				AddItem('Briefcase', 'Briefcase', 'rbxassetid://138634158890068')
				AddItem('HoneyPot', 'Honey Pot', 'rbxassetid://84825411467075')
				AddItem('PaperPlane', 'Paper Plane', 'rbxassetid://80334088426896')
				AddItem('WaterCup', 'Water Cup', 'rbxassetid://71060879079691')
				AddItem('ArchivesTicket', 'Ticket', 'rbxassetid://116552699534329')
				AddItem('FihFlakes', 'Fih Flakes', 'rbxassetid://121885940364750')
				AddItem('HonchoCoffee', 'Honcho Mug', 'rbxassetid://99451032775084')
				AddItem('SallyToy', 'Sally\'s Toy', 'rbxassetid://126510979761292')
				AddItem('CartToGo', 'Cart-to-Go', 'rbxassetid://81829195761498')
				AddItem('Candy', 'Candy', 'rbxassetid://91226846785149')
				AddItem('CandyBag', 'Candy Bag', 'rbxassetid://88108365460057')
				AddItem('Buddy', 'Buddy', 'rbxassetid://96164691124017')
				AddItem('Lotus', 'Lotus', 'rbxassetid://121905075599624')
				AddItem('LotusPetal', 'Lotus Petal', 'rbxassetid://82584389669499')
				AddItem('Scanner', 'NVCS-3000', 'rbxassetid://11374263930')
				Variables.admin.AdminPanel.PanelClient.Enabled = false
				Variables.admin.Container.Pages:ClearAllChildren()
				local lol = Variables.admin.Container.TabButtons.UIListLayout:Clone()
				Variables.admin.Container.TabButtons:ClearAllChildren()
				lol.Parent = Variables.admin.Container.TabButtons
				Variables.admin.AdminPanel.PanelClient.Enabled = true
				Library:Notify({
					Title = Info.AddonTitle,
					Description = '调试管理面板加载成功',
					Time = 3
				})
			end
		})

		Stuff.BypassAnticheat = Groupbox2:AddButton(prefix..'BypassAnticheat', {
			Text = '绕过反作弊',
			DisabledTooltip = '无管理面板',
			DoubleClick = true,
			Disabled = not Variables.admin,
			Func = function()
				Event:FireServer(
					"Fly",
					{}
				)
				while not required_main_game.noclip do task.wait() end
				required_main_game.noclip = false
				required_main_game.freecam = false
				required_main_game.hideplayers = 0
			end
		})

		local selected_players = nil

		Stuff.Players = Groupbox2:AddDropdown(prefix..'PlayersAdminPanel', {
			SpecialType = 'Player',
			Searchable = true,
			Multi = true,
			Text = '玩家',
			DisabledTooltip = '无管理面板',
			Default = {},
			Disabled = not Variables.admin,
			Callback = function(value)
				selected_players = value
			end
		})

		Stuff.LagPlayer = Groupbox2:AddButton(prefix..'LagPlayer', {
			Text = '卡顿',
			DisabledTooltip = '无管理面板',
			Tooltip = '让玩家卡顿',
			DoubleClick = true,
			Disabled = not Variables.admin,
			Func = function()
				local PlayersNames = {}

				for player, _ in selected_players do
					PlayersNames[player.Name] = player.Name
				end

				for _ = 1,100 do
					Event:FireServer("GlitchPlayer", {
						Players = PlayersNames
					})
				end
			end
		})

		Stuff.LagAll = Groupbox2:AddButton(prefix..'LagAll', {
			Text = '全员卡顿',
			DisabledTooltip = '无管理面板',
			Tooltip = '让所有玩家卡顿（除你以外）',
			DoubleClick = true,
			Disabled = not Variables.admin,
			Func = function()
				local _Players = Services.Players:GetPlayers()
				local PlayersNames = {}

				for _, player in _Players do
					if player ~= LocalPlayer then
						PlayersNames[player.Name] = player.Name
					end
				end

				for _ = 1,100 do
					Event:FireServer("GlitchPlayer", {
						Players = PlayersNames
					})
				end
			end
		})
	end

	Groupbox2:AddDivider({
		Text = "客户端",
		MarginTop = 2,
		MarginBottom = -2
	})

	local input

	local function getTexts(text)
		texts = text:split(";")
		local newtexts = {}
		for _, text in texts do
			if text:sub(1,1):match("%s") and text:sub(2):match("%S") then
				table.insert(newtexts, text:sub(2))
			elseif text:match("%S") then
				table.insert(newtexts, text)
			end
		end
		return newtexts
	end

	Groupbox2:AddButton(prefix.."ModLuckyInspect", {
		Text = "修改幸运皮肤检视",
		DisabledTooltip = "当前执行器不支持",
		Tooltip = "修改检视带有'幸运'皮肤物品后字幕中显示的文本（丢弃物品可重置文本)",
		Disabled = not setupvalue,
		Func = function()
			local tool = GetEquippedTool(LocalPlayer)
			if tool and (tool:GetAttribute("ToolSkin") or ""):match("Skin_%a+_Lucky") then
				setupvalue(require(tool["*ToolClientFunctions"]).Inspect, 2, input.Value:match("%S") and getTexts(input.Value) or {
					"Text 1",
					"Text 2",
					"Text 3"
				})
			elseif not tool then
				Library:Notify({
					Title = Info.AddonTitle,
					Description = "未装备物品",
					Time = 2
				})
			else
				Library:Notify({
					Title = Info.AddonTitle,
					Description = "物品未装备'幸运'皮肤",
					Time = 3
				})
			end
		end
	})

	input = Groupbox2:AddInput(prefix.."ModLuckyInspectTexts", {
		Text = "文本",
		DisabledTooltip = "当前执行器不支持",
		Placeholder = "Text 1; Text 2; Text 3",
		Disabled = not setupvalue,
		ClearTextOnFocus = false,
	})

	Groupbox2:AddDivider({
		Text = "恶搞",
		MarginTop = 2,
		MarginBottom = -2
	})

	Toggles.Stun = Groupbox2:AddToggle(prefix..'Stun', {
		Text = '眩晕',
		Enabled = false,

		Callback = function(value, force)
			if force then return end
			if value then
				Character:SetAttribute('Stunned', true)
			else
				Character:SetAttribute('Stunned', false)
			end
		end
	})

	Toggles.ThinkingAnimation = Groupbox2:AddToggle(prefix..'ThinkingAnimation', {
		Text = '思考动画',
		Enabled = false,

		Callback = function(value)
			if value then
				local animation = Instance.new('Animation')
				animation.AnimationId = 'rbxassetid://' .. thinkanims[math.random(1, #thinkanims)]
				Variables.animtrack = Character:FindFirstChildOfClass('Humanoid'):LoadAnimation(animation)
				Variables.animtrack.Looped = true
				Variables.animtrack:Play()
			else
				if Variables.animtrack then
					Variables.animtrack:Stop()
					Variables.animtrack:Destroy()
				end
			end
		end
	})

	Variables.CollisionOffsetGodmode = Library.Toggles.CollisionOffsetGodmode
	Variables.CollisionOffsetAutomatic = Library.Toggles.CollisionOffsetAutomatic
	Variables.UpsideDownEnabled = false
	Toggles.UpsideDown = Groupbox2:AddToggle(prefix..'UpsideDown', {
		Text = '上下颠倒',
		Tooltip = '禁用位置偏移以防止 bug，非常不稳定',
		Default = false,
		Risky = true,

		Callback = function(value, respawn)
			if value and not Variables.UpsideDownEnabled then
				Variables.UpsideDownEnabled = true
				if Variables.CollisionOffsetGodmode.Value then
					Variables.CollisionOffsetGodmode:SetValue(false)
				end
				if Variables.CollisionOffsetAutomatic.Value then
					Variables.CollisionOffsetAutomatic:SetValue(false)
				end
				if Toggles.CollisionOffsetGodmodeAlt.Value then
					Toggles.CollisionOffsetGodmodeAlt:SetValue(false)
				end
				Variables.CollisionOffsetGodmode:SetDisabled(true)
				Variables.CollisionOffsetAutomatic:SetDisabled(true)
				Toggles.CollisionOffsetGodmodeAlt:SetDisabled(true)
				Character.HumanoidRootPart.Orientation += Vector3.new(0,0,180)
				Connections.UpsideDownConnection = Services.RunService.RenderStepped:Connect(function()
					pcall(function()
						Character.LowerTorso.Root.C0 = CFrame.new(0, 1.206, 0)*CFrame.Angles(0,0,math.rad(180))
					end)
				end)
			elseif not value and Variables.UpsideDownEnabled then
				Variables.UpsideDownEnabled = false
				Variables.CollisionOffsetGodmode:SetDisabled(false)
				Variables.CollisionOffsetAutomatic:SetDisabled(false)
				Toggles.CollisionOffsetGodmodeAlt:SetDisabled(false)
				if Connections.UpsideDownConnection then
					Connections.UpsideDownConnection:Disconnect()
				end
				if not respawn then
					Character.HumanoidRootPart.Orientation += Vector3.new(0,0,180)
					Character.LowerTorso.Root.C0 = CFrame.new(0, -1.206, 0)
				end
			end
		end
	})

	Groupbox2:AddDivider({
		Margin = -6
	})

	local WalkSpoofTable = {
		Methods = {
			ReallyFast = {
				Speed = "Framerate"
			},
			AnnoyingFootsteps = {
				Speed = "Framerate",
				Weight = 0
			},
			InvertedWalk = {
				Speed = "Inverted"
			},
			NoAnimation = {
				Speed = 0,
				Weight = 0
			}
		},
		Method = "NoAnimation"
	}

	local function getMethodValues()
		return WalkSpoofTable.Methods[WalkSpoofTable.Method]
	end

	local selfDontSpoof
	Toggles.WalkAnimSpoof = Groupbox2:AddToggle(prefix..'WalkAnimSpoof', {
		Text = '行走动画伪造',
		Tooltip = '让你的角色走路方式不同',
		Enabled = false,

		Callback = function(value)
			if value then
				Connections.WalkAnimSpoofConnection = Services.RunService.PreAnimation:Connect(function(dt)
					local forward = required_main_game.animations.Forward
					local vals = getMethodValues()
					if selfDontSpoof then
						Services.RunService.PostSimulation:Wait()
					end
					if vals.Speed then
						forward:AdjustSpeed(vals.Speed == "Framerate" and 1/dt or vals.Speed == "Inverted" and -forward.Speed or vals.Speed)
					end
					if vals.Weight then
						forward:AdjustWeight(vals.Weight)
					end
				end)
			else
				if Connections.WalkAnimSpoofConnection then
					Connections.WalkAnimSpoofConnection:Disconnect()
					Connections.WalkAnimSpoofConnection = nil
				end
			end
		end
	})

	Toggles.DontShowSpoofedWalkAnim = Groupbox2:AddToggle(prefix..'DontShowSpoofedWalkAnim', {
		Text = '不对自己伪造',
		Tooltip = "不会改变你自己的行走动画",
		Enabled = false,

		Callback = function(value)
			selfDontSpoof = value
		end
	})

	local MethodsIndexWalk = {}
	for index, _ in WalkSpoofTable.Methods do
		table.insert(MethodsIndexWalk, index)
	end

	Groupbox2:AddDropdown(prefix..'WalkMethods', {
		Multi = false,
		Text = '方式',
		DisabledTooltip = '当前执行器不支持',
		Disabled = not hookmetamethod,
		Values = MethodsIndexWalk,
		Default = WalkSpoofTable.Method,

		Callback = function(value)
			WalkSpoofTable.Method = value
		end
	})

	Groupbox2:AddDivider({
		Margin = -3
	})

	function disconnectPart(part)
		local part = Connections.PartsConnections[part]
		for index, connection in part or {} do
			connection:Disconnect()
		end
		part = nil
	end

	function handlePart(part)
		if part:IsA("BasePart") then
			Connections.PartsConnections = Connections.PartsConnections or {}
			Connections.PartsConnections[part] = {
				AncestryChanged = part.AncestryChanged:Connect(function()
					if not part.Parent then
						disconnectPart(part)
					end
				end),
				CrazyLoop = Services.RunService.RenderStepped:Connect(function()
					if isnetworkowner(part) and not part.Anchored then
						part.CFrame *= CFrame.Angles(math.rad(math.random(-1800,1800)/100*4),math.rad(math.random(-1800,1800)/100*4),math.rad(math.random(-1800,1800)/100*4))
					end
				end)
			}
		end
	end

	Toggles.CrazyUnanchoredParts = Groupbox2:AddToggle(prefix..'CrazyUnanchoredParts', {
		Text = '疯狂的非锚定部件',
		Tooltip = '让非锚定部件发疯',
		Default = false,

		Callback = function(value)
			if value then
				toggleNetworkOwner(true)
				for _, part in CurrentRooms:GetDescendants() do
					handlePart(part)
				end
				Connections.UnanchoredPartAdded = CurrentRooms.DescendantAdded:Connect(handlePart)
			else
				toggleNetworkOwner(false)
				if Connections.UnanchoredPartAdded then
					Connections.UnanchoredPartAdded:Disconnect()
					Connections.UnanchoredPartAdded = nil
				end
				for part, _ in Connections.PartsConnections or {} do
					disconnectPart(part)
				end
				Connections.PartsConnections = nil
			end
		end
	})

	grumblesOffset = Vector3.new(0,10000,0)
	Toggles.InvisibleGrumbles = Groupbox2:AddToggle(prefix..'InvisibleGrumbles', {
		Text = '隐形咕噜',
		Default = false,

		Callback = function(value)
			if value then
				local nest = CurrentRooms:FindFirstChild('_NestHandler', true)
				local grumbles = nest and nest:FindFirstChild('Grumbles')
				if grumbles then
					toggleNetworkOwner(true)
					Connections.LoopInvisGrumbles = Services.RunService.Heartbeat:Connect(function()
						for _, grumble in grumbles:GetChildren() do
							task.spawn(function()
								local rig = grumble:FindFirstChild("GrumbleRig")
								local root = rig and rig:FindFirstChild("Root")
								if root then
									root.CFrame += grumblesOffset
									Services.RunService.RenderStepped:Wait()
									root.CFrame -= grumblesOffset
								end
							end)
						end
					end)
					Library:Notify({
						Title = Info.AddonTitle,
						Description = "咕噜现在不会出现在所有人面前！（只有你能看到）",
						Time = 4
					})
				else
					Library:Notify({
						Title = Info.AddonTitle.." [Error]",
						Description = '未找到咕噜',
						Time = 2
					})
					Toggles.InvisibleGrumbles:SetValue(false)
				end
			else
				toggleNetworkOwner(false)
				if Connections.LoopInvisGrumbles then
					Connections.LoopInvisGrumbles:Disconnect()
					Connections.LoopInvisGrumbles = nil
				end
			end
		end
	})

	Toggles.LoopTriggerFigure = Groupbox2:AddToggle(prefix..'LoopTriggerFigure', {
		Text = '循环触发飞哥',
		Tooltip = '伪造脚步声来触发飞哥',
		Default = false,

		Callback = function()
			while Toggles.LoopTriggerFigure.Value do
				Footstep:FireServer()
				task.wait()
			end
		end
	})

	local playerToKill
	Groupbox2:AddDropdown(prefix..'PlayerToKill', {
		SpecialType = 'Player',
		Searchable = true,
		Multi = false,
		Text = '玩家',
		Default = {},
		Callback = function(value)
			playerToKill = value
		end
	})

	local killPlayerWF; killPlayerWF = Groupbox2:AddButton(prefix..'KillPlayerWithFigure', {
		Text = '杀死玩家',
		DisabledTooltip = '请稍候...',
		Tooltip = '需要飞哥与被选玩家在同一房间',
		DoubleClick = true,
		Func = function()
			if not (Character and Character:FindFirstChild("HumanoidRootPart")) then
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = '未找到本地玩家的根部件',
					Time = 3
				})
				return
			end
			if playerToKill then
				if playerToKill == LocalPlayer then
					Library:Notify({
						Title = Info.AddonTitle.." [Error]",
						Description = "兄弟你不能用飞哥自杀",
						Time = 3
					})
					return
				end
				if playerToKill:GetAttribute("Alive") then
					local Victim = playerToKill.Character
					local VRoot = Victim and Victim:FindFirstChild("HumanoidRootPart")
					if VRoot then
						local figure = workspace:FindFirstChild("FigureRig", true)
						if not figure then
							Library:Notify({
								Title = Info.AddonTitle.." [Error]",
								Description = '未找到飞哥',
								Time = 2
							})
							return
						end
						local room = inWhatRoom(figure)
						if room ~= playerToKill:GetAttribute("CurrentRoom") then
							Library:Notify({
								Title = Info.AddonTitle.." [Error]",
								Description = '飞哥与被选玩家不在同一房间',
								Time = 4
							})
							return
						end
						killPlayerWF:SetDisabled(true)
						local wasEnabled = {Toggles.CollisionOffsetGodmodeAlt.Value, Toggles.InfiniteCrucifixAlt.Value}
						if wasEnabled[1] then
							Toggles.CollisionOffsetGodmodeAlt:SetValue(false)
						end
						if wasEnabled[2] then
							Toggles.InfiniteCrucifixAlt:SetValue(false)
						end
						Toggles.CollisionOffsetGodmodeAlt:SetDisabled(true)
						Toggles.InfiniteCrucifixAlt:SetDisabled(true)
						Crouch:FireServer(nil,true)
						TPPath:ComputeAsync(Character.HumanoidRootPart.Position, VRoot.Position)
						local val = Toggles.AntiTeleport.Value
						if val then
							pcall(Toggles.AntiTeleport.Callback, false)
						end
						if #TPPath:GetWaypoints() > 0 then
							for _, point in TPPath:GetWaypoints() do
								Crouch:FireServer(nil,true)
								Character:PivotTo(CFrame.new(point.Position)+Vector3.new(0,12,0))
								task.wait()
							end
						end
						local OldCFrame = Character.HumanoidRootPart.CFrame
						local Weld = WeldTo(VRoot, CFrame.new(0,9,0))
						local lastfire = -1/0
						local started = os.clock()
						while room == playerToKill:GetAttribute("CurrentRoom") and playerToKill:GetAttribute("Alive") and Weld.Destroy and started > os.clock()-30 do
							Crouch:FireServer(nil,true)
							if lastfire < os.clock()-.5 then
								lastfire = os.clock()
								Footstep:FireServer()
							end
							task.wait()
						end
						if Weld.Destroy then Weld:Destroy() end
						settings().Physics.AllowSleep = Weld.OldAllowSleep
						task.wait()
						TPPath:ComputeAsync(VRoot.Position, OldCFrame.Position)
						if #TPPath:GetWaypoints() > 0 then
							for _, point in TPPath:GetWaypoints() do
								Crouch:FireServer(nil,true)
								Character:PivotTo(CFrame.new(point.Position)+Vector3.new(0,12,0))
								task.wait()
							end
							Character:PivotTo(OldCFrame)
						else
							Character:PivotTo(OldCFrame)
						end
						if val then
							pcall(Toggles.AntiTeleport.Callback, true)
						end
						Crouch:FireServer()
						if playerToKill:GetAttribute("Alive") then
							Library:Notify({
								Title = Info.AddonTitle.." [Error]",
								Description = '杀死被选玩家失败',
								Time = 3
							})
						else
							Library:Notify({
								Title = Info.AddonTitle,
								Description = '成功杀死被选玩家',
								Time = 3
							})
						end
					else
						Library:Notify({
							Title = Info.AddonTitle.." [Error]",
							Description = '未找到被选玩家的根部件',
							Time = 3
						})
					end 
				else
					Library:Notify({
						Title = Info.AddonTitle.." [Error]",
						Description = '被选玩家已死亡',
						Time = 3
					})
				end
			else
				Library:Notify({
					Title = Info.AddonTitle.." [Error]",
					Description = '没有选中的玩家',
					Time = 2
				})
			end
			killPlayerWF:SetDisabled(false)
			if wasEnabled[1] then
				Toggles.CollisionOffsetGodmodeAlt:SetValue(true)
			end
			if wasEnabled[2] then
				Toggles.InfiniteCrucifixAlt:SetValue(true)
			end
			Toggles.CollisionOffsetGodmodeAlt:SetDisabled(false)
			Toggles.InfiniteCrucifixAlt:SetDisabled(false)
		end
	})

	Groupbox2:AddDivider({
		Margin = -3
	})

	Variables.MethodsIndex = {}
	for index, _ in Variables.motorReplicaAbuse.methods do
		table.insert(Variables.MethodsIndex, index)
	end

	Groupbox2:AddDropdown(prefix..'MotorMethods', {
		Multi = false,
		Text = '方式',
		DisabledTooltip = '当前执行器不支持',
		Disabled = not hookmetamethod,
		Values = Variables.MethodsIndex,
		Default = Variables.motorReplicaAbuse.method,

		Callback = function(value)
			Variables.motorReplicaAbuse.method = value
			if not Variables.motorReplicaAbuse.enabled then return end
			local method = Variables.motorReplicaAbuse.methods[value]
			if Connections.CurrentLVYAbuseMethodConnection then
				Connections.CurrentLVYAbuseMethodConnection:Disconnect()
				Connections.CurrentLVYAbuseMethodConnection = nil
			end
			if typeof(method) == "table" and method.methodType == "Number" then
				MotorReplication:FireServer(0)
			elseif typeof(method) == "function" then
				if Connections.CurrentLVYAbuseMethodConnection then
					Connections.CurrentLVYAbuseMethodConnection:Disconnect()
					Connections.CurrentLVYAbuseMethodConnection = nil
				end
				Connections.CurrentLVYAbuseMethodConnection = method()
			end
		end
	})

	Variables.MotorSpeed = Groupbox2:AddSlider("LadderSpeed", {
		Text = "速度",
		Default = 1,
		Min = 0.5,
		Max = 2,
		Rounding = 2,
		Compact = true
	})

	Toggles.MotorAbuse = Groupbox2:AddToggle(prefix..'MotorAbuse', {
		Text = 'LVY 滥用',
		Tooltip = '对 Motor Replication 事件做一些有趣的事（每个人都会看到）',
		Default = Variables.motorReplicaAbuse.enabled,
		DisabledTooltip = '当前执行器不支持',
		Disabled = not hookmetamethod,

		Callback = function(value)
			Variables.motorReplicaAbuse.enabled = value
			local method = Variables.motorReplicaAbuse.methods[Variables.motorReplicaAbuse.method]
			if value then
				if typeof(method) == "table" and method.methodType == "Number" then
					MotorReplication:FireServer(0)
				elseif typeof(method) == "function" then
					if Connections.CurrentLVYAbuseMethodConnection then
						Connections.CurrentLVYAbuseMethodConnection:Disconnect()
						Connections.CurrentLVYAbuseMethodConnection = nil
					end
					Connections.CurrentLVYAbuseMethodConnection = method()
				end
			else
				if Connections.CurrentLVYAbuseMethodConnection then
					Connections.CurrentLVYAbuseMethodConnection:Disconnect()
					Connections.CurrentLVYAbuseMethodConnection = nil
				end
				MotorReplication:FireServer(0)
			end
		end
	})

	Groupbox:AddDivider({
		Text = "物品",
		MarginTop = 2,
		MarginBottom = -2
	})

	Variables.itemsOffset = Vector3.zero
	Variables.selectedPlayerItem = nil
	Variables.old = {}

	function toggleNetworkOwner(bool)
		if not(gethiddenproperty and sethiddenproperty) then return end
		if (Toggles.InvisibleGrumbles.Value or Toggles.LoopSteal.Value or Toggles.DisableMandrakeFEAlt.Value or Toggles.OrbitDrops.Value or Toggles.OrbitGlowsticks.Value or Toggles.CrazyUnanchoredParts.Value or Toggles.BringDrawers.Value) and not bool then return end
		if bool and not Connections.network then
			Variables.old.allowSleep = settings().Physics.AllowSleep
			Variables.old.replicaFocus = LocalPlayer.ReplicationFocus
			Variables.old.maxSimRadius = gethiddenproperty(LocalPlayer, 'MaximumSimulationRadius')
			Variables.old.simRadius = gethiddenproperty(LocalPlayer, 'SimulationRadius')
			settings().Physics.AllowSleep = false
			LocalPlayer.ReplicationFocus = workspace
			Connections.network = Services.RunService.Heartbeat:Connect(function()
				sethiddenproperty(LocalPlayer, 'MaximumSimulationRadius', 1/0)
				sethiddenproperty(LocalPlayer, 'SimulationRadius', 1/0)
				if replicatesignal then
					pcall(replicatesignal, LocalPlayer.SimulationRadiusChanged, 1/0)
				end
				for _, Player in Services.Players:GetPlayers() do
					if Player == LocalPlayer then return end
					sethiddenproperty(Player, 'MaxSimulationRadius', 0)
					sethiddenproperty(Player, 'SimulationRadius', 0)
					if replicatesignal then
						pcall(replicatesignal, Player.SimulationRadiusChanged, 0)
					end
				end
			end)
		elseif not bool and Connections.network then
			settings().Physics.AllowSleep = Variables.old.allowSleep
			Connections.network:Disconnect()
			Connections.network = nil
			LocalPlayer.ReplicationFocus = Variables.old.replicaFocus
			sethiddenproperty(LocalPlayer, 'MaximumSimulationRadius', Variables.old.maxSimRadius)
			sethiddenproperty(LocalPlayer, 'SimulationRadius', Variables.old.simRadius)
			if replicatesignal then
				pcall(replicatesignal, LocalPlayer.SimulationRadiusChanged, Variables.old.simRadius)
			end
			Variables.old = {}
		end
	end

	Variables.connectedPrompts = {}

	local function activatePrompt(hrp, drop, prompt)
		if typeof(prompt) == 'Instance' and prompt:IsA('ProximityPrompt') then
			local connection = {changeHrp = function(newhrp)
				hrp = newhrp or hrp
			end}
			function connection:onActivate()
				self = nil
			end
			table.insert(Variables.connectedPrompts, connection)
			task.spawn(function()
				local lastDetectedHrp = os.clock()
				while prompt.Parent and connection and os.clock()-lastDetectedHrp < 3 do
					if hrp.Parent then
						lastDetectedHrp = os.clock()
						drop:PivotTo(hrp.CFrame + itemsOffset)
						fireproximityprompt(prompt)
					end
					for _ = 1,math.clamp(#Variables.connectedPrompts,1,1/0) do -- math.clamp is here to prevent 'while true do end' crash
						task.wait()
					end
				end
				if connection then
					connection:onActivate()
				end
			end)
			return connection
		end
	end

	Groupbox:AddDropdown(prefix..'PlayerToBringItems', {
		SpecialType = 'Player',
		Searchable = true,
		Multi = true,
		Text = '玩家',
		Default = {},
		Callback = function(value)
			Variables.selectedPlayerItem = value
		end
	})

	Groupbox:AddButton(prefix.."BringDrops", {
		Text = '拉近掉落物',
		Tooltip = '把所有掉落物品拉到你的当前位置',
		Func = function()
			local char = Variables.selectedPlayerItem and Variables.selectedPlayerItem.Character or Character
			local human = char and char:FindFirstChild('Humanoid')
			local hrp = human and human.RootPart

			if hrp then
				toggleNetworkOwner(true)
				for _, drop in Drops:GetChildren() do
					if drop:IsA('BasePart') then
						drop.CFrame = hrp.CFrame + Variables.itemsOffset
					elseif drop:IsA('Model') then
						drop:PivotTo(hrp.CFrame + Variables.itemsOffset)
					end
				end
				toggleNetworkOwner(false)
			end
		end
	})

	Groupbox:AddDivider({
		Margin = -6
	})

	Groupbox:AddButton(prefix.."StealDrops", {
		Text = '偷取掉落物',
		Tooltip = '偷取所有掉落物品',
		Func = function()
			local char = Character
			local human = char and char:FindFirstChild('Humanoid')
			local hrp = human and human.RootPart

			if hrp then
				toggleNetworkOwner(true)
				for _, drop in Drops:GetChildren() do
					if drop:IsA('BasePart') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					elseif drop:IsA('Model') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					end
				end
				toggleNetworkOwner(false)
			end
		end
	})

	Toggles.LoopSteal = Groupbox:AddToggle(prefix..'LoopSteal', {
		Text = '循环偷取掉落物',
		Tooltip = '循环偷取所有掉落物品（除你自己的）',
		Default = false,
		Callback = function(bool)
			if not bool then
				if Connections.loop then
					Connections.loop:Disconnect()
					Connections.loop = nil
				end
				if Connections.charchanged then
					Connections.charchanged:Disconnect()
					Connections.charchanged = nil
				end
				if Connections.rootchanged then
					Connections.rootchanged:Disconnect()
					Connections.rootchanged = nil
				end
				for _, connection in Variables.connectedPrompts do
					connection:onActivate()
				end
				toggleNetworkOwner(false)
				return
			end

			local char = Character or LocalPlayer.CharacterAdded:Wait()
			local human = char:WaitForChild('Humanoid', 99)
			local hrp = human.RootPart
			Connections.rootchanged = human:GetPropertyChangedSignal("RootPart"):Connect(function()
				hrp = human.RootPart
				for _, connection in Variables.connectedPrompts do
					connection:changeHrp(hrp)
				end
			end)

			if not Toggles.LoopSteal.Value then return end

			if hrp then
				toggleNetworkOwner(true)
				for _, drop in Drops:GetChildren() do
					if drop:GetAttribute("PlayerName") == LocalPlayer.Name then continue end
					if drop:IsA('BasePart') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					elseif drop:IsA('Model') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					end
				end
				Connections.loop = Drops.ChildAdded:Connect(function(drop)
					if drop:GetAttribute("PlayerName") == LocalPlayer.Name then return end
					if drop:IsA('BasePart') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					elseif drop:IsA('Model') then
						activatePrompt(hrp, drop, drop:FindFirstChild('ModulePrompt', true))
					end
				end)
				Connections.charchanged = LocalPlayer.CharacterAdded:Connect(function(c)
					char = c
					human = c:WaitForChild('Humanoid', 99)
					hrp = human.RootPart or hrp
					if Connections.rootchanged then
						Connections.rootchanged:Disconnect()
					end
					Connections.rootchanged = human:GetPropertyChangedSignal("RootPart"):Connect(function()
						hrp = human.RootPart
						for _, connection in Variables.connectedPrompts do
							connection:changeHrp(hrp)
						end
					end)
					for _, connection in Variables.connectedPrompts do
						connection:changeHrp(hrp)
					end
				end)
			else
				toggle:SetValue(false)
			end
		end
	})

	Groupbox:AddDivider({
		Margin = -6
	})

	local Settings = {}
	local VisualOrbitOffset = Vector3.new(0,-128,0)
	Toggles.OrbitDrops = Groupbox:AddToggle(prefix..'OrbitDrops', {
		Text = '环绕掉落物',
		Default = false,
		Callback = function(bool)
			if bool then
				toggleNetworkOwner(true)
				local val = 0
				Connections.OrbitDropsConnection = Services.RunService.Heartbeat:Connect(function(dt)
					val = (val + dt * 90 * Settings.Speed.Value) % 360
					local Root = Character and Character:FindFirstChild("HumanoidRootPart")
					if Root and Character:GetAttribute("Alive") then
						local drops = Drops:QueryDescendants(`> Model[$PlayerName = {LocalPlayer.Name}]`)
						for num, drop in drops do
							local main = drop:FindFirstChild("Main")
							if main then
								main.AssemblyLinearVelocity = Vector3.zero
								main.CanQuery = not Toggles.NoPrompt.Value
							end
							drop:PivotTo((CFrame.Angles(0, math.rad(val - 360 / #drops * num), 0) + Root.Position) * CFrame.new(0, 0, Settings.Offset.Value) + (Toggles.AntiSteal.Value and VisualOrbitOffset or Vector3.zero))
							local prompt = drop:FindFirstChild("ModulePrompt")
							if prompt then
								prompt.Enabled = not Toggles.NoPrompt.Value
							end
							local itemDropPickup = drop:FindFirstChild("ItemDropPickup")
							if itemDropPickup then
								itemDropPickup.CanCollide = not Toggles.NoPrompt.Value
								itemDropPickup.CanQuery = not Toggles.NoPrompt.Value
							end
						end
						if Toggles.AntiSteal.Value then
							Services.RunService.RenderStepped:Wait()
							for num, drop in drops do
								drop:PivotTo(drop:GetPivot() - VisualOrbitOffset)
							end
						end
					end
				end)
			else
				toggleNetworkOwner(false)
				if Connections.OrbitDropsConnection then
					if Toggles.AntiSteal.Value then
						pcall(Toggles.AntiSteal.Callback, false)
						Services.RunService.RenderStepped:Wait()
					end
					Connections.OrbitDropsConnection:Disconnect()
					Connections.OrbitDropsConnection = nil
					if Toggles.NoPrompt.Value then
						local drops = Drops:QueryDescendants(`> Model[$PlayerName = {LocalPlayer.Name}]`)
						for num, drop in drops do
							local prompt = drop:FindFirstChild("ModulePrompt")
							if prompt then
								prompt.Enabled = true
							end
							local main = drop:FindFirstChild("Main")
							if main then
								main.CanQuery = true
							end
							local itemDropPickup = drop:FindFirstChild("ItemDropPickup")
							if itemDropPickup then
								itemDropPickup.CanCollide = true
								itemDropPickup.CanQuery = true
							end
						end
					end
				end
			end
		end
	})

	Toggles.OrbitGlowsticks = Groupbox:AddToggle(prefix..'OrbitGlowsticks', {
		Text = '环绕荧光棒',
		Default = false,
		Callback = function(bool)
			if bool then
				toggleNetworkOwner(true)
				local val = 0
				Connections.OrbitGlowsticksConnection = Services.RunService.Heartbeat:Connect(function(dt)
					val = (val + dt * 90 * Settings.Speed.Value) % 360
					local Root = Character and Character:FindFirstChild("HumanoidRootPart")
					if Root and Character:GetAttribute("Alive") then
						local sticks = workspace:QueryDescendants(`> #GlowstickLive[$Owner = {LocalPlayer.Name}]`)
						for num, stick in sticks do
							stick.CFrame = (CFrame.Angles(0, math.rad(val - 360 / #sticks * num), 0) + Root.Position) * CFrame.new(0, 0, Settings.Offset.Value)
							stick.AssemblyLinearVelocity = Vector3.zero
						end
					end
				end)
			else
				toggleNetworkOwner(false)
				if Connections.OrbitGlowsticksConnection then
					Connections.OrbitGlowsticksConnection:Disconnect()
					Connections.OrbitGlowsticksConnection = nil
				end
			end
		end
	})

	Settings.Speed = Groupbox:AddSlider(prefix.."Speed", {
		Text = "速度",
		Default = 1,
		Min = 0,
		Max = 4,
		Rounding = 1,
	})

	Settings.Offset = Groupbox:AddSlider(prefix.."Offset", {
		Text = "偏移",
		Default = 4,
		Min = 2,
		Max = 8,
		Rounding = 1,
	})

	Toggles.AntiSteal = Groupbox:AddToggle(prefix..'AntiSteal', {
		Text = '防偷取',
		Tooltip = "开启轨道掉落时不允许其他玩家偷取物品",
		Default = false
	})

	Toggles.NoPrompt = Groupbox:AddToggle(prefix..'NoPrompt', {
		Text = '无提示',
		Tooltip = '开启轨道掉落时隐藏提示',
		Default = false
	})

	Groupbox2:AddDivider({
		Text = "杂项",
		MarginTop = 2,
		MarginBottom = -2
	})

	local sound = '7107161936'
	local color = Color3.new(1,1,1)
	local captionEnabled = false

	Toggles.DeluluCaption = Groupbox2:AddToggle(prefix..'DeluluCaption', {
		Text = '妄想字幕',
		Tooltip = '来自妄想办公室的字幕',
		DisabledTooltip = '请稍候...',
		Disabled = not spawncaption,
		Default = false,

		Callback = function(value)
			if value then
				captionEnabled = true
				main_game.Reminder.Enabled = false
				Connections.caption = RemotesFolder.Caption.OnClientEvent:Connect(function(text)
					spawncaption(script1.Parent:WaitForChild('MainTextFrameSample'), script1.Parent, text, `rbxassetid://{sound}`, color)
				end)
				Connections.disableogcaption = Services.RunService.RenderStepped:Connect(function()
					pcall(function()
						main_game.Reminder.Enabled = false
					end)
				end)
			else
				if not captionEnabled then return end
				captionEnabled = false
				Connections.caption:Disconnect()
				Connections.disableogcaption:Disconnect()
				main_game.Reminder.Enabled = true
			end
		end
	})

	task.spawn(function()
		while not spawncaption and loaded do
			task.wait()
		end
		if loaded then
			Toggles.DeluluCaption:SetDisabled(false)
		end
	end)

	local DeluluSettings = Groupbox2:AddDependencyBox(prefix.."DeluluSettings")

	DeluluSettings:AddInput(prefix..'DeluluSound', {
		Text = '字幕音效',
		Numeric = true,
		Finished = true,
		ClearTextOnFocus = true,
		Placeholder = sound,
		Default = sound,

		Callback = function(newsound)
			sound = newsound
		end
	})

	DeluluSettings:AddLabel('Caption Color'):AddColorPicker(prefix..'DeluluColor', {
		Title = '字幕颜色',
		Default = color,

		Callback = function(newcolor)
			color = newcolor
		end
	})

	DeluluSettings:SetupDependencies({
		{ Toggles.DeluluCaption, true }
	})

	Groupbox2:AddDivider({
		Margin = -6
	})

	local light = "Blue"

	Groupbox2:AddDropdown(prefix..'Lights', {
		Multi = false,
		Text = '灯光',
		DisabledTooltip = '当前执行器不支持',
		Disabled = not firesignal,
		Values = {
			"Blue",
			"Yellow",
			"Glitch",
			"Rush"
		},
		Default = light,

		Callback = function(value)
			light = value
		end
	})

	local EvilTexts = {
		Blue = {
			Rush = {
				NoPosOffset = {
					"You died to Rush.",
					"Why can't you just hide in the closet.",
					"Are you stupid?"
				},
				PosOffset = {
					"Okay that is absolutely TERRIBLE...",
					"You died to a Rush with a FRICKING POSITION OFFSET.",
					"ARE YOU A ####### OR SOMETHING!?",
					"...",
					"You should probably get better at this game, NOOB."
				}
			},
			Blitz = {
				NoPosOffset = {
					"You died to Blitz.",
					"Why can't you just hide in the closet.",
					"Are you stupid?"
				},
				PosOffset = {
					"Okay that is TERRIBLE...",
					"You died to a Blitz with a POSITION OFFSET.",
					"HOW DID YOU EVEN MANAGED TO DIE!?!?",
					"You should probably get better at this game, NOOB."
				}
			},
			Ambush = {
				NoPosOffset = {
					"And you died to Ambush.",
					"Well, not surprised."
				},
				PosOffset = {
					"You have a Position Offset on...",
					"AND YOU STILL DIED TO AMBUSH!!!",
					"You can't even play this game with cheats!"
				}
			},
			ClientEntity = {
				"...",
				"Listen to me, skid.",
				"You can just disable this entity.",
				"But because you didn't do it,",
				"You probably can't have more than 7 IQ."
			},
			Other = {
				"You died to %s with cheats.",
				"Pfft, get better LOL."
			}
		},
		Yellow = {
			Rush = {
				NoPosOffset = {
					"Okay who killed you this time.",
					"...",
					"Bro, you was able to enter the ####### closet to survive,",
					"But because you are stupid you didn't do it."
				},
				PosOffset = {
					"Okay who killed you this time.",
					"...",
					"Well, you are terrible at this game,",
					"Can you just ####### leave please?"
				}
			},
			Blitz = {
				NoPosOffset = {
					"Who killed you this time.",
					"Ehh.. this guy.",
					"You was able just to hide in the closet to survive him bro,",
					"How many times i should repeat this."
				},
				PosOffset = {
					"Who killed you this time.",
					"Oh.",
					"Lmfao i think you have skill issue,",
					"Just get better bro."
				}
			},
			Ambush = {
				NoPosOffset = {
					"And you died to Ambush.",
					"Well, not surprised."
				},
				PosOffset = {
					"You have a Position Offset on...",
					"AND YOU STILL DIED TO AMBUSH!!!",
					"You can't even play this game with cheats!"
				}
			},
			ClientEntity = {
				"Press Right Shift,",
				"Go to Exploits,",
				"And disable the ####### entity, you #######."
			},
			Other = {
				"#### off bro Im not curious about who caused your death."
			}
		},
		Glitch = {
			Rush = {
				NoPosOffset = {
					"PRESS ALT+F4 TWICE TO REMOVE RUSH",
					"SO YOU DON'T HAVE TO HIDE"
				},
				PosOffset = {
					">",
					"SKID SKID SKID SAHUR"
				}
			},
			Blitz = {
				NoPosOffset = {
					"PRESS ALT+F4 TWICE TO REMOVE BLITZ",
					"SO YOU DON'T HAVE TO HIDE"
				},
				PosOffset = {
					">",
					"HEY, YOU [_] STUPID!"
				}
			},
			Ambush = {
				NoPosOffset = {
					"PRESS ALT+F4 TWICE TO REMOVE AMBUSH",
					"SO YOU DON'T HAVE TO HIDE"
				},
				PosOffset = {
					">",
					"EXECUTE 'setrawmetatable(game, {})'"
				}
			},
			ClientEntity = {
				">",
				"BRO DISABLE HIM :SOB:"
			},
			Other = {
				"WELL WELL WELL",
				">",
				unpack(table.create(100, "A")) -- this is gonna be fun
			}
		},
		Rush = {
			Rush = {
				NoPosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10))),
				PosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10)))
			},
			Blitz = {
				NoPosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10))),
				PosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10)))
			},
			Ambush = {
				NoPosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10))),
				PosOffset = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10)))
			},
			ClientEntity = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10))),
			Other = table.create(math.random(1,5), string.rep("RUSH ", math.random(5, 10)))
		}
	}

	local Rushers = {
		"Rush",
		"Blitz",
		"Ambush"
	}

	local ClientEntities = {
		"Screech",
		"A-90",
		"Halt",
		"Snare",
		"Drones",
		"Drone",
		"Scribbles",
		"Alma",
		"Ransom"
	}

	local function pickEvilDialogue(light)
		local lightTexts = EvilTexts[light]
		local deathCause = Character:GetAttribute("DeathCause")
		if table.find(Rushers, deathCause) then
			local texts = lightTexts[deathCause]
			return Toggles.CollisionOffsetGodmodeAlt.Value and texts.PosOffset or texts.NoPosOffset
		elseif table.find(ClientEntities, deathCause) then
			return lightTexts.ClientEntity
		else
			return lightTexts.Other
		end
	end

	local lod = false
	local nld = false
	local edc = false
	local deathHintConnection = firesignal and DeathHint.OnClientEvent:Connect(function(texts, lightName, exploited)
		if not exploited and (lod or nld) then
			lightName = lod and light or lightName
			texts = nld and {} or edc and pickEvilDialogue(lightName) or texts
			for _ = 1,30 do -- so it would work 100%
				firesignal(DeathHint.OnClientEvent, texts, lightName, true)
				task.wait()
			end
		end
	end)

	Toggles.LightOnDeath = Groupbox2:AddToggle(prefix..'LightOnDeath', {
		Text = '死亡时亮灯',
		Tooltip = "用其他灯光替换当前楼层的默认灯光（文字不会变）",
		DisabledTooltip = '当前执行器不支持',
		Disabled = not deathHintConnection,
		Default = false,

		Callback = function(value)
			lod = value
		end
	})

	Toggles.NoLightDialog = Groupbox2:AddToggle(prefix..'NoLightDialog', {
		Text = '无灯光对话',
		Tooltip = "死亡后移除对话",
		DisabledTooltip = '当前执行器不支持',
		Disabled = not deathHintConnection,
		Default = false,

		Callback = function(value)
			if Toggles.EvilLights.Value and value then
				Toggles.EvilLights:SetValue(false)
			end
			nld = value
		end
	})

	Toggles.EvilLights = Groupbox2:AddToggle(prefix..'EvilLights', {
		Text = '邪恶灯光',
		Tooltip = "灯光不再帮你而是说点别的（我为什么要做这个）",
		DisabledTooltip = '当前执行器不支持',
		Disabled = not deathHintConnection,
		Default = false,

		Callback = function(value)
			if Toggles.NoLightDialog.Value and value then
				Toggles.NoLightDialog:SetValue(false)
			end
			edc = value
		end
	})

	Groupbox:AddDivider({
		Text = "反实体",
		MarginTop = 2,
		MarginBottom = -2
	})

	Toggles.CollisionOffsetGodmodeAlt = NoAltFeatures() or Groupbox:AddToggle(prefix..'CollisionOffsetGodmodeAlt', {
		Text = '位置偏移替代',
		Tooltip = "位置偏移的替代方法（来源 Abysall，由 tplaygd 修改）",
		Default = false,

		Callback = function(value)
			if value then
				if Toggles.AntiGroundskeeper.Value then
					Toggles.AntiGroundskeeper:SetValue(false)
				end
				if Toggles.AntiFigure.Value then
					Toggles.AntiFigure:SetValue(false)
				end
				DoStuffWithAntiTp()
				Variables.cogAlt = true
				Crouch:FireServer(true)
				Connections.POA = Services.RunService.Heartbeat:Connect(function()
					if not Variables.hook then
						Crouch:FireServer(true)
					end
					Character.HumanoidRootPart.CFrame *= CFrame.new(0, -2.146, 0)
					Character.CollisionPart.Weld.C1 = CFrame.new(0, 2.146, 0)
					Services.RunService.RenderStepped:Wait()
					Character.HumanoidRootPart.CFrame *= CFrame.new(0, 2.146, 0)
					Character.CollisionPart.Weld.C1 = CFrame.new(0, 0, 0)
					Camera.CFrame += Vector3.new(0, 2.146, 0)
				end)
			elseif Variables.cogAlt then
				Variables.cogAlt = false
				if Connections.POA then
					Connections.POA:Disconnect()
				end
				Character.HumanoidRootPart.CFrame *= CFrame.new(0, 2.146, 0)
				Character.CollisionPart.Weld.C1 = CFrame.new(0, 0, 0)
			end
		end
	})

	-- 快捷菜单（mspaint 的悬浮按键面板）注册：位置偏移替代
	-- 说明：这个精简版把原版所有的 AddKeyPicker 都删掉了（原版 5 个，这里 0 个），
	--       所以快捷菜单里看不到这个功能；下面这段从原版 v2.4.0 加回来
	--       （原文：Text = "Position Offset Alt", Default = "U", Mode = "Toggle"）
	do
		local altToggle = Toggles.CollisionOffsetGodmodeAlt
		if altToggle and altToggle.Callback and altToggle.AddKeyPicker then
			local ok, picker = pcall(function()
				return altToggle:AddKeyPicker(prefix.."CollisionOffsetGodmodeAltKey", {
					Text = "位置偏移替代",
					Default = "U",
					Mode = "Toggle",
					SyncToggleState = true
				})
			end)
			if ok and picker then
				KeyPickers.CollisionOffsetGodmodeAltKey = picker
			else
				warn("[TplaysAddon] 位置偏移替代 的按键注册失败：" .. tostring(picker))
			end
		end
	end

	local RaycastParams = RaycastParams.new()
	RaycastParams.FilterType = Enum.RaycastFilterType.Include
	RaycastParams.RespectCanCollide = true

	local function visualizeRaycast(startpos, endpos, success)
		if not ADDON_CONFIG.Debug then return end
		local part = Instance.new("Part", workspace)
		local ok = endpos-startpos
		part.Size = Vector3.new(.1,.1,ok.Magnitude)
		part.CFrame = CFrame.lookAt(startpos, endpos)+ok.Unit*(ok.Magnitude/2)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Anchored = true
		part.Color = success and Color3.new(0,1) or Color3.new(1)
		Services.Debris:AddItem(part, 5)
	end

	Variables.ping = 0
	task.spawn(function()
		while task.wait(1/15) and loaded do
			task.spawn(function()
				local start = os.clock()
				RequestLocalAsset:InvokeServer({{}})
				Variables.ping = os.clock()-start
			end)
		end
	end)

	local Dupes = {}
	local function handleDupe(sideroomDupe)
		local hidden = sideroomDupe:WaitForChild("DoorFake", 1/0):WaitForChild("Hidden", 1/0)
		Connections[sideroomDupe] = hidden.Touched:Connect(function(hit)
			local collision = Character and Character:FindFirstChild("Collision")
			local tool = GetEquippedTool(LocalPlayer)
			if hit == collision and tool and tool.Name == "Crucifix" then
				table.remove(Dupes, table.find(Dupes, sideroomDupe))
				Connections[sideroomDupe]:Disconnect()
				Connections[sideroomDupe] = nil
				task.wait()
				DropItem:FireServer(tool)
				local crucifix
				local con; con = Drops.ChildAdded:Connect(function(child)
					if child.Name == "Crucifix" and child:GetAttribute("PlayerName") == LocalPlayer.Name then
						crucifix = child
						con:Disconnect()
					end
				end)
				while not crucifix do
					task.wait()
				end
				task.spawn(function()
					local start = os.clock()
					local prompt = crucifix:WaitForChild("ModulePrompt", 3)
					if prompt then
						crucifix:PivotTo(Character:GetPivot())
						if start <= os.clock()-.5 then
							fireproximityprompt(prompt)
						end
						while crucifix.Parent do
							task.wait()
							crucifix:PivotTo(Character:GetPivot())
							if start <= os.clock()-.5 then
								fireproximityprompt(prompt)
							end
						end
					end
				end)
			end
		end)
		table.insert(Dupes, sideroomDupe)
	end

	Variables.Range = {
		RushMoving = 50,
		AmbushMoving = 60,
		["A60"] = 60,
	}

	Variables.AntiDupe = Library.Toggles.AntiDupe

	Toggles.InfiniteCrucifixAlt = NoAltFeatures() or Groupbox:AddToggle(prefix..'InfiniteCrucifixAlt', {
		Text = '无限十字架替代',
		Risky = true,
		Tooltip = '应该有更高概率复制十字架（仅对突袭、伏击、A-60、复制有效）',
		Default = false,

		Callback = function(value)
			if value then
				if Variables.AntiDupe.Value then
					Variables.AntiDupe:SetValue(false)
				end
				Variables.AntiDupe:SetDisabled(true)
				Connections.InfiniteCrucifixConnection = workspace.ChildAdded:Connect(function(child)
					local n = child.Name
					if n=="RushMoving" or n=="AmbushMoving" or n=="A60" then
						local main = child:FindFirstChildWhichIsA("BasePart")
						if main then
							local speedTable = {}
							local speed = 0
							local dir = Vector3.zero
							local crucifixed = false
							task.spawn(function()
								local startpos = main.Position
								while startpos == main.Position do
									task.wait()
								end
								while not crucifixed do
									local pos = main.Position
									local dt = task.wait(1/60)
									local yea = main.Position-pos
									table.insert(speedTable, yea.Magnitude/dt)
									dir = yea.Unit
									if #speedTable > 60 then
										table.remove(speedTable, 1)
									end
									speed = 0
									for _, speed1 in speedTable do
										speed += speed1
									end
									speed /= #speedTable
								end
							end)
							while child.Parent do
								local cpart = Character and Character:FindFirstChild("CollisionPart")
								local tool = GetEquippedTool(LocalPlayer)
								RaycastParams.FilterDescendantsInstances = {CurrentRooms, cpart}
								local predictedpos = main.Position+(dir*Variables.ping)
								local yea = Variables.Range[n]
								local raycast = cpart and workspace:Raycast(predictedpos, (cpart.Position-predictedpos).Unit*yea, RaycastParams)
								local success = raycast and raycast.Instance == cpart
								--logprint(yea)
								logprint(raycast, raycast and raycast.Position, raycast and raycast.Instance)
								visualizeRaycast(predictedpos, raycast and raycast.Position or predictedpos+(cpart.Position-predictedpos).Unit*yea, success)
								if success and tool and tool.Name == "Crucifix" then
									log("DROP CRUCIFIX")
									DropItem:FireServer(tool)
									local crucifix
									local con1; con1 = child.AncestryChanged:Connect(function()
										if not child.Parent then
											crucifixed = true
											con1:Disconnect()
										end
									end)
									local con2; con2 = Drops.ChildAdded:Connect(function(child)
										if child.Name == "Crucifix" and child:GetAttribute("PlayerName") == LocalPlayer.Name then
											crucifix = child
											con2:Disconnect()
										end
									end)
									while not crucifix do
										task.wait()
									end
									task.spawn(function()
										local start = os.clock()
										local prompt = crucifix:WaitForChild("ModulePrompt", 3)
										if prompt then
											crucifix:PivotTo(Character:GetPivot())
											if not child.Parent or start <= os.clock()-1.5 then
												fireproximityprompt(prompt)
											end
											while crucifix.Parent do
												task.wait()
												crucifix:PivotTo(Character:GetPivot())
												if not child.Parent or start <= os.clock()-1.5 then
													fireproximityprompt(prompt)
												end
											end
										end
									end)
									break
								end
								Services.RunService.Heartbeat:Wait()
							end
						end
					end
				end)
				Connections.OnDupeAnimation = Character:GetAttributeChangedSignal("Animating"):Connect(function()
					Character:SetAttribute("Animating", false)
				end)
				for _, dupe in CurrentRooms:QueryDescendants("Model >> #SideroomDupe") do
					handleDupe(dupe)
				end
				Connections.OnDupeSpawned = CurrentRooms.DescendantAdded:Connect(function(descendant)
					if descendant.Name == "SideroomDupe" then
						handleDupe(descendant)
					end
				end)
				Connections.OnDupeRemoved = CurrentRooms.DescendantRemoving:Connect(function(descendant)
					if descendant.Name == "SideroomDupe" then
						Connections[descendant]:Disconnect()
						Connections[descendant] = nil
						table.remove(Dupes, table.find(Dupes, descendant))
					end
				end)
			else
				Variables.AntiDupe:SetDisabled(false)
				if Connections.InfiniteCrucifixConnection then
					Connections.InfiniteCrucifixConnection:Disconnect()
					Connections.InfiniteCrucifixConnection = nil
				end
				if Connections.OnDupeAnimation then
					Connections.OnDupeAnimation:Disconnect()
					Connections.OnDupeAnimation = nil
				end
				if Connections.OnDupeSpawned then
					Connections.OnDupeSpawned:Disconnect()
					Connections.OnDupeSpawned = nil
				end
				for _, dupe in Dupes do
					Connections[dupe]:Disconnect()
					Connections[dupe] = nil
				end
				Dupes = {}
			end
		end
	})

	Variables.MandrakesPos = {}

	StuffToRemoveLater.voidpos = Instance.new("BodyPosition")
	StuffToRemoveLater.voidpos.MaxForce = Vector3.new(1/0, 1/0, 1/0)
	StuffToRemoveLater.voidpos.Position = Vector3.new(0, -100000, 0)
	StuffToRemoveLater.voidpos.Name = "VoidPos"

	function handleMandrake(mandrake)
		if mandrake.Name == "Mandrake" and mandrake:WaitForChild("ModulePrompt", 1) and mandrake:WaitForChild("KilledEvent", 1) and mandrake:WaitForChild("Root", 1) then
			local pos = StuffToRemoveLater.voidpos:Clone()
			pos.Parent = mandrake.Root
			Variables.MandrakesPos[mandrake] = pos
			mandrake.Goal.GoalAttach.CFrame = CFrame.new(0,-100000,0)
		end
	end

	local function getDirFunction()
		local connections = getconnections and getconnections(TargetCameraDirection.OnClientEvent)
		local connection = connections and connections[1]
		return connection and connection.Function
	end

	Variables.AutoMandrake = Library.Toggles.AutoMandrake
	Variables.DeleteMandrake = Library.Toggles.DeleteMandrake
	Toggles.DisableMandrakeFEAlt = NoAltFeatures() or (Floor ~= "Garden" and {Value = false}) or Groupbox:AddToggle(prefix..'DisableMandrakeFEAlt', {
		Text = '禁用曼德拉替代 [FE]',
		Default = false,

		Callback = function(value)
			if value then
				toggleNetworkOwner(true)
				Variables.dirFunction = getDirFunction()
				if hookfunction then
					if Variables.dirFunction then
						hookfunction(Variables.dirFunction, function()end)
					end
					hookfunction(TargetCameraDirection.OnClientEvent.Connect, function()end)
				end
				if Variables.AutoMandrake then
					if Variables.AutoMandrake.Value then
						Variables.AutoMandrake:SetValue(false)
					end
					Variables.AutoMandrake:SetDisabled(true)
				end
				if Variables.DeleteMandrake.Value then
					Variables.DeleteMandrake:SetValue(false)
				end
				Variables.DeleteMandrake:SetDisabled(true)
				for _, mandrake in CurrentRooms:QueryDescendants("#Mandrake") do
					handleMandrake(mandrake)
				end
				Connections.MandrakeAddedConnection = CurrentRooms.DescendantAdded:Connect(handleMandrake)
				Connections.MandrakeRemovedConnection = CurrentRooms.DescendantRemoving:Connect(function(mandrake)
					if mandrake.Name == "Mandrake" and mandrake:WaitForChild("ModulePrompt", 1) and mandrake:WaitForChild("KilledEvent", 1) and MandrakesVel[mandrake] then
						Variables.MandrakesPos[mandrake]:Destroy()
						Variables.MandrakesPos[mandrake] = nil
					end
				end)
			else
				toggleNetworkOwner(false)
				if isfunctionhooked and restorefunction then
					if Variables.dirFunction and isfunctionhooked(Variables.dirFunction) then
						restorefunction(Variables.dirFunction)
					end
					if isfunctionhooked(TargetCameraDirection.OnClientEvent.Connect) then
						restorefunction(TargetCameraDirection.OnClientEvent.Connect)
					end
				end
				if Variables.AutoMandrake then
					Variables.AutoMandrake:SetDisabled(false)
				end
				Variables.DeleteMandrake:SetDisabled(false)
				if Connections.MandrakeAddedConnection then
					Connections.MandrakeAddedConnection:Disconnect()
					Connections.MandrakeAddedConnection = nil
				end
				if Connections.MandrakeRemovedConnection then
					Connections.MandrakeRemovedConnection:Disconnect()
					Connections.MandrakeRemovedConnection = nil
				end
				for mandrake, pos in Variables.MandrakesPos do
					pos:Destroy()
					Variables.MandrakesPos[mandrake] = nil
					mandrake.Goal.GoalAttach.CFrame = CFrame.new(0,0,0)
				end
			end
		end
	})

	Variables.spoofed = false
	Toggles.AntiGroundskeeper = Groupbox:AddToggle(prefix..'AntiGroundskeeper', {
		Text = '反园丁',
		Default = false,

		Callback = function(value)
			if value then
				if Toggles.InfiniteCrucifixAlt.Value then
					Toggles.InfiniteCrucifixAlt:SetValue(false)
				end
				if Toggles.CollisionOffsetGodmodeAlt.Value then
					Toggles.CollisionOffsetGodmodeAlt:SetValue(false)
				end
				Connections.AGS = Services.RunService.Heartbeat:Connect(function()
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					if HumanoidRootPart and ShouldSpoofGS(HumanoidRootPart) and not killPlayerWF.Disabled then
						if not Variables.spoofed then
							DoStuffWithAntiTp()
						end
						Variables.spoofed = true
						HumanoidRootPart.CFrame *= CFrame.new(0, 3, 0)
						Services.RunService.RenderStepped:Wait()
						HumanoidRootPart.CFrame *= CFrame.new(0, -3, 0)
						Camera.CFrame -= Vector3.new(0,3,0)
					else
						Variables.spoofed = false
					end
				end)
			else
				if Connections.AGS then
					if Variables.spoofed then
						DoStuffWithAntiTp()
					end
					Connections.AGS:Disconnect()
					Connections.AGS = nil
					Variables.spoofed = false
				end
			end
		end
	})

	Variables.spoofed2 = false
	Toggles.AntiFigure = Groupbox:AddToggle(prefix..'AntiFigure', {
		Text = '反飞哥',
		Default = false,

		Callback = function(value)
			if value then
				if Toggles.InfiniteCrucifixAlt.Value then
					Toggles.InfiniteCrucifixAlt:SetValue(false)
				end
				if Toggles.CollisionOffsetGodmodeAlt.Value then
					Toggles.CollisionOffsetGodmodeAlt:SetValue(false)
				end
				Connections.AFR = Services.RunService.Heartbeat:Connect(function()
					local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
					local offset = 9.5-(Toggles.AntiGroundskeeper.Value and ShouldSpoofGS(HumanoidRootPart) and 3 or 0)
					if HumanoidRootPart and ShouldSpoofFR(HumanoidRootPart) and not killPlayerWF.Disabled then
						if not Variables.spoofed2 then
							DoStuffWithAntiTp()
						end
						Variables.spoofed2 = true
						HumanoidRootPart.CFrame *= CFrame.new(0, offset, 0)
						Services.RunService.RenderStepped:Wait()
						HumanoidRootPart.CFrame *= CFrame.new(0, -offset, 0)
						Camera.CFrame -= Vector3.new(0,offset,0)
					else
						Variables.spoofed2 = false
					end
				end)
			else
				if Connections.AFR then
					if spoofed2 then
						DoStuffWithAntiTp()
					end
					Connections.AFR:Disconnect()
					Connections.AFR = nil
					spoofed2 = false
				end
			end
		end
	})

	Toggles.FlingCreak = Floor ~= "Stairwell" and {Value = false} or Groupbox:AddToggle(prefix..'FlingCreak', {
		Text = '甩飞 Creak',
		DisabledTooltip = '当前执行器不支持',
		Tooltip = '尝试用椅子甩飞 Creak（兄弟他们为什么加了个能用的椅子 :sob:）',
		Risky = true,
		Default = false,
		Disabled = not sethiddenproperty,

		Callback = function(value)
			if value then
				Library:Notify({
					Title = "Tplay 的插件",
					Description = "抓一把椅子来甩飞 Creak",
					Time = 10
				})
				Connections.OnChairGrabCreak = Character.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("Attachment") and descendant.Name == "CartTargetAttachment" and descendant.Parent.Name == "CollisionPart" then
						local chair = FindChair(descendant)
						local promptBlock = chair and chair:FindFirstChild("PromptBlocker")
						if promptBlock then
							if chair == Variables.ChairThatFlingsCreak then
								CartControl:FireServer()
								return
							elseif Variables.ChairThatFlingsCreak then
								return
							elseif not Variables.ChairThatFlingsCreak then
								CartControl:FireServer()
							end
							Library:Notify({
								Title = "Tplay 的插件",
								Description = "椅子已准备好甩飞 Creak",
								Time = 3
							})
							Variables.ChairThatFlingsCreak = chair
							task.wait()
							chair = Variables.ChairThatFlingsCreak
							local oldcframe = chair:GetPivot()
							local killed = false
							Variables.FlingingCreak = true
							while Variables.FlingingCreak and chair and chair.Parent and promptBlock and isnetworkowner(promptBlock) do
								local creak = LiveEntities:FindFirstChild("Creak")
								if creak then
									local part = creak:FindFirstChild("HumanoidRootPart") or creak.PrimaryPart or creak:FindFirstChildWhichIsA("BasePart")
									if not part then
										killed = true
										break
									end
									pcall(sethiddenproperty, promptBlock, "PhysicsRepRootPart", part)
									chair:PivotTo(creak:GetPivot()+Vector3.new(0,3,0))
    								chair.Collider.AssemblyLinearVelocity = Vector3.new(0,-math.random(500000,1000000),0)
								end
								task.wait()
								chair = Variables.ChairThatFlingsCreak
								promptBlock = chair and chair:FindFirstChild("PromptBlocker")
							end
							if chair then
								chair:PivotTo(oldcframe)
							end
							Variables.ChairThatFlingsCreak = nil
							if killed then
								Library:Notify({
									Title = "Tplay 的插件",
									Description = "甩飞过程中 Creak 已被删除，现在你可以安心玩楼梯间了，不用再担心 Creak",
									Time = 10
								})
							elseif Variables.FlingingCreak then
								Library:Notify({
									Title = "Tplay 的插件 [警告]",
									Description = "椅子出了点问题导致无法继续甩飞 Creak，请再抓一把椅子继续甩飞",
									Time = 10
								})
							else
								Library:Notify({
									Title = "Tplay 的插件",
									Description = "已解除对甩飞 Creak 的椅子的控制",
									Time = 5
								})
							end
							Variables.FlingingCreak = false
						end
					end
				end)
			else
				if Connections.OnChairGrabCreak then
					Connections.OnChairGrabCreak:Disconnect()
					Connections.OnChairGrabCreak = nil
				end
				if Variables.FlingingCreak then
					Variables.FlingingCreak = false
				end
			end
		end
	})

	Groupbox:AddDivider({
		Text = "自动完成",
		MarginTop = 4,
		MarginBottom = 0
	})

	Variables.AutoFloorDist = {
		RushMoving = 120,
		AmbushMoving = 180,
		BackdoorRush = 108,
		["A60"] = 180
	}

	function ActiveRusher(interesting)
		local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
		local Door = Room and Room:FindFirstChild("Door")
		local PrevRoom = CurrentRooms:FindFirstChild(LatestRoom.Value-1)
		local PrevDoor = PrevRoom and PrevRoom:FindFirstChild("Door")
		local PrevPrevRoom = CurrentRooms:FindFirstChild(LatestRoom.Value-2)
		local PrevPrevDoor = PrevPrevRoom and PrevPrevRoom:FindFirstChild("Door")
		for _, rusher in workspace:QueryDescendants("> #RushMoving, > #AmbushMoving, > #A60, > #BackdoorRush") do
			if interesting or (Character:GetPivot().Position-rusher:GetPivot().Position).Magnitude < Variables.AutoFloorDist[rusher.Name] or (Door and (Door:GetPivot().Position-rusher:GetPivot().Position).Magnitude < Variables.AutoFloorDist[rusher.Name]) or (PrevDoor and (PrevDoor:GetPivot().Position-rusher:GetPivot().Position).Magnitude < Variables.AutoFloorDist[rusher.Name]) or (PrevPrevDoor and (PrevPrevDoor:GetPivot().Position-rusher:GetPivot().Position).Magnitude < Variables.AutoFloorDist[rusher.Name]) then
				return true
			end
		end
		return false
	end

	function GetDropThatCanUnlock()
		for i,v in Drops:QueryDescendants(`Model[$PlayerName = {LocalPlayer.Name}]`) do
			if v.Name == "Lockpick" or v.Name == "SkeletonKey" or v.Name == "Multitool" then
				return v
			end
		end
		return nil
	end

	function ItemThatCanUnlock()
		local Backpack = LocalPlayer.Backpack
		local Tool = GetEquippedTool(LocalPlayer)
		return Tool
		and (Tool.Name == "Lockpick" or Tool.Name == "SkeletonKey" or Tool.Name == "Multitool")
		and Tool
		or GetDropThatCanUnlock()
		or Backpack:FindFirstChild("Lockpick")
		or Backpack:FindFirstChild("SkeletonKey")
		or Backpack:FindFirstChild("Multitool")
	end

	function FindKeyObtain(Room)
		local key = Room:FindFirstChild("KeyObtain", true)
		if key then
			return key, key.Parent.Name == "DrawerContainer" and key.Parent
		end
		return nil, false
	end

	function GetNearestBook(Room)
		local Nearest = {
			Dist = 1/0
		}
		for _, book in Room:QueryDescendants("#Modular_Bookshelf > #LiveHintBook") do
			local dist = (Character:GetPivot().Position-book:GetPivot().Position).Magnitude
			if dist < Nearest.Dist then
				Nearest.Dist = dist
				Nearest.Book = book
			end
		end
		return Nearest.Book
	end

	function GetNearestBreaker(Room)
		local Nearest = {
			Dist = 1/0
		}
		for _, breaker in Room:QueryDescendants("#LiveBreakerPolePickup") do
			local dist = (Character:GetPivot().Position-breaker:GetPivot().Position).Magnitude
			if dist < Nearest.Dist then
				Nearest.Dist = dist
				Nearest.Breaker = breaker
			end
		end
		return Nearest.Breaker or Room:FindFirstChild("LiveBreakerPolePickup")
	end

	function GetNearestFuse(Room)
		local Nearest = {
			Dist = 1/0
		}
		for _, fuse in Room:QueryDescendants("#FuseObtain") do
			local dist = (Character:GetPivot().Position-fuse:GetPivot().Position).Magnitude
			if dist < Nearest.Dist and fuse.Hitbox.FuseModel.LocalTransparencyModifier ~= 1 then
				Nearest.Dist = dist
				Nearest.Fuse = fuse
			end
		end
		return Nearest.Fuse
	end

	Variables.InfItems = Library.Toggles.InfItems
	Variables.AutoLibrarySolver = Library.Toggles.AutoLibrarySolver
	Variables.BruteforceLibraryCode = Library.Toggles.BruteforceLibraryCode
	Variables.AutoBreakerSolverMethod = Library.Options.AutoBreakerSolverMethod
	Variables.AutoBreakerSolver = Library.Toggles.AutoBreakerSolver
	Variables.StuffToKeepEnabled = {
		Library.Toggles.AntiScreech,
		Library.Toggles.AntiDupe,
		Library.Toggles.AntiDread,
		Library.Toggles.AntiHalt,
		Library.Toggles.AntiSnare,
		Library.Toggles.AntiEyes,
		Library.Toggles.AntiA90,
		Library.Toggles.CollisionOffsetAutomatic,
		Library.Toggles.AutoInteract,
	}

	if Floor == "Mines" then
		for i, b in Library.Buttons do
			if b and b.Text == "Beat Door 200" then
				Variables.BeatDoor200 = b
				break
			end
		end
		table.insert(Variables.StuffToKeepEnabled, Library.Toggles.AntiSeekFlood)
		table.insert(Variables.StuffToKeepEnabled, Library.Toggles.AntiGiggle)
	elseif Floor == "Garden" then
		table.insert(Variables.StuffToKeepEnabled, Library.Toggles.NoSurgeDamage)
		table.insert(Variables.StuffToKeepEnabled, Toggles.BringDrawers)
		table.insert(Variables.StuffToKeepEnabled, Toggles.AutoLoot)
	elseif `{Floor}_{FloorSpecific}` == "Ripple_Daily_Default" then
	else
		table.insert(Variables.StuffToKeepEnabled, Toggles.BringDrawers)
		table.insert(Variables.StuffToKeepEnabled, Toggles.AutoLoot)
	end

	function IsInteresting(Rooms, Room)
		return not not (table.find(Rooms, Room:GetAttribute("RawName")) or table.find(Rooms, `{Room:GetAttribute("RawName")}|{Room.Name}`) or table.find(Rooms, Room.Name))
	end

	function GetNearestLadderGrabPart(Room)
		local Nearest = {
			Dist = 1/0
		}
		for _, grabPart in Room:QueryDescendants("#Ladder > #GrabPart") do
			local dist = (Character:GetPivot().Position-grabPart.Position).Magnitude
			if dist < Nearest.Dist then
				Nearest.Dist = dist
				Nearest.GrabPart = grabPart
			end
		end
		return Nearest.GrabPart
	end

	function GetNearestLever(Room)
		local Nearest = {
			Dist = 1/0
		}
		for _, lever in Room:QueryDescendants("#AlaskanVineSet > #VineGuillotine > #Lever") do
			local dist = (Character:GetPivot().Position-lever.Position).Magnitude
			if dist < Nearest.Dist and lever.ActivateEventPrompt.Enabled then
				Nearest.Dist = dist
				Nearest.Lever = lever
			end
		end
		return Nearest.Lever
	end

	function GetLotusPetal()
		local LotusPetals = CurrentRooms:QueryDescendants("#LotusHolder, #LotusPetalPickup, #LotusPetal")
		local LotusPetal, Drawer
		for _, lotuspetal in LotusPetals do
			if lotuspetal.ModulePrompt.Enabled then
				LotusPetal, Drawer = lotuspetal, lotuspetal.Parent and lotuspetal.Parent.Name == "DrawerContainer" and lotuspetal.Parent
				break
			end
		end
		return LotusPetal, Drawer
	end

	StuffToRemoveLater.novelocitybro = Instance.new("BodyVelocity")
	StuffToRemoveLater.novelocitybro.MaxForce = Vector3.new(1/0, 1/0, 1/0)
	StuffToRemoveLater.novelocitybro.Velocity = Vector3.zero

	Variables.AutoFloors = {
		Hotel = {
			Requirements = {
				"firetouchinterest",
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				local InterestingRooms = {
					"Hotel_SeekIntro",
					"Hotel_LibraryEntrance",
					"99"
				}
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					local interesting = IsInteresting(InterestingRooms, tempRoom)
					local activeRusher = ActiveRusher(interesting)
					local lastCutscene = ""
					local lastCutsceneGlobal = ""
					local unavailableUntil = -1/0
					local touched = false
					local key, drawer, book, breaker
					AutoFloor.CutsceneActivatedGlobal = Cutscene.OnClientEvent:Connect(function(name)
						lastCutsceneGlobal = name
					end)
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						if os.clock()<unavailableUntil or Character.PrimaryPart.Anchored then return end
						activeRusher = ActiveRusher(interesting)
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						if activeRusher then
							if Library.Toggles.DoorReach.Value then
								Library.Toggles.DoorReach:SetValue(false)
							end
							return
						elseif Room:GetAttribute("RequiresKey") then
							local item = ItemThatCanUnlock()
							if item then
								if not Variables.InfItems.Value then
									Variables.InfItems:SetValue(true)
								end
								if item:IsA("Tool") and item.Parent ~= Character then
									item.Parent = Character
								elseif item:IsA("Model") then
									item:PivotTo(Character:GetPivot())
									fireproximityprompt(item.ModulePrompt)
								end
								Character:PivotTo(Door:GetPivot())
								local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
								if prompt then
									fireproximityprompt(prompt)
								end
							else
								local tool = GetEquippedTool(LocalPlayer)
								if LocalPlayer.Backpack:FindFirstChild("Key") or (tool and tool.Name == "Key") then
									key = nil
									drawer = nil
									Character:PivotTo(Door:GetPivot())
									local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
									if prompt then
										fireproximityprompt(prompt)
									end
								else
									if not key or not drawer then
										key, drawer = FindKeyObtain(Room)
									end
									if key then
										Character:PivotTo(drawer and drawer:GetPivot() or key:GetPivot())
										if drawer then
											fireproximityprompt(drawer.Knobs.ActivateEventPrompt)
										end
										fireproximityprompt(key.ModulePrompt)
									end
								end
							end
						elseif Room.Name == "50" then
							if bool ~= false then
								book = book and book.Parent and book or GetNearestBook(Room)
							end
							if book then
								Character:PivotTo(book:GetPivot()+Vector3.new(0,8,0))
								fireproximityprompt(book.ActivateEventPrompt)
							else
								book = false
								local tool = GetEquippedTool(LocalPlayer)
								local LibraryHintPaper = (tool and tool.Name == "LibraryHintPaper" and tool) or LocalPlayer.Backpack:FindFirstChild("LibraryHintPaper") or Room:FindFirstChild("LibraryHintPaper")
								if LibraryHintPaper then
									if LibraryHintPaper:IsA("Tool") then
										if not Variables.AutoLibrarySolver.Value then
											Variables.AutoLibrarySolver:SetValue(true)
										end
										if not Variables.BruteforceLibraryCode.Value then
											Variables.BruteforceLibraryCode:SetValue(true)
										end
										LibraryHintPaper.Parent = LibraryHintPaper.Parent == Character and LocalPlayer.Backpack or Character
										Character:PivotTo(Door:GetPivot())
									else
										Character:PivotTo(LibraryHintPaper:GetPivot()+Vector3.new(0,5,0))
										fireproximityprompt(LibraryHintPaper.ModulePrompt)
									end
								end
							end
						elseif Room.Name == "100" then
							if not AutoFloor.CutsceneActivated then
								AutoFloor.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
									lastCutscene = name
									if name == "Elevator1" then
										Library:Notify({
											Title = Info.AddonTitle,
											Description = "酒店挑战完成！",
											Time = 10
										})
										Toggles.AutoFloor:SetValue(false)
										Toggles.AutoFloor:SetDisabled(true)
										return
									end
								end)
							end
							if breaker ~= false then
								breaker = breaker and breaker.Parent and breaker or GetNearestBreaker(Room)
							end
							if breaker then
								Character:PivotTo(breaker:GetPivot())
								fireproximityprompt(breaker.ActivateEventPrompt)
							else
								breaker = false
								if lastCutscene == "" then
									Character:PivotTo(Room.IndustrialGate:GetPivot())
									fireproximityprompt(Room.IndustrialGate.Box.ActivateEventPrompt)
								elseif lastCutscene == "FigureHotelEnd" then
									toggleNetworkOwner(true)
									local pivot = Room.ElevatorBreakerEmpty:GetPivot()
									Character:PivotTo(pivot+pivot.RightVector*-12)
									fireproximityprompt(Room.ElevatorBreakerEmpty.Prompt)
									pcall(function()
										Room.FigureSetup.FigureRig:PivotTo(CFrame.new(0,-1000,0))
									end)
								elseif lastCutscene == "FigureHotelChase" then
									Character:PivotTo(Room.ElevatorCar.CollisionExtra.CFrame)
									firetouchinterest(Character.PrimaryPart, Room.ElevatorCar.CollisionExtra, touched and 1 or 0)
									touched = not touched
								elseif Room:FindFirstChild("ElevatorBreaker") then
									if not Variables.AutoBreakerSolver.Value then
										Variables.AutoBreakerSolver:SetValue(true)
									end
									if Variables.AutoBreakerSolverMethod.Value ~= "Exploit" then
										Variables.AutoBreakerSolverMethod:SetValue("Exploit")
									end
									Character:PivotTo(Room.ElevatorBreaker:GetPivot())
									fireproximityprompt(Room.ElevatorBreaker.ActivateEventPrompt)
								end
							end
						else
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}`)
						end
						interesting = IsInteresting(InterestingRooms, room)
						if room and interesting then
							unavailableUntil = os.clock()+7
							while os.clock()<unavailableUntil and not activeRusher do
								activeRusher = ActiveRusher(interesting)
								Services.RunService.RenderStepped:Wait()
							end
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Mines = {
			Requirements = {
				"firetouchinterest",
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked",
				"getrawmetatable",
				"setreadonly"
			},
			Callback = function(value)
				local InterestingRooms = {
					"Mines_SeekStart",
					"Sewer_SeekEnter",
					"98"
				}
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					local interesting = IsInteresting(InterestingRooms, tempRoom)
					local activeRusher = ActiveRusher(interesting)
					local lastCutscene
					local unavailableUntil = -1/0
					local fuse, buttonPressed, leverActivated, beatingDoor200, noGeneratorSince, buggyRun
					AutoFloor.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
						lastCutscene = name
					end)
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						if os.clock()<unavailableUntil or Character.PrimaryPart.Anchored or buggyRun then return end
						activeRusher = ActiveRusher(interesting)
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						local grabPart = not Character:GetAttribute("_BypassedAC") and not (Camera and Camera:FindFirstChild("MinecartRig")) and GetNearestLadderGrabPart(Room)
						if activeRusher then
							if Library.Toggles.DoorReach.Value then
								Library.Toggles.DoorReach:SetValue(false)
							end
							return
						elseif Character:GetAttribute("Climbing") then
							Character:SetAttribute("Climbing")
							Character:SetAttribute("_BypassedAC", true)
							Connections.OnBypassRemove = Character:GetAttributeChangedSignal("Climbing"):Once(function()
								Character:SetAttribute("_BypassedAC", false)
								if Variables.AutoFloorRoom then
									Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {Room and Room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
								end
							end)
							if Variables.AutoFloorRoom then
								Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {Room and Room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
							end
						elseif grabPart then
							Character:PivotTo(grabPart.CFrame)
							fireproximityprompt(grabPart.ClimbPrompt)
						elseif Room.Name == "100" then
							if not AutoFloor.CutsceneActivated then
								AutoFloor.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
									lastCutscene = name
									if name == "MinesFinale" then
										Library:Notify({
											Title = Info.AddonTitle,
											Description = "矿山挑战完成！",
											Time = 10
										})
										Toggles.AutoFloor:SetValue(false)
										Toggles.AutoFloor:SetDisabled(true)
										return
									end
								end)
							end
							if beatingDoor200 then
								if leverActivated and not buttonPressed then
									local button = Room.Assets.MinesGateButton.Button
									local prompt = button.ActivateEventPrompt
									Character:PivotTo(button.CFrame)
									fireproximityprompt(prompt)
									if button.SoundPress.Playing then
										buttonPressed = true
									end
								elseif not leverActivated then
									if Room.Assets.MinesGenerator.GeneratorMain.Sound.Playing then
										leverActivated = true
									end
								else
									local doors = Room._DamHandler._OutsideCutscene.DungeonDoor.DoubleDoors
									local prompt = doors.ActivateEventPrompt
									Character:PivotTo(doors:GetPivot())
									fireproximityprompt(prompt)
								end
							else
								beatingDoor200 = true
								pcall(Variables.BeatDoor200.Func)
							end
						elseif Room:GetAttribute("RequiresGenerator") then
							local fuse = GetNearestFuse(Room)
							if fuse then
								Character:PivotTo(fuse:GetPivot())
								local openFirst = fuse:FindFirstAncestor("Locker_Small") or fuse:FindFirstAncestor("DrawerContainer") or fuse:FindFirstAncestor("Toolbox")
								if openFirst then
									fireproximityprompt(openFirst:FindFirstChild("ActivateEventPrompt", true))
								end
								fireproximityprompt(fuse.ModulePrompt)
							else
								local gen = Room.Assets:FindFirstChild("MinesGenerator")
								if gen then
									noGeneratorSince = nil
								else
									noGeneratorSince = noGeneratorSince or os.clock()
									if noGeneratorSince < os.clock()-3 then
										buggyRun = true
										Library:Notify({
											Title = Info.AddonTitle,
											Description = "检测到生成 bug：矿山发电机未在需要发电机的房间生成\n（游戏将自动重启）",
											Persist = true
										})
										PlayAgain:FireServer()
									end
									return
								end
								local notTuff = false
								for _, fuse in gen.Fuses:GetChildren() do
									if tonumber(fuse.Name) and fuse.Fuse.Transparency == 1 then
										notTuff = true
										break
									end
								end
								local prompt = notTuff and (gen:FindFirstChild("FusesPrompt", true) or gen:FindFirstChild("FakePrompt", true))
								if prompt then
									Character:PivotTo(gen:GetPivot())
									fireproximityprompt(prompt)
								elseif not leverActivated then
									prompt = gen.Lever.LeverPrompt
									Character:PivotTo(gen:GetPivot())
									fireproximityprompt(prompt)
									if gen.GeneratorMain.Sound.Playing then
										leverActivated = true
									end
								elseif not buttonPressed then
									local button = Room.Assets.MinesGateButton.Button
									prompt = button.ActivateEventPrompt
									Character:PivotTo(button.CFrame)
									fireproximityprompt(prompt)
									if button.SoundPress.Playing then
										buttonPressed = true
									end
								else
									Character:PivotTo(Door:GetPivot())
								end
							end
						elseif Room.Name == "46" and not Camera:FindFirstChild("MinecartRig") then
							if not Toggles.MinecartChaseSkip.Value then
								Toggles.MinecartChaseSkip:SetValue(true)
							end
							Character:PivotTo(Room.MinecartCollision.Collision.CFrame)
							firetouchinterest(Character.PrimaryPart, Room.MinecartCollision.Collision, 0)
							firetouchinterest(Character.PrimaryPart, Room.MinecartCollision.Collision, 1)
							return
						elseif Camera:FindFirstChild("MinecartRig") and (tonumber(Room.Name) >= 46 or tonumber(Room.Name) < 50) then
							if not Toggles.MinecartChaseSkip.Value then
								Toggles.MinecartChaseSkip:SetValue(true)
							end
							return
						elseif Room.Name == "50" then
							if Camera:FindFirstChild("MinecartRig") then return end
							if buttonPressed then
								Character:PivotTo(Door:GetPivot())
							else
								local button = Room._NestHandler.Console.Button
								local prompt = button.ActivateEventPrompt
								Character:PivotTo(button.CFrame)
								fireproximityprompt(prompt)
								if button.SoundPress.Playing then
									buttonPressed = true
								end
							end
						else
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						leverActivated = nil
						buttonPressed = nil
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
						end
						interesting = IsInteresting(InterestingRooms, room)
						if room and interesting then
							unavailableUntil = os.clock()+7
							while os.clock()<unavailableUntil and not activeRusher do
								activeRusher = ActiveRusher(interesting)
								Services.RunService.RenderStepped:Wait()
							end
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Endless = {
			Requirements = {
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					local key, drawer
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						local item = ItemThatCanUnlock()
						if item then
							if not Variables.InfItems.Value then
								Variables.InfItems:SetValue(true)
							end
							if item:IsA("Tool") and item.Parent ~= Character then
								item.Parent = Character
							elseif item:IsA("Model") then
								item:PivotTo(Character:GetPivot())
								fireproximityprompt(item.ModulePrompt)
							end
							Character:PivotTo(Door:GetPivot())
							local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
							if prompt then
								fireproximityprompt(prompt)
							end
						else
							local tool = GetEquippedTool(LocalPlayer)
							if LocalPlayer.Backpack:FindFirstChild("Key") or (tool and tool.Name == "Key") then
								key = nil
								drawer = nil
								Character:PivotTo(Door:GetPivot())
								local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
								if prompt then
									fireproximityprompt(prompt)
								end
							else
								if not key or not drawer then
									key, drawer = FindKeyObtain(Room)
								end
								if key then
									Character:PivotTo(drawer and drawer:GetPivot() or key:GetPivot())
									if drawer then
										fireproximityprompt(drawer.Knobs.ActivateEventPrompt)
									end
									fireproximityprompt(key.ModulePrompt)
								else
									Library:Notify({
										Title = Info.AddonTitle,
										Description = "无尽模式完成！",
										Time = 10
									})
									Toggles.AutoFloor:SetValue(false)
									Toggles.AutoFloor:SetDisabled(true)
								end
							end
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}`)
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Ripple_Daily_Default = {
			Requirements = {
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`,
						Persist = true
					})
					local AutoFloor = {}
					local activeRusher = ActiveRusher()
					Connections.AutoFloor = AutoFloor
					local key, drawer, fuse, buttonPressed, leverActivated, noGeneratorSince, buggyRun
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						if buggyRun then return end
						activeRusher = ActiveRusher()
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						local grabPart = not Character:GetAttribute("_BypassedAC") and GetNearestLadderGrabPart(Room)
						if activeRusher then
							if Library.Toggles.DoorReach.Value then
								Library.Toggles.DoorReach:SetValue(false)
							end
							return
						elseif Character:GetAttribute("Climbing") then
							Character:SetAttribute("Climbing")
							Character:SetAttribute("_BypassedAC", true)
							Connections.OnBypassRemove = Character:GetAttributeChangedSignal("Climbing"):Once(function()
								Character:SetAttribute("_BypassedAC", false)
								if Variables.AutoFloorRoom then
									Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {Room and Room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
								end
							end)
							if Variables.AutoFloorRoom then
								Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {Room and Room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
							end
						elseif grabPart then
							Character:PivotTo(grabPart.CFrame)
							fireproximityprompt(grabPart.ClimbPrompt)
						elseif Room:GetAttribute("RequiresKey") then
							local item = ItemThatCanUnlock()
							if item then
								if not Variables.InfItems.Value then
									Variables.InfItems:SetValue(true)
								end
								if item:IsA("Tool") and item.Parent ~= Character then
									item.Parent = Character
								elseif item:IsA("Model") then
									item:PivotTo(Character:GetPivot())
									fireproximityprompt(item.ModulePrompt)
								end
								Character:PivotTo(Door:GetPivot())
								local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
								if prompt then
									fireproximityprompt(prompt)
								end
							else
								local tool = GetEquippedTool(LocalPlayer)
								local keyTool = LocalPlayer.Backpack:FindFirstChild("Key") or (tool and tool.Name == "Key" and tool) or LocalPlayer.Backpack:FindFirstChild("KeyBackdoor") or (tool and tool.Name == "KeyBackdoor" and tool)
								if keyTool then
									key = nil
									drawer = nil
									if keyTool.Name == "KeyBackdoor" and keyTool.Parent ~= Character then
										keyTool.Parent = Character
									end
									Character:PivotTo(Door:GetPivot())
									local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
									if prompt then
										fireproximityprompt(prompt)
									end
								else
									if not key or not drawer then
										key, drawer = FindKeyObtain(Room)
									end
									if key then
										Character:PivotTo(drawer and drawer:GetPivot() or key:GetPivot())
										if drawer then
											fireproximityprompt(drawer:FindFirstChild("ActivateEventPrompt", true))
										end
										fireproximityprompt(key.ModulePrompt)
									end
								end
							end
						elseif Room:GetAttribute("RequiresGenerator") then
							local fuse = GetNearestFuse(Room)
							if fuse then
								Character:PivotTo(fuse:GetPivot())
								local openFirst = fuse:FindFirstAncestor("Locker_Small") or fuse:FindFirstAncestor("DrawerContainer") or fuse:FindFirstAncestor("Toolbox")
								if openFirst then
									fireproximityprompt(openFirst:FindFirstChild("ActivateEventPrompt", true))
								end
								fireproximityprompt(fuse.ModulePrompt)
							else
								local gen = Room.Assets:FindFirstChild("MinesGenerator")
								if gen then
									noGeneratorSince = nil
								else
									noGeneratorSince = noGeneratorSince or os.clock()
									if noGeneratorSince < os.clock()-3 then
										buggyRun = true
										Library:Notify({
											Title = Info.AddonTitle,
											Description = "检测到生成 bug：矿山发电机未在需要发电机的房间生成\n（游戏将自动重启）",
											Persist = true
										})
										PlayAgain:FireServer()
									end
									return
								end
								local notTuff = false
								for _, fuse in gen.Fuses:GetChildren() do
									if tonumber(fuse.Name) and fuse.Fuse.Transparency == 1 then
										notTuff = true
										break
									end
								end
								local prompt = notTuff and (gen:FindFirstChild("FusesPrompt", true) or gen:FindFirstChild("FakePrompt", true))
								if prompt then
									Character:PivotTo(gen:GetPivot())
									fireproximityprompt(prompt)
								elseif not leverActivated then
									prompt = gen.Lever.LeverPrompt
									Character:PivotTo(gen:GetPivot())
									fireproximityprompt(prompt)
									if gen.GeneratorMain.Sound.Playing then
										leverActivated = true
									end
								elseif not buttonPressed then
									local button = Room.Assets.MinesGateButton.Button
									prompt = button.ActivateEventPrompt
									Character:PivotTo(button.CFrame)
									fireproximityprompt(prompt)
									if button.SoundPress.Playing then
										buttonPressed = true
									end
								else
									Character:PivotTo(Door:GetPivot())
								end
							end
						elseif Room:GetAttribute("RawName") == "RippleEnd" then
							if not AutoFloor.OnStatistics then
								AutoFloor.OnStatistics = RippleStatistics.OnClientEvent:Connect(function()
									Library:Notify({
										Title = Info.AddonTitle,
										Description = "每日挑战完成！",
										Time = 10
									})
									Toggles.AutoFloor:SetValue(false)
									Toggles.AutoFloor:SetDisabled(true)
								end)
							end
							Door = Room.RippleExitDoor
							Character:PivotTo(Door:GetPivot())
							fireproximityprompt(Door.Door.EnterPrompt)
						else
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						leverActivated = nil
						buttonPressed = nil
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Garden = {
			Requirements = {
				"firetouchinterest",
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if Variables.tpFunction then
						local tp; tp = hookfunction(Variables.tpFunction, function(...)
							if checkcaller() then
								tp(...)
							end
						end)
					end
					local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
						if not checkcaller() then
							hookfunction(func, function()end)
							Variables.tpFunction = func
						end
						return hook(self, func)
					end)
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					local unavailableUntil = -1/0
					local lastCutscene = ""
					local LOTUS, PICKING_LOTUS = false, false
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						logprint("WORKS")
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						local eyestalkEnd = Room:GetAttribute("RawName") == "Garden_EyestalkEnd" and Toggles.TriggerEyestalkChaseEnd.Value and (lastCutscene ~= "EyestalkOutro" or Character.PrimaryPart.Anchored)
						if os.clock()<unavailableUntil or (eyestalkEnd and Character.PrimaryPart.Anchored) then logprint("RETURNED", os.clock()<unavailableUntil, (eyestalkEnd and Character.PrimaryPart.Anchored))  return end
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						local lotuspetal, drawer, grampy
						local tool = GetEquippedTool(LocalPlayer)
						if Toggles.MakeLotus.Value and not (LocalPlayer.Backpack:FindFirstChild("Lotus") or (tool and tool.Name == "Lotus")) then
							lotuspetal, drawer = GetLotusPetal()
							grampy = CurrentRooms:FindFirstChild("Grampy", true)
							grampy = grampy and (tonumber(grampy.Parent.Parent.Name) or 0) <= LatestRoom.Value and grampy
						end
						local lotuspetaltool = (tool and tool.Name == "LotusPetal" and tool) or LocalPlayer.Backpack:FindFirstChild("LotusPetal")
						local success, forminglotus = pcall(function()
							return Room.Assets.FormingLotus
						end)
						forminglotus = success and forminglotus
						if grampy and not LOTUS and lotuspetaltool and lotuspetaltool:GetAttribute("Durability") > 7 then
							logprint(1)
							PICKING_LOTUS = true
							Character:PivotTo(grampy:GetPivot())
							if lotuspetaltool.Parent ~= Character then
								lotuspetaltool.Parent = Character
							end
							fireproximityprompt(grampy.DialogPrompt)
						elseif grampy and not LOTUS and PICKING_LOTUS then
							if tool and tool.Name == "Lotus" then
								logprint(2.1)
								LOTUS = true
							elseif forminglotus and forminglotus:FindFirstChild("Lotus") then
								logprint(2.2)
								Character:PivotTo(forminglotus:GetPivot())
								fireproximityprompt(forminglotus.Lotus.PromptAttach.ModulePrompt)
							end
						elseif lotuspetal and not (lotuspetaltool and lotuspetaltool:GetAttribute("Durability") > 7) then
							logprint(3)
							Character:PivotTo(lotuspetal:GetPivot())
							if drawer then
								fireproximityprompt(drawer:FindFirstChild("ActivateEventPrompt", true))
							end
							fireproximityprompt(lotuspetal.ModulePrompt)
						elseif eyestalkEnd then
							if not AutoFloor.CutsceneActivated then
								AutoFloor.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
									lastCutscene = name
								end)
							end
							if lastCutscene == "EyestalkOutro" then
								logprint(4.1)
								AutoFloor.CutsceneActivated:Disconnect()
							else
								logprint(4.2)
								Character:PivotTo(Room.EyestalkEndCutscene.Collision.CFrame)
								firetouchinterest(Character.PrimaryPart, Room.EyestalkEndCutscene.Collision, 0)
								firetouchinterest(Character.PrimaryPart, Room.EyestalkEndCutscene.Collision, 1)
							end
						elseif Room.Name == "35" then
							if not AutoFloor.CutsceneActivated then
								AutoFloor.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
									lastCutscene = name
								end)
							end
							if lastCutscene == "BrambleIntro" then
								logprint(5.1)
								local Lever = GetNearestLever(Room)
								if Lever then
									logprint("5.1.1")
									Character:PivotTo(Lever.CFrame)
									fireproximityprompt(Lever.ActivateEventPrompt)
								else
									logprint("5.1.2")
									Character:PivotTo(Room.OutdoorsEnding.Collision.CFrame)
									firetouchinterest(Character.PrimaryPart, Room.OutdoorsEnding.Collision, 0)
									firetouchinterest(Character.PrimaryPart, Room.OutdoorsEnding.Collision, 1)
								end
							elseif lastCutscene == "EyestalkOutro" or lastCutscene == "" then
								logprint(5.2)
								Character:PivotTo(Room.BrambleCutscene.Collision.CFrame)
								firetouchinterest(Character.PrimaryPart, Room.BrambleCutscene.Collision, 0)
								firetouchinterest(Character.PrimaryPart, Room.BrambleCutscene.Collision, 1)
							else
								logprint(5.3)
								Library:Notify({
									Title = Info.AddonTitle,
									Description = "户外挑战完成！",
									Time = 10
								})
								Toggles.AutoFloor:SetValue(false)
								Toggles.AutoFloor:SetDisabled(true)
							end
						else
							logprint(6)
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}`)
						end
						if Toggles.MakeLotus.Value then
							unavailableUntil = os.clock()+.5
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
						restorefunction(Variables.tpFunction)
					end
					if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
						restorefunction(ServerTeleported.OnClientEvent.Connect)
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Backdoor = {
			Requirements = {
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					local unavailableUntil = -1/0
					local key, drawer, timerincreased
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						if os.clock()<unavailableUntil then return end
						activeRusher = ActiveRusher()
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						local timerlever = Room:FindFirstChild("TimerLever", true)
						if timerlever and not timerincreased then
							Character:PivotTo(timerlever:GetPivot())
							fireproximityprompt(timerlever.ActivateEventPrompt)
							if timerlever.TakeTimer.TextLabel.Text == "00:00" then
								timerincreased = true
							end
						elseif Room:GetAttribute("RequiresKey") then
							local item = ItemThatCanUnlock()
							if item then
								if not Variables.InfItems.Value then
									Variables.InfItems:SetValue(true)
								end
								if item:IsA("Tool") and item.Parent ~= Character then
									item.Parent = Character
								elseif item:IsA("Model") then
									item:PivotTo(Character:GetPivot())
									fireproximityprompt(item.ModulePrompt)
								end
								Character:PivotTo(Door:GetPivot())
								local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
								if prompt then
									fireproximityprompt(prompt)
								end
							else
								local tool = GetEquippedTool(LocalPlayer)
								local keyTool = LocalPlayer.Backpack:FindFirstChild("Key") or (tool and tool.Name == "Key" and tool) or LocalPlayer.Backpack:FindFirstChild("KeyBackdoor") or (tool and tool.Name == "KeyBackdoor" and tool)
								if keyTool then
									key = nil
									drawer = nil
									if keyTool.Name == "KeyBackdoor" and keyTool.Parent ~= Character then
										keyTool.Parent = Character
									end
									Character:PivotTo(Door:GetPivot())
									local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
									if prompt then
										fireproximityprompt(prompt)
									end
								else
									if not key or not drawer then
										key, drawer = FindKeyObtain(Room)
									end
									if key then
										Character:PivotTo(drawer and drawer:GetPivot() or key:GetPivot())
										if drawer then
											fireproximityprompt(drawer:FindFirstChild("ActivateEventPrompt", true))
										end
										fireproximityprompt(key.ModulePrompt)
									end
								end
							end
						elseif Room.Name == "50" then
							if not AutoFloor.OnStatistics then
								AutoFloor.OnStatistics = Statistics.OnClientEvent:Connect(function()
									Library:Notify({
										Title = Info.AddonTitle,
										Description = "后门挑战完成！",
										Time = 10
									})
									Toggles.AutoFloor:SetValue(false)
									Toggles.AutoFloor:SetDisabled(true)
								end)
							end
							Door = Room.Backdoors_Exit.Door
							Character:PivotTo(Door:GetPivot())
							fireproximityprompt(Door.EnterPrompt)
						else
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						timerincreased = nil
						room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}\nAnticheat bypass status: {Character:GetAttribute("_BypassedAC") and "ON" or "OFF"}`)
						end
						unavailableUntil = os.clock()+1
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
		Stairwell = {
			Requirements = {
				"fireproximityprompt",
				"hookfunction",
				"restorefunction",
				"isfunctionhooked"
			},
			Callback = function(value)
				if value then
					if Toggles.AntiTeleport.Value then
						Toggles.AntiTeleport:SetValue(false)
					elseif Toggles.AntiTeleportRaknet.Value then
						Toggles.AntiTeleportRaknet:SetValue(false)
					end
					Services.RunService.RenderStepped:Wait()
					Toggles.AntiTeleport:SetDisabled(true)
					if not Toggles.AntiTeleportRaknet.Disabled then
						Toggles.AntiTeleportRaknet:SetDisabled(true)
					end
					Variables.tpFunction = getTpFunction()
					if hookfunction then
						if Variables.tpFunction then
							local tp; tp = hookfunction(Variables.tpFunction, function(...)
								if checkcaller() then
									tp(...)
								end
							end)
						end
						local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
							if not checkcaller() then
								hookfunction(func, function()end)
								Variables.tpFunction = func
							end
							return hook(self, func)
						end)
					end
					local tempRoom = CurrentRooms:FindFirstChild(LatestRoom.Value)
					Variables.AutoFloorRoom = Library:Notify({
						Title = Info.AddonTitle,
						Description = `Doors opened: {LatestRoom.Value}\nCurrent room: {tempRoom and tempRoom:GetAttribute("RawName") or "?"}`,
						Persist = true
					})
					local AutoFloor = {}
					Connections.AutoFloor = AutoFloor
					AutoFloor.Teleporter = Services.RunService.Heartbeat:Connect(function()
						local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
						local Door = Room and Room:FindFirstChild("Door")
						if not Variables.slideSH then
							Variables.slideSH = true
							Crouch:FireServer(true,true)
						end
						for _, toggle in Variables.StuffToKeepEnabled do
							if not toggle.Value and not toggle.Disabled then
								toggle:SetValue(true)
							end
						end
						if LatestRoom.Value > 198 then
							local stairwellexit = Room:FindFirstChild("StairwellExitDoor")
							if stairwellexit then
								Character:PivotTo(stairwellexit:GetPivot())
								fireproximityprompt(stairwellexit.Collision.EnterPrompt)
							else
								Library:Notify({
									Title = Info.AddonTitle,
									Description = "楼梯间已完成！",
									Time = 10
								})
								Toggles.AutoFloor:SetValue(false)
								Toggles.AutoFloor:SetDisabled(true)
							end
						else
							Character:PivotTo(Door:GetPivot())
						end
						if not Library.Toggles.DoorReach.Value then
							Library.Toggles.DoorReach:SetValue(true)
						end
					end)
					AutoFloor.LatestRoomChanged = LatestRoom.Changed:Connect(function()
						if Variables.AutoFloorRoom then
							Variables.AutoFloorRoom:ChangeDescription(`Doors opened: {LatestRoom.Value}\nCurrent room: {room and room:GetAttribute("RawName") or "?"}`)
						end
					end)
				else
					if Variables.AutoFloorRoom then
						Variables.AutoFloorRoom:Destroy()
					end
					if not Toggles.SlideSpeedHack and Variables.slideSH then
						Variables.slideSH = false
						Crouch:FireServer(true,true)
					end
					Toggles.AntiTeleport:SetDisabled(false)
					if Variables.raknet_at_hook then
						Toggles.AntiTeleportRaknet:SetDisabled(false)
					end
					if isfunctionhooked and restorefunction then
						if Variables.tpFunction and isfunctionhooked(Variables.tpFunction) then
							restorefunction(Variables.tpFunction)
						end
						if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
							restorefunction(ServerTeleported.OnClientEvent.Connect)
						end
					end
					if Connections.AutoFloor then
						for _, connection in Connections.AutoFloor do
							connection:Disconnect()
						end
						Connections.AutoFloor = nil
					end
				end
			end
		},
	}

	function ExecutorSupported(AutoFloor)
		for _, funcName in AutoFloor.Requirements do
			if not (getgenv and getgenv()[funcName]) then
				return false
			end
		end
		return true
	end

	Variables.AutoFloorFunc = Variables.AutoFloors[Floor] or Variables.AutoFloors[`{Floor}_{FloorSpecific}`]
	Variables.AutoFloorSupported = ExecutorSupported(Variables.AutoFloorFunc or {Requirements = {}})

	Toggles.AutoFloor = Groupbox:AddToggle(prefix.."AutoFloor", {
		Text = "自动楼层",
		DisabledTooltip = Variables.AutoFloorSupported and (Variables.AutoFloorFunc and "Floor is already completed" or "Auto Floor is not supported for this floor") or "Executor is not supported",
		Default = false,
		Disabled = not (Variables.AutoFloorSupported and Variables.AutoFloorFunc),

		Callback = Variables.AutoFloorFunc and Variables.AutoFloorFunc.Callback or function()end
	})

	if Floor == "Garden" then
		local cutscenes = {}
		Connections.OnCutsceneSEC = Cutscene.OnClientEvent:Connect(function(name)
			if not table.find(cutscenes, name) then
				table.insert(cutscenes, name)
			end
		end)

		Toggles.SkipEyestalkChase = Groupbox:AddToggle(prefix.."SkipEyestalkChase", {
			Text = "跳过眼柄追逐 [FE]",
			DisabledTooltip = Variables.AutoFloorSupported and "Eyestalk chase was skipped" or "Executor is not supported",
			Default = false,
			Disabled = not Variables.AutoFloorSupported,

			Callback = function(value)
				if value then
					Connections.SECConnection = Services.RunService.RenderStepped:Connect(function()
						if table.find(cutscenes, "EyestalkOutro") then
							if Toggles.AutoFloor.Value then
								Toggles.AutoFloor:SetValue(false)
							end
							if Toggles.TriggerEyestalkChaseEnd.Value then
								Toggles.TriggerEyestalkChaseEnd:SetValue(true)
							end
							Toggles.SkipEyestalkChase:SetValue(false)
							Toggles.SkipEyestalkChase:SetDisabled(true)
						elseif table.find(cutscenes, "EyestalkIntro") then
							if not Toggles.TriggerEyestalkChaseEnd.Value then
								Toggles.TriggerEyestalkChaseEnd:SetValue(true)
							end
							if not Toggles.AutoFloor.Value then
								Toggles.AutoFloor:SetValue(true)
							end
						end
					end)
				else
					if Connections.SECConnection then
						Connections.SECConnection:Disconnect()
					end
					if Toggles.AutoFloor.Value then
						Toggles.AutoFloor:SetValue(false)
					end
				end
			end
		})

		Toggles.TriggerEyestalkChaseEnd = Groupbox:AddToggle(prefix.."TriggerEyestalkChaseEnd", {
			Text = "触发眼柄追逐结束",
			Tooltip = "启用自动楼层时不要跳过结束眼柄追逐的触发器",
			DisabledTooltip = "当前执行器不支持",
			Default = false,
			Disabled = not Variables.AutoFloorSupported
		})

		Toggles.MakeLotus = Groupbox:AddToggle(prefix.."MakeLotus", {
			Text = "制作莲花",
			Tooltip = "自动楼层应收集莲花花瓣来制作莲花",
			DisabledTooltip = "当前执行器不支持",
			Default = false,
			Disabled = not Variables.AutoFloorSupported
		})
	end

	function CustomContinueOrSave()
		task.defer(function()
			RequestLocalAsset:InvokeServer({{}})
			PlayAgain:FireServer()
		end)
		return true, nil
	end

	Variables.OldContinueOrSave = getcallbackvalue and getcallbackvalue(ContinueOrSave, "OnClientInvoke") or CustomContinueOrSave
	Variables.ContinueOrSaveHook = hookmetamethod and hookmetamethod(game, "__newindex", function(self, key, value)
		if not checkcaller() and self == ContinueOrSave and key == "OnClientInvoke" then
			Variables.OldContinueOrSave = value
			if Toggles.AutoPlayAgain.Value then
				value = CustomContinueOrSave
			end
		end
		return Variables.ContinueOrSaveHook(self, key, value)
	end)

	Toggles.AutoPlayAgain = Groupbox:AddToggle(prefix.."AutoPlayAgain", {
		Text = "自动重开",
		Tooltip = "启用快速结局后效果更好",
		DisabledTooltip = "当前执行器不支持",
		Default = false,
		Disabled = not Variables.ContinueOrSaveHook,

		Callback = function(value)
			if value then
				ContinueOrSave.OnClientInvoke = CustomContinueOrSave
				Connections.OnStatistics = Statistics.OnClientEvent:Connect(function()
					task.delay(.01, PlayAgain.FireServer, PlayAgain)
				end)
			else
				ContinueOrSave.OnClientInvoke = Variables.OldContinueOrSave
				if Connections.OnStatistics then
					Connections.OnStatistics:Disconnect()
				end
			end
		end
	})

	function clearEverything(list: {})
		list = typeof(list) == "table" and list or {}
		for _, val in list do
			if typeof(val) == "table" then
				clearEverything(val)
			elseif typeof(val) == "RBXScriptConnection" then
				pcall(val.Disconnect, val)
			elseif typeof(val) == "Instance" then
				pcall(val.Destroy, val)
			end
			val = nil
		end
	end

	OnUnload(function(wasReloaded)
		for _, toggle in Toggles do
			if toggle.Value then
				pcall(toggle.Callback, false)
			end
		end
		if deathHintConnection then
			deathHintConnection:Disconnect()
			deathHintConnection = nil
		end
		clearEverything(Connections)
		clearEverything(StuffToRemoveLater)
		GlobalIgnoreList = nil
		ScreenGui:Destroy()
		restoremetamethods()
		if Variables.ACBypassNotify then
			Variables.ACBypassNotify:Destroy()
			Variables.ACBypassNotify = nil
		end
		if Variables.admin then
			task.spawn(function()
				clearEverything(ItemsFromAddon)
				Variables.admin.AdminPanel.PanelClient.Enabled = false
				Variables.admin.Container.Pages:ClearAllChildren()
				local lol = Variables.admin.Container.TabButtons.UIListLayout:Clone()
				Variables.admin.Container.TabButtons:ClearAllChildren()
				lol.Parent = Variables.admin.Container.TabButtons
				Variables.admin.AdminPanel.PanelClient.Enabled = true
				Variables.admin = nil
			end)
		end
		print(`[{Info.AddonTitle}]: {wasReloaded and "reloaded" or "unloaded"}!`)
	end)
elseif game.GameId == 6352299542 then
	if game.PlaceId == 18749553947 or game.PlaceId == 121496416407905 then
		local GenerateText = Services.ReplicatedStorage.Remotes.GenerateTextClient

		local function sendmessage(string, type)
			if firesignal then
				if type == "error" then
					firesignal(GenerateText.OnClientEvent, string, "none", Color3.new(1,0.25,0.25))
				end
				if type == "success" then
					firesignal(GenerateText.OnClientEvent, string, "none", Color3.new(0.25,1,0.25))
				end
				if type == "message" then
					firesignal(GenerateText.OnClientEvent, string, "none", "none")
				end
			end
		end

		local CreateServer = Services.Players.LocalPlayer.PlayerGui.MainGui.MainMenuFrames.ServersFrame.CreateServerFrame.MainFrame.CreateButton.r1
		local JoinServer = Services.Players.LocalPlayer.PlayerGui.MainGui.MainMenuFrames.ServersFrame.MainFrame.ClickedOnServerCall
		local args = {}
		local servers = workspace.ServersFolder.MainServersHolder
		local LocalPlayer = Services.Players.LocalPlayer

		-- 默认值
		Mode = "Normal"
		Rooms = "Main Game"
		Difficulty = "Normal"
		MaxPlayers = 4
		Password = ""
		LobbyName = ""
		SelectedPlr = nil

		Groupbox:AddInput(prefix.."mode", {
			Text = "模式",
			ClearTextOnFocus = true,
			Default = "None",
			Callback = function(val)
				Mode = val
			end
		})

		Groupbox:AddInput(prefix.."rooms", {
			Text = "房间",
			ClearTextOnFocus = true,
			Default = "Main Game",
			Callback = function(val)
				Rooms = val
			end
		})

		Groupbox:AddInput(prefix.."diff", {
			Text = "难度",
			ClearTextOnFocus = true,
			Default = "Normal",
			Callback = function(val)
				Difficulty = val
			end
		})

		Groupbox:AddInput(prefix.."players", {
			Text = "玩家",
			Default = 4,
			Numeric = true,
			ClearTextOnFocus = true,
			Callback = function(val)
				MaxPlayers = val
			end
		})

		Groupbox:AddInput(prefix.."pass", {
			Text = "密码",
			ClearTextOnFocus = true,
			Callback = function(val)
				Password = val
			end
		})

		Groupbox:AddInput(prefix.."lobbyname", {
			Text = "房间名",
			ClearTextOnFocus = true,
			Callback = function(val)
				LobbyName = val
			end
		})

		local bypassedpatch = false

		Groupbox:AddButton(prefix.."bypassmaxhealthpatch", {
			Text = "绕过生命值上限补丁",
			Tooltip = "按下此按钮并开始游戏后，你可以修改生命值上限",
			Default = false,
			Func = function()
				if not bypassedpatch then
					bypassedpatch, _ = pcall(function()
						queue_on_teleport('local event = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 60):WaitForChild("EditValueCall", 60) if not event then return end local bypass; bypass = hookmetamethod(game, "__namecall", function(self, ...) local args = {...} if self == event and getnamecallmethod() == "FireServer" and args[1] == "blockmaxhealthfuturechanges" then return end return bypass(self, ...) end) _G.BypassedMaxHealthPatch = true')
					end)
					if bypassedpatch then
						sendmessage("[Bypass Max Health Patch] Patch bypassed", "success")
					else
						sendmessage("[Bypass Max Health Patch] Failed to bypass patch", "error")
					end
				else
					sendmessage("[Bypass Max Health Patch] Patch is already bypassed", "error")
				end
			end
		})

		Groupbox:AddButton(prefix.."createlobby", {
			Text = "创建房间",
			Func = function()
				if LobbyName:gsub("%s+") == "" then LobbyName = nil end
				local solo = nil
				local args = {}
				args = {
					Mode = Mode, 
					Room = Rooms, 
					Difficulty = Difficulty, 
					MaxPlayers = tonumber(MaxPlayers)
				}
				if game.PlaceId == 121496416407905 then
					args.RoomName = LobbyName
				elseif game.PlaceId == 18749553947 then
					args.Name = LobbyName
				end
				solo = tonumber(MaxPlayers) <= 1 or Rooms == "Testrooms"
				if Password:gsub("%s+") ~= "" then
					args.Password = Password
				end
				CreateServer:FireServer(args, solo)
				local timestamp = os.clock()
				local server = servers:WaitForChild(LocalPlayer.Name, 5)
				if server then
					sendmessage(`[Create Lobby] Created lobby successfully [ {math.floor((os.clock()-timestamp)*10)/10} sec ]`, "success")
				else
					sendmessage("[Create Lobby] Failed to create a lobby", "error")
				end
			end
		})

		Groupbox:AddDivider()

		Groupbox:AddDropdown(prefix.."selectedplr", {
			SpecialType = 'Player',
			Text = '已选玩家',
			Default = nil,
			AllowNull = true,
			Multi = false,

			Callback = function(player)
				SelectedPlr = player
			end
		})

		Groupbox:AddButton(prefix.."joinlobby", {
			Text = "加入玩家房间",
			Func = function()
				if SelectedPlr == nil then sendmessage("[Join Player Lobby] Please select a player", "error") else
					if servers:FindFirstChild(SelectedPlr.Name) then
						if not servers[SelectedPlr.Name].PlayersFolder:FindFirstChild(LocalPlayer.Name) then
							for _,_ in inservers:QueryDescendants(`StringValue[Name = {LocalPlayer.Name}]`) do
								return sendmessage("[Join Player Lobby] You already in a lobby, please leave it if you want to join another one", "error")
							end
							JoinServer:FireServer(SelectedPlr.Name)
							local value = servers[SelectedPlr.Name].PlayersFolder:WaitForChild(LocalPlayer.Name, 3)
							if value then
								sendmessage("[Join Player Lobby] Joined the lobby successfully", "success")
							else
								sendmessage("[Join Player Lobby] Failed to join the lobby", "error")
							end
						else
							sendmessage("[Join Player Lobby] You're already in this lobby", "error")
						end
					else
						sendmessage("[Join Player Lobby] Player didn't created lobby", "error")
					end
				end   
			end
		})

		OnUnload(function(wasReloaded)
			print(`[{Info.AddonTitle}]: {wasReloaded and "reloaded" or "unloaded"}!`)
		end)
	else
		local UserInputService = Services.UserInputService
		local GenerateText = Services.ReplicatedStorage.Remotes.GenerateTextClient

		local function sendmessage(string, type)
			if type == "error" then
				GenerateText:FireServer(string, "none", Color3.new(1,0.25,0.25))
			end
			if type == "success" then
				GenerateText:FireServer(string, "none", Color3.new(0.25,1,0.25))
			end
			if type == "message" then
				GenerateText:FireServer(string, "none", "none")
			end
		end

		-- 文件夹
		local ens = workspace.Entities
		local remotes = game.Services.ReplicatedStorage.Remotes

		-- 玩家相关
		local player = Services.Players.LocalPlayer
		local char = player.Character
		local backpack = player.Backpack
		local tpobbycall = remotes.EntityTpObbyCall
		local kys = remotes.KillPlayerCall
		local damagecall = remotes.DamageCall
		local editvalue = remotes.EditValueCall
		local breathingsound = remotes.BreathingSoundCall

		-- 混沌事件
		local events = {}
		for _, event in workspace.GameData.ChaosMode.MainChaosScript:GetChildren() do
			if event:IsA("LocalScript") then
				table.insert(events, event.Name)
			end
		end

		-- 生命值管理
		local Health = char.HealthManager

		-- 函数
		local function edithealth(value)
			if remotes:FindFirstChild("EditValueCall") and Health.MaxHealth.Value-Health.Value > 0 then
				editvalue:FireServer("health", (value <= (Health.MaxHealth.Value-Health.Value) and value or Health.MaxHealth.Value-Health.Value))
			end
		end
		local function setmaxhealth(value)
			if remotes:FindFirstChild("EditValueCall") and _G.BypassedMaxHealthPatch then
				editvalue:FireServer("maxhealth", value-Health.MaxHealth.Value)
			end
		end
		local function annoyplayer(player, volume)
			breathingsound:FireServer(0,volume,player)
		end

		-- 检查地点
		local PlaceIssue = game.PlaceId == 131662053719761
		local PlaceIssue2 = game.PlaceId == 131662053719761 or game.PlaceId == 126817484851889
		local PlaceIssue3 = game.PlaceId == 126817484851889

		local function deluludelete(instance)
			player.Character.CharacLocalScripts.PlayerInteractObjects.r1:FireServer({
				["maxrange"] = math.huge,
				["hittarget"] = instance,
				["camcframe"] = CFrame.new(0, -1000000, 0)
			})
			player.Character.CharacLocalScripts.PlayerInteractObjects.r1:FireServer({
				["unanchortarget"] = true
			})
		end

		-- 默认值
		local AllPlayers = false
		local SelectedPlayer = player.Name
		local DashBoostValue = 40
		local AccelerationValue = 0.015

		local Acceleration, OldAccelerationValue, OldDashCD, DashBoost, OldDashBoostValue, MaxHealthOld

		Groupbox:AddDivider({
			Text = "生命值管理器",
			MarginTop = 2,
			MarginBottom = -2
		})

		Toggles.godmode = Groupbox:AddToggle(prefix.."godmode",{
			Text = '无敌模式',
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue,
			Callback = function(value)
				if value then
					kys.Name = "_KillPlayerCall"
					damagecall.Name = "_DamageCall"
					MaxHealthOld = Health.MaxHealth.Value
					setmaxhealth(100000)
					loopheal = Services.RunService.Heartbeat:Connect(function()
						edithealth(1/0)
					end)
				else
					if loopheal then
						loopheal:Disconnect()
					end
					setmaxhealth(MaxHealthOld)
					MaxHealthOld = nil
					kys.Name = "KillPlayerCall"
					damagecall.Name = "DamageCall"
				end
			end
		})

		Toggles.restorehp = Groupbox:AddButton(prefix.."restorehp",{
			Text = '恢复生命值',
			--Tooltip = "Can trigger anticheat, i don't recommend to use it"
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue,
			Func = function()
				edithealth(1/0)
			end
		})

		Groupbox:AddDivider({
			Text = "移动",
			MarginTop = 2,
			MarginBottom = -2
		})

		local function bool2Int(bool: boolean): number
			return bool and 1 or 0
		end

		Toggles.nodashcd = Groupbox:AddToggle(prefix.."nodashcd",{
			Text = '移除冲刺冷却',
			Default = false,
			DisabledTooltip = reason,
			Disabled = PlaceIssue or isgetconnectionsmissing,
			Callback = function(value)
				if value then
					OldDashCD = debug.getupvalue(debug.getupvalue(getconnections(char.AttributeChanged)[1].Function, 2), 2)
					debug.setupvalue(debug.getupvalue(getconnections(char.AttributeChanged)[1].Function, 2), 2, 0)
				else
					debug.setupvalue(debug.getupvalue(getconnections(char.AttributeChanged)[1].Function, 2), 2, OldDashCD)
				end
			end
		})

		Toggles.nojumpcd = Groupbox:AddToggle(prefix.."nojumpcd",{
			Text = '移除跳跃冷却',
			Default = false,
			Callback = function(value)
				char.CharacterValues.LowerJumpCooldown.Value = bool2Int(value)
				while Toggles.nojumpcd.Value and task.wait() do
					char.CharacterValues.LowerJumpCooldown.Value = bool2Int(Toggles.nojumpcd.Value)
				end
			end
		})

		Toggles.autokick = Groupbox:AddToggle(prefix.."autokick",{
			Text = '自动踢人',
			Default = false,
			DisabledTooltip = reason,
			Disabled = PlaceIssue,
			Callback = function(value)
				editvalue:FireServer("editvalcharacter"..(value and "enable" or "disable"), "AutoKick")
				while Toggles.autokick.Value do
					task.wait()
					if not char.CharacterValues.AutoKick.Value then
						editvalue:FireServer("editvalcharacter"..(Toggles.autokick.Value and "enable" or "disable"), "AutoKick")
					end
				end
			end
		})

		local kickremote = char.MainControls.ScriptsForCall.KickRemote
		local kickFire; kickFire = hookmetamethod(game, "__namecall", function(self, ...)
			if not checkcaller() and self == kickremote and getnamecallmethod() == "FireServer" and Toggles.nokickcd.Value then
				return
			end
			return kickFire(self, ...)
		end)

		Toggles.nokickcd = Groupbox:AddToggle(prefix.."nokickcd",{
			Text = '移除踢人冷却',
			Default = false,
			Callback = function(value)
				if value then
					nocdkick = UserInputService.InputBegan:Connect(function(input)
						if input.KeyCode == Enum.KeyCode.F then
							if char.WalkspeedManager.Value < 52 then
								kickremote:FireServer(false)
							else
								kickremote:FireServer(true)
							end
						end
					end)
				else
					if nocdkick then
						nocdkick:Disconnect()
					end
				end
			end
		})

		Groupbox:AddDivider({
			Text = "杂项",
			MarginTop = 2,
			MarginBottom = -2
		})

		Toggles.nochaosevents = Groupbox:AddToggle(prefix.."nochaosevents",{
			Text = '禁用混沌事件',
			Tooltip = '仅客户端事件',
			DisabledTooltip = reason2,
			Disabled = PlaceIssue2,
			Default = false,
			Callback = function(value)
				if value then
					loopdisablechaos = game.DescendantAdded:Connect(function(descendant)
						if table.find(events, descendant.Name) then
							descendant:Destroy()
						end
					end)
				else
					if loopdisablechaos then
						loopdisablechaos:Disconnect()
					end
				end
			end
		})

		--[[Groupbox:AddButton(prefix.."callvoidtp",{
			Text = '调用虚空传送',
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue,
			Func = function()
				if mspaint.ExecutorSupport["firetouchinterest"] then
					firetouchinterest(workspace.RoomsHolder.AntivoidPart.MainAntivoidPart, char.HumanoidRootPart, 0)
					task.delay(0.1, function() firetouchinterest(workspace.RoomsHolder.AntivoidPart.MainAntivoidPart, char.HumanoidRootPart, 1) end)
				else
					char:MoveTo(workspace.RoomsHolder.AntivoidPart.MainAntivoidPart.Position)
				end
			end
		})]]

		Groupbox:AddButton(prefix.."getbadge1",{
			Text = '获取徽章 "未觉醒"',
			DisabledTooltip = reason,
			Disabled = queueteleportmissing,
			Func = function()
				Services.TeleportService:Teleport(105262163721105, player)
				QueueTeleport([[
            if not game.Loaded then
                game.Loaded:Wait()
            end
            local badge = game:GetService("BadgeService"):CheckUserBadgesAsync(game.Players.LocalPlayer.UserId, {1289197938381069})
            if #badge == 1 then
                game.Players.LocalPlayer:Kick("you already have this badge")
            end
            game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("badgecall"):FireServer()
            print("Getting Badge...")
            wait(3)
            game.Players.LocalPlayer:Kick("aaaa badge")
        ]])
			end
		})

		Groupbox:AddButton(prefix.."getbadge2",{
			Text = '获取徽章 "场地"',
			DisabledTooltip = reason,
			Disabled = queueteleportmissing,
			Func = function()
				Services.TeleportService:Teleport(98402192137325, player)
				QueueTeleport([[
            if not game.Loaded then
                game.Loaded:Wait()
            end
            local badge = game:GetService("BadgeService"):CheckUserBadgesAsync(game.Players.LocalPlayer.UserId, {1624501183928838})
            if #badge == 1 then
                game.Players.LocalPlayer:kick("you already have this badge")
            end
            game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("badgecall"):FireServer()
            print("Getting Badge...")
            wait(3)
            game.Players.LocalPlayer:kick("aaaa badge")
        ]])
			end
		})

		Groupbox:AddButton(prefix.."deleteobjects",{
			Text = '删除物体',
			Func = function()
				for i,v in workspace:QueryDescendants("#DeskChair, #PottedPlant, #TableLamp, #DeskChair, #MetalShelf, #PapersAsset, #metalfence") do
					deluludelete(v)
				end
			end
		})

		Groupbox:AddDivider({
			Text = "恶搞",
			MarginTop = 2,
			MarginBottom = -2
		})

		Groupbox:AddDropdown(prefix.."players",{
			SpecialType = 'Player',
			Text = '已选玩家',
			Default = Services.Players.LocalPlayer.Name,
			AllowNull = true,
			Multi = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue3,
			Callback = function(value)
				player.PlayerGui.SpectateGui.MainSpectateScript.r1:FireServer(value.Name)
				SelectedPlayer = value.Name
			end
		})

		Toggles.annoyplayer = Groupbox:AddToggle(prefix.."annoyplayer",{
			Text = "骚扰玩家",
			Tooltip = "让某个玩家发出呼吸声（仅1名玩家）",
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue3,
			Callback = function(value)
				if value then
					AnnoyPlayer = SelectedPlayer
					loopannoy = Services.RunService.RenderStepped:Connect(function()
						annoyplayer(SelectedPlayer,10)
						if SelectedPlayer ~= AnnoyPlayer then
							annoyplayer(AnnoyPlayer,0)
							AnnoyPlayer = SelectedPlayer
						end
					end)
				else
					if loopannoy then
						loopannoy:Disconnect()
						annoyplayer(AnnoyPlayer,0)
						AnnoyPlayer = nil
					end
				end
			end
		})

		Groupbox:AddDivider({
			Text = "反实体",
			MarginTop = 2,
			MarginBottom = -2
		})

		local tpobbyfire; tpobbyfire = hookmetamethod(game, "__namecall", function(self, ...)
			if self == tpobbycall and getnamecallmethod() == "FireServer" and Toggles.antihand then
				return
			end
			return tpobbyfire(self, ...)
		end)

		Toggles.antihand = Groupbox:AddToggle(prefix.."antihand",{
			Text = '反手 (EN-009) 障碍赛',
			Tooltip = "移除障碍赛但保留他本人",
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue
		})

		Toggles.antidelmon = Groupbox:AddToggle(prefix.."antidelmon",{
			Text = '反 Delmon 水晶 (EN-019)',
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue,
			Callback = function(value)
				if value then
					for i,v in workspace:GetChildren() do
						if v.Name == "GlassSpikeStructureSpawnIndicator" or v.Name == "GlassSpikeStructure" then
							v:Destroy()
						end
					end
					local loopantien019; loopantien019 = workspace.ChildAdded:Connect(function()
						if v.Name == "GlassSpikeStructureSpawnIndicator" or v.Name == "GlassSpikeStructure" then
							v:Destroy()
						end
					end)
				else
					if loopantien019 then
						loopantien019:Disconnect()
					end
				end
			end
		})

		Toggles.antistalker = Groupbox:AddToggle(prefix.."antistalker",{
			Text = '反跟踪者 (EN-016, EN-016-02)',
			Default = false,
			Callback = function(value)
				if value then
					local loopantistalker; loopantistalker = ens.OtherEntities.ChildAdded:Connect(function(child)
						if child.Name == "StalkerEntityAlreadyAttacked" then
							task.spawn(function()
								if Lighting:WaitForChild("ColorCorrection", 3) then
									Lighting.ColorCorrection:Destroy()
								end
								if Lighting:FindFirstChild("ColCorrectionType2Stalker", 3) then
									Lighting.ColCorrectionType2Stalker:Destroy()
								end
							end)
							char:WaitForChild("StalkerType2ScreenShake", 60):Destroy()
							char:WaitForChild("EntityLocalScript", 60):Destroy()
							child:Destroy()
						end
					end)
				else
					if loopantistalker then
						loopantistalker:Disconnect()
					end
				end
			end
		})

		Toggles.antiunknown = Groupbox:AddToggle(prefix.."antiunknown",{
			Text = '反 EN-013',
			Default = false,
			DisabledTooltip = reason2,
			Disabled = PlaceIssue,
			Callback = function(value)
				if value then
					local loopantien013; loopantien013 = ens.Rushers.ChildAdded:Connect(function(child)
						if child.Name == "UnknownEntityAlreadyAttacked" then
							char:WaitForChild("EntityLocalScript", 60):Destroy()
							child:Destroy()
						end
					end)
				else
					if loopantien013 then
						loopantien013:Disconnect()
					end
				end
			end
		})

		Toggles.antidelusion = Groupbox:AddToggle(prefix.."antidelusion",{
			Text = '反妄想 (EN-011)',
			Default = false,
			Callback = function(value)
				if value then
					local loopantidelusion; loopantidelusion = ens.ClientEntities.ChildAdded:Connect(function(child)
						if child.Name == "ShadowEntity" then
							child:Destroy()
						end
					end)
				else
					if loopantidelusion then
						loopantidelusion:Disconnect()
					end
				end
			end
		})

		sendmessage("@tplaygd: just let you know that the addon is loaded", "message")

		OnUnload(function(wasReloaded)
			for _, toggle in Toggles do
				if toggle.Value then
					pcall(toggle.Callback, false)
				end
			end
			restoremetamethods()
			print(`[{Info.AddonTitle}]: {wasReloaded and "reloaded" or "unloaded"}!`)
		end)
	end
elseif game.GameId == 8507497593 then
	local LocalPlayer = Services.Players.LocalPlayer
	local Character = LocalPlayer.Character

	local RemotesFolder = Services.ReplicatedStorage.RemotesFolder

	local Cutscene = RemotesFolder.Cutscene
	local Vote = RemotesFolder.Vote

	local CurrentRooms = workspace.CurrentRooms
	local LatestRoom = Services.ReplicatedStorage.GameData.LatestRoom

	local AutoFarmSupported = fireproximityprompt and firetouchinterest
	local Connections = {}

	Toggles.AutoFarm = Groupbox:AddToggle(prefix.."AutoFarm", {
		Text = "自动刷取",
		DisabledTooltip = "当前执行器不支持",
		Default = false,
		Disabled = not AutoFarmSupported,

		Callback = function(value)
			if value then
				Services.RunService.RenderStepped:Wait()
				local AutoFarm = {}
				Connections.AutoFarm = AutoFarm
				local unavailableUntil = -1/0
				local lastCutscene = ""
				local notified = false
				AutoFarm.CutsceneActivated = Cutscene.OnClientEvent:Connect(function(name)
					lastCutscene = name
				end)
				AutoFarm.Teleporter = Services.RunService.Heartbeat:Connect(function()
					if not LocalPlayer:GetAttribute("InGame") then
						Vote:FireServer((Services.ReplicatedStorage:GetAttribute("ServerType") or 1) > 1 and 6 or 4)
						return
					end
					if os.clock()<unavailableUntil then return end
					local Room = CurrentRooms:FindFirstChild(LatestRoom.Value)
					local Door = Room and Room:FindFirstChild("Door")
					if Room and Room:GetAttribute("RawName") == "Garden_EyestalkStart" and lastCutscene ~= "EyestalkIntro" then
						Character:PivotTo(Room.TriggerEventCollision.Collision.CFrame)
						firetouchinterest(Character.PrimaryPart, Room.TriggerEventCollision.Collision, 0)
						firetouchinterest(Character.PrimaryPart, Room.TriggerEventCollision.Collision, 1)
					elseif Room:GetAttribute("RawName") == "Garden_EyestalkEnd" then
						if lastCutscene == "EyestalkOutro" and not notified then
							notified = true
							Library:Notify({
								Title = Info.AddonTitle,
								Description = "眼柄追逐已完成！",
								Time = 10
							})
						else
							Character:PivotTo(Room.EyestalkEndCutscene.Collision.CFrame)
							firetouchinterest(Character.PrimaryPart, Room.EyestalkEndCutscene.Collision, 0)
							firetouchinterest(Character.PrimaryPart, Room.EyestalkEndCutscene.Collision, 1)
						end
					else
						Character:PivotTo(Door:GetPivot())
						Door.ClientOpen:FireServer()
					end
				end)
				for _, descendant in CurrentRooms:QueryDescendants("#ClientOpen") do
					if descendant:IsA("RemoteEvent") then
						descendant:FireServer()
					end
				end
				AutoFarm.OnClientOpenRemoteSpawn = CurrentRooms.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("RemoteEvent") and descendant.Name == "ClientOpen" then
						descendant:FireServer()
					end
				end)
				AutoFarm.LatestRoomChanged = LatestRoom.Changed:Connect(function()
					room = CurrentRooms:FindFirstChild(LatestRoom.Value)
				end)
				AutoFarm.InGameChanged = LocalPlayer:GetAttributeChangedSignal("InGame"):Connect(function()
					notified = false
				end)
			else
				if Connections.AutoFarm then
					for _, connection in Connections.AutoFarm do
						connection:Disconnect()
					end
					Connections.AutoFarm = nil
				end
			end
		end
	})

	OnUnload(function(wasReloaded)
		for _, toggle in Toggles do
			if toggle.Value then
				pcall(toggle.Callback, false)
			end
		end
		print(`[{Info.AddonTitle}]: {wasReloaded and "reloaded" or "unloaded"}!`)
	end)
else
	Groupbox:AddLabel(`<font color="#f00">Game is not supported</font>\n\n{Info.AddonTitle} supports these games:\n\nDoors (Lobby & Game),\nDelusional Office (Lobby & Game, Recommend to use in testplace),\nEyestalk Chase Practice\n\n`, true)
end

Groupbox:AddDivider({
	Text = "最重要的功能",
	MarginTop = 2,
	MarginBottom = -2
})

Groupbox:AddButton(prefix.."FunnyButton", {
	Text = "不要按这个按钮...",
	Func = function()
		local TextBox = Instance.new("TextBox", gethui().Obsidian)
		task.spawn(function()
			while TextBox.Parent do
				local a = workspace.CurrentCamera.ViewportSize
				local b = gethui().Obsidian.AbsoluteSize
				TextBox.Size = UDim2.new(0,a.X,0,a.Y)
				TextBox.Position = UDim2.new(0,b.X-a.X,0,b.Y-a.Y)
				task.wait()
			end
		end)
		TextBox.TextEditable = false
		TextBox.ClearTextOnFocus = false
		TextBox.BackgroundColor3 = Color3.new()
		TextBox.TextColor3 = Color3.new(1,1,1)
		TextBox.FontFace = Font.fromEnum(Enum.Font.Code)
		TextBox.TextSize = 12
		TextBox.ZIndex = 2147483647
		TextBox.Text = [[                                            ::::::::::::::                                             :::::::::::                                    
                                      -:::::::::::::::-----::::                                  ::::::::::::::::::::::                               
                                    ::::::::::::::::::------::::::                            :::::::::::::::::::::::::::                             
                                  ::::::::::::::::::::------::::::::                        :::::::::::::::::::::::::::::::                           
                                ::::::::::::::::::::::::---::::::::::                      :::::::::::::::::::::::::::::::::                          
                               ::::::::::::::::                   ::                       :::::               ::::::::::::::                         
                             ::::::::::::::                                                                       :-:-::::::::                        
                            :::::::::::-                                                                             ---:::::::                       
                           :::::::----                                                                                -----::::-                      
                          :::::::---                                                                                    -----::-:                     
                          ::::::::                                                                                       :-------                     
                         ::::::::                             %#%%%%%%%%%%%%%%%%%%%%%%                                     ------:                    
                        :::::::                      %%%%###############################%#%%%%%#                            ------:                   
                       :::::::                 %%%################################################%%%%                        -----                   
                       -::::              ##############################################################%%#                    -----                  
                       ---:           #######################################################################%#                 ----                  
                                   #############################################################################%%               ---                  
                               #%####################################################################################                                 
                            #%#########################################################################################%                              
                          #################################################################################################                           
                       ######################################################################################################                         
                     ###########%%%%%%%%%%%%%%#######################################################%%%%%%%%%%%%%%%%%#########                       
                   #######%%%@@@@%@@@@@@@@@@%%%@@@%##*####################%%%%%%#################%@@@@@@@@@@@@@@@@%%%%@@%%%######                     
                 ######%%%%%%%%%%%%%%%@@@@%%%%%%%%%%@@%**#####################################@@@@@@@@@@@@@%%%%%%%%%%%%@@@@@%%#####                   
                #####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@#*################################%@@@@@@@@@@@%%@%%%%%%%%%%%%%%%%%@@@@@%####                 
              #####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@#*############################%@@@@@@@%%%%%%%@%%%%%%%%%%%%%%%%%%%%@@@@@#####               
            #####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@@@@**########################%@@%%%%%%%%%%%%%@%%%%%%%%%%%%%%%%%%%%%%%@@@@%####              
           #####%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@@@@@#*######################@%%%%%%%%%%%%%@@@@@@@@@@@@@@%%%%%%%%%%%%%%@@@@@%####            
          #####%%%%%%%%%%%%%%%%%%%%%%%%%%@@@@@@@@@@@@@@@@@@@@@@%**###################@%%%%%%%%%%%@@@@%+---:::::--=#%@%%%%%%%%%%%%%%@@@%####           
         #####%%%%%%%%%%%%%%%%%%%%%%%@@@#=-::::::::::-#@@@@@@@@@%**#################%%%%%%%%%%%@@#-:::::::::::::::::-#@@%%%%%%%%%%%%%@@%*###          
       ###*##%%%%%%%%%%%%%%%%%%%%%%@@*-:::::::::::::::::+@@@@@@@@%**###############%%%%%%%%%%@@*:::::::::::::::::--====#@@%%%%%%%%%%%%%@#*###         
      ####*#%%%%%%%%%%%%%%%%%%%%%%@*::::::::::::::::::-==-*@@@@@@@#*##############%%%%%%%%%%@%-:::::::::::::::::=++====-+%@%%%%%%%%%%%%@%#*###        
     ####*##%%%%%%%%%%%%%%%%%%%%%%-:::::::::::::::::=++===-=@@@@@@%**#############%%%%%%%%%%*::::::::::::::::::-+++====--+@@%%%%%%%%%%%%@#**###       
     ####*#%%%%%%%%%%%%%%%%%%%%%#::::::::::::::::::-++====---%@@@@@**###########*%%%%%%%%%%#::::::::::::::::::::++=====---%@%%%%%%%%%%%%@%**####      
    ####**#%%%%%%%%%%%%%%%%%%%%#:::::::::::::::::::-++====---=@@@@@#*############%%%%%%%%%%::::::::::::::::::::::-====----*@%%%%%%%%%%%%%%#*#####     
   #####**#%%%%%%%%%%%%%%%%%%%%:::::::::::::::::::::-++===----@@@@@%*############%%%%%%%%%#:::::::::::::::::::::::::::::::+@%%%%%%%%%%%%%%#*######    
  #####***#%%%%%%%%%%%%%%%%%%%*:::::::::::::::::::::::-==---::%@@%%%**###########%%%%%%%%%#:::::::::::::::::::::::::::::::%@%%%%%%%%%%%%%@#*######    
  #####***#%%%%%%%%%%%%%%%%%%%*:::::::::::::::::::::::::::::::@@@%%%**#########*#%%%%%%%%%%::::::::::::::::::::::::::::::+@%%%%%%%%%%%%%%@#*#######   
 ######***#%%%%%%%%%%%%%%%%%%%#::::::::::::::::::::::::::::::=@@@%@#**#########*#%%%%%%%%%%#::::::::::::::::::::::::::::#@%%%%%%%%%%%%%%%%**#######   
 ######****%%%%%%%%%%%%%%%%%%%%-:::::::::::::::::::::::::::::%@@%%@**###########*%%%%%%%%%#%*:::::::::::::::::::::::::-%@%%%%%%%%%%%%%%%@#**########  
 ######***+%%%%%%%%%%%%%%%%%%%%#:::::::::::::::::::::::::::-%@@%%@%+*###########*#%%%%%%%%##%#=:::::::::::::::::::::-%%%%%%%%%%%%%%%%%%%%**#########  
#######***+*%%%%%%%%%%%%%%%%%%%%#:::::::::::::::::::::::::=%@@%@@@***###########**%%%%%%%%####%%*=:::::::::::::::-*%%%%%%%%%%%%%%%%%%%%@***#########  
#######****+#%%%%%%%%%%%%%%%%%%%%%=:::::::::::::::::::::-#@@%%%@@#+*#############**%%%%%%%%######%%%*=-------=*%%%%%%%%%%%%%%%%%%%%%%%@***########### 
######******+#%%%%%%%%%%%%%%%%%%%%%%*:::::::::::::::::-%@%%%%%%@#+**##############**%%%%%%%%%#######%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%***############ 
#####********+#%%%%%%%%%%%%%%%%%%%%%%%%#-::::::::::+%@%%%%%%%%@#+**###############**+%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%+**############# 
#####*********++%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@@*+**##################*+#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@*+**############## 
####***********++#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%+**#####################**+%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@*+**################ 
####*************+=#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%++**########################*+=#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%++**################## 
###****************+=#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%=+**############################*+=*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@#++**#################### 
*#*******************+=+%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%+=+**################################**+=*#%%%%%%%%%%%%%%%%%%%%%%%%*+++**###################### 
#**********************++=+#%%%%%%%%%%%%%%%%%%%%%%#+=++**#####################################**++=+*##%%%%%%%%%%%%#*+=++***######################### 
***************************++==+**###########*+-=+++***###########################################****+++++++++++++++*****+=----+###################  
 #******************************+++++++++++++++*****######################################################*********#####-:::::::::-#################  
 ##**************************************************##################################################################+:::=:::::::-################  
 ##***************************************************#####################################################################-:::-+:::*##############   
  ##****************************************************#################################################################+::::=####################   
  *#*********************************************************##########################################################=:::::*####################    
   *##************************************************************##################################################+::::::*#####################     
    ##***************************************************************############################################*-:::::=########################     
     ##*******************************************************************####################################+-:::::=*#########################      
      ##********************++*****************************************************#######################*=::::::=############################       
       ##*******************+-::-=+*****************************************************##############*-::::::-*##############################        
        ##********************+=-::::-=+**************************************************#######*-::::::::+#################################         
         ##***********************+=-::::::=+*****************************************######+:::::::::-#####****############################          
          ##**************************+=-::::::::-=+**************************######*+-:::::::::::+*##***********##########################           
           ####***************************+=-:::::::::::::::::--------------::::::::::::::::=+*##*****************#######################             
             ###********************************+=-::::::::::::::::::::::::::::::::::=+****************************#####################              
              ####***************************************++++++===========+++++*************************************##################                
                ####************************************************************************************************#################                 
                  ####*************************************************************************************************############                   
                   #####************************************************************************************************#########                     
                      ####***********************************************************************************************######                       
                        ###**********************************************************************************************####                         
                          ####*****************************************************************************************####                           
                             ######**********************************************************************************###                              
                                #######***************************************************************************###                                 
                                   ########********************************************************************##*                                    
                                       #######**************************************************************##                                        
                                           #########***************************************************#**                                            
                                                ###########***************************************##*                                                 
                                                      ###############*************###########*                                                        
                                                                  ####***********#                                                                    ]]
		Services.RunService:SetRobloxGuiFocused(true)
		Services.Debris:AddItem(TextBox, 4)
		task.wait(4)
		Services.RunService:SetRobloxGuiFocused(false)
	end
})