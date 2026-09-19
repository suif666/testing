--[[
    坐标传送（独立版）by suif
    功能：
      1. 段落显示玩家坐标（X/Y/Z 各保留两位小数）
      2. 「实时刷新坐标」开关，默认关闭
         —— 关闭时显示区冻结，复制/保存取的仍是显示区那个值（所见即所得）
      3. 复制当前坐标 / 保存当前坐标 / 输入框自定义名称
         —— 名称留空自动命名：坐标01、坐标02、坐标03……
            编号填补空缺（删了坐标02，下一个还是坐标02）
      4. 可折叠的「已保存坐标」分组：刷新列表 + 每条坐标带「传送」「删除」
         —— 每条会显示是在哪个游戏保存的；子服务器里显示的是【主游戏名】，
            并额外标注实际地点（子服务器名）。其他游戏保存的坐标会标 ⚠其他游戏
         —— 英文游戏名自动翻成中文（离线词典即时翻译 + 联网翻译并缓存）
    依赖：WindUI-Boreal
      - 优先复用主脚本已加载的 getgenv().WindUI
      - 没有则自己从 GitHub 拉取（可单独执行）
    核心逻辑导出在 getgenv().CoordTP，方便以后并入主脚本
]]

-- ==================== 加载 WindUI ====================
local WindUI = getgenv().WindUI
if not WindUI then
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/suif666/suif/refs/heads/main/WindUI-Boreal.lua"))()
    end)
    if ok and res then
        WindUI = res
        getgenv().WindUI = WindUI
    else
        warn("[坐标传送] WindUI 加载失败：" .. tostring(res))
        return
    end
end

-- ==================== 服务与玩家 ====================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local setClipboard = setclipboard or toclipboard
    or (syn and syn.setclipboard)
    or (getgenv and getgenv().setclipboard)

-- ==================== 存储 ====================
local SAVE_FILE = "SutureCoordTP.json"

local function loadSavesFromFile()
    local ok, data = pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            local raw = readfile(SAVE_FILE)
            if raw and raw ~= "" then
                return HttpService:JSONDecode(raw)
            end
        end
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function saveSavesToFile(list)
    pcall(function()
        if writefile then
            writefile(SAVE_FILE, HttpService:JSONEncode(list))
        end
    end)
end

-- 已保存坐标列表：{ {name="坐标01", x=, y=, z=}, ... }
local Saves = getgenv().SutureCoordSaves
if type(Saves) ~= "table" then
    Saves = loadSavesFromFile() or {}
    getgenv().SutureCoordSaves = Saves
end

-- ==================== 游戏信息（主游戏名 / 子服务器识别） ====================
-- 关键点：同一个「宇宙(universe)」下的子服务器其实是不同的 place，
-- 它们的 game.GameId 完全相同，只有 game.PlaceId 不同。
-- 所以用 GameId 查询拿到的是主游戏名（网站上那个体验名）——
-- 即使在子服务器里也能拿到主服务器的名字。
-- 而 PlaceId 查到的才是「子服务器自己的名字」（其他脚本普遍这么写，所以会串名）。
local MarketplaceService = game:GetService("MarketplaceService")

local GameInfo = getgenv().SutureGameInfo or {}
GameInfo.gameId = game.GameId                                   -- 宇宙 ID（子服务器共用）
GameInfo.placeId = game.PlaceId                                 -- 当前地点 ID（每个子服务器不同）
GameInfo.jobId = game.JobId                                     -- 当前服务器实例
GameInfo.name = GameInfo.name or nil                            -- 主游戏名
GameInfo.placeName = GameInfo.placeName or nil                  -- 当前地点名（子服务器名）
GameInfo.rootPlaceId = GameInfo.rootPlaceId or nil              -- 主地点 ID
GameInfo.isSubPlace = GameInfo.isSubPlace or false              -- 当前是否在子服务器里
GameInfo.resolved = GameInfo.resolved or false
getgenv().SutureGameInfo = GameInfo

local onGameInfoReady = nil   -- 名称解析完成后的回调（UI 建好后赋值）

local function resolveGameInfo()
    task.spawn(function()
        -- 1) 用宇宙 ID 查主游戏名（子服务器与主服务器共用同一个 GameId）
        if GameInfo.gameId and GameInfo.gameId > 0 then
            -- 1a) 官方 games 接口（最可靠，返回的就是网站上那个体验名）
            local okApi, apiName, apiRoot = pcall(function()
                local url = "https://games.roblox.com/v1/games?universeIds="
                    .. tostring(GameInfo.gameId)
                local body = game:HttpGet(url)
                if type(body) ~= "string" or body == "" then return nil end
                local data = HttpService:JSONDecode(body)
                local first = data and data.data and data.data[1]
                if first then
                    return first.name, first.rootPlaceId
                end
                return nil
            end)
            if okApi and type(apiName) == "string" and apiName ~= "" then
                GameInfo.name = apiName
                if type(apiRoot) == "number" and apiRoot > 0 then
                    GameInfo.rootPlaceId = apiRoot
                end
            end

            -- 1b) 接口不通就退回 GetProductInfo
            if not GameInfo.name or GameInfo.name == "" then
                local ok, info = pcall(function()
                    return MarketplaceService:GetProductInfo(GameInfo.gameId, Enum.InfoType.Game)
                end)
                if ok and type(info) == "table" and type(info.Name) == "string"
                    and info.Name ~= "" then
                    GameInfo.name = info.Name
                    if type(info.RootPlaceId) == "number" and info.RootPlaceId > 0 then
                        GameInfo.rootPlaceId = info.RootPlaceId
                    end
                end
            end
        end

        -- 2) 用地点 ID 查当前地点名（在子服务器里得到的就是子服务器名）
        local ok2, info2 = pcall(function()
            return MarketplaceService:GetProductInfo(GameInfo.placeId)
        end)
        if ok2 and type(info2) == "table" then
            GameInfo.placeName = info2.Name
        end

        -- 3) 兜底：查不到就用 Studio 里的名字
        if not GameInfo.name or GameInfo.name == "" then
            GameInfo.name = game.Name
        end
        if not GameInfo.placeName or GameInfo.placeName == "" then
            GameInfo.placeName = game.Name
        end

        -- 当前地点不是主地点 → 说明现在就在子服务器里
        GameInfo.isSubPlace = (GameInfo.rootPlaceId ~= nil
            and GameInfo.rootPlaceId > 0
            and GameInfo.rootPlaceId ~= GameInfo.placeId)
        GameInfo.resolved = true

        -- 补全历史记录里缺名字的条目（只补同一游戏的）
        local changed = false
        for _, e in ipairs(Saves) do
            if e.gameId == GameInfo.gameId then
                if not e.gameName or e.gameName == "" then
                    e.gameName = GameInfo.name
                    changed = true
                end
                if not e.placeName or e.placeName == "" then
                    e.placeName = GameInfo.placeName
                    changed = true
                end
            end
        end
        if changed then
            saveSavesToFile(Saves)
        end

        if onGameInfoReady then
            pcall(onGameInfoReady)
        end
    end)
end

-- ==================== 游戏名中文化 ====================
-- API 返回的是开发者填的原文（英文游戏就是英文名）。
-- 三层处理：常用游戏精确表 → 本地词级词典（离线、瞬间）→ 联网翻译（结果缓存）
local NAME_CACHE_FILE = "SutureGameNameCache.json"
local AutoTranslate = true

local NameCache = getgenv().SutureGameNameCache
if type(NameCache) ~= "table" then
    local ok, data = pcall(function()
        if readfile and isfile and isfile(NAME_CACHE_FILE) then
            local raw = readfile(NAME_CACHE_FILE)
            if raw and raw ~= "" then
                return HttpService:JSONDecode(raw)
            end
        end
    end)
    NameCache = (ok and type(data) == "table") and data or {}
    getgenv().SutureGameNameCache = NameCache
end

local function saveNameCache()
    pcall(function()
        if writefile then
            writefile(NAME_CACHE_FILE, HttpService:JSONEncode(NameCache))
        end
    end)
end

-- 是否已经包含中文（含中文就不用翻译）
local function hasCJK(s)
    s = tostring(s or "")
    local ok, res = pcall(function()
        for _, cp in utf8.codes(s) do
            if cp >= 0x4E00 and cp <= 0x9FFF then
                return true
            end
        end
        return false
    end)
    if ok then return res end
    return s:find("[\228-\233]") ~= nil
end

-- 常用游戏精确对照（热门游戏的中文名）
local ExactDict = {
    ["blox fruits"] = "海盗果实",
    ["adopt me!"] = "领养我",
    ["adopt me"] = "领养我",
    ["tower defense simulator"] = "塔防模拟器",
    ["natural disaster survival"] = "自然灾害生存",
    ["murder mystery 2"] = "谋杀之谜2",
    ["jailbreak"] = "越狱",
    ["arsenal"] = "军火库",
    ["piggy"] = "小猪",
    ["doors"] = "门",
    ["brookhaven"] = "布鲁克黑文",
    ["brookhaven rp"] = "布鲁克黑文角色扮演",
    ["meepcity"] = "米普城",
    ["work at a pizza place"] = "披萨店打工",
    ["royale high"] = "皇家高中",
    ["da hood"] = "达胡德",
    ["welcome to bloxburg"] = "欢迎来到方块堡",
    ["bloxburg"] = "方块堡",
    ["the strongest battlegrounds"] = "最强战场",
    ["strongest battlegrounds"] = "最强战场",
    ["combat warriors"] = "战斗勇士",
    ["pet simulator x"] = "宠物模拟器X",
    ["all star tower defense"] = "全明星塔防",
    ["anime fighting simulator"] = "动漫格斗模拟器",
    ["shindo life"] = "新道人生",
    ["demon slayer"] = "鬼灭之刃",
    ["slayer awakening"] = "鬼灭觉醒",
    ["survive the killers"] = "逃离杀手",
    ["survival the killers"] = "逃离杀手",
    ["evade"] = "躲避",
    ["flee the facility"] = "逃离设施",
    ["tower of hell"] = "地狱塔",
    ["speed run 4"] = "速通4",
    ["epic minigames"] = "史诗小游戏",
    ["flood escape 2"] = "洪水逃生2",
    ["horrific housing"] = "恐怖房屋",
    ["pls donate"] = "请打赏",
    ["grow a garden"] = "种花园",
    ["dress to impress"] = "惊艳穿搭",
    ["steal a brainrot"] = "偷取脑腐",
    ["bee swarm simulator"] = "养蜂模拟器",
    ["mega easy obby"] = "超简单跑酷",
    ["total roblox drama"] = "罗布乐思大乱斗",
    ["creatures of sonaria"] = "索纳里亚生物",
    ["blox fruit"] = "海盗果实",
    ["mm2"] = "谋杀之谜2",
}

-- 短语词典（先长后短匹配，所以「tower defense」不会被拆成两个词）
local PhraseDict = {
    ["tower defense"] = "塔防",
    ["tower defence"] = "塔防",
    ["battle royale"] = "大逃杀",
    ["pet simulator"] = "宠物模拟器",
    ["natural disaster"] = "自然灾害",
    ["racing game"] = "竞速游戏",
    ["role play"] = "角色扮演",
    ["open world"] = "开放世界",
    ["first person"] = "第一人称",
    ["third person"] = "第三人称",
}

-- 单词词典（离线即时翻译，覆盖面尽量广）
local WordDict = {
    ["the"] = "", ["a"] = "", ["an"] = "", ["of"] = "", ["and"] = "与",
    ["simulator"] = "模拟器", ["sim"] = "模拟", ["tycoon"] = "大亨",
    ["tower"] = "塔", ["defense"] = "防御", ["defence"] = "防御",
    ["survival"] = "生存", ["survive"] = "生存", ["survivor"] = "幸存者",
    ["blox"] = "方块", ["block"] = "方块", ["blocks"] = "方块", ["cube"] = "方块",
    ["fruit"] = "果实", ["fruits"] = "果实", ["pet"] = "宠物", ["pets"] = "宠物",
    ["obby"] = "跑酷", ["parkour"] = "跑酷", ["adventure"] = "冒险",
    ["world"] = "世界", ["island"] = "岛屿", ["islands"] = "岛屿",
    ["city"] = "城市", ["town"] = "小镇", ["village"] = "村庄",
    ["battle"] = "战斗", ["fight"] = "格斗", ["fighting"] = "格斗",
    ["war"] = "战争", ["wars"] = "战争", ["arena"] = "竞技场",
    ["legend"] = "传奇", ["legends"] = "传奇", ["hero"] = "英雄", ["heroes"] = "英雄",
    ["dragon"] = "龙", ["dragons"] = "龙", ["ninja"] = "忍者",
    ["pirate"] = "海盗", ["pirates"] = "海盗",
    ["zombie"] = "僵尸", ["zombies"] = "僵尸",
    ["horror"] = "恐怖", ["scary"] = "恐怖", ["haunted"] = "闹鬼",
    ["escape"] = "逃脱", ["runner"] = "跑者", ["run"] = "跑",
    ["clicker"] = "点击器", ["idle"] = "放置", ["incremental"] = "放置",
    ["sword"] = "剑", ["swords"] = "剑", ["gun"] = "枪", ["guns"] = "枪",
    ["anime"] = "动漫", ["story"] = "物语", ["project"] = "计划",
    ["new"] = "新", ["super"] = "超级", ["mega"] = "巨型",
    ["ultra"] = "究极", ["mini"] = "迷你", ["my"] = "我的", ["me"] = "我",
    ["attack"] = "攻击", ["attacks"] = "攻击", ["defend"] = "防御",
    ["titan"] = "巨人", ["titans"] = "巨人", ["giant"] = "巨人",
    ["king"] = "国王", ["kingdom"] = "王国", ["queen"] = "女王",
    ["school"] = "学校", ["prison"] = "监狱", ["life"] = "生活",
    ["roleplay"] = "角色扮演", ["rp"] = "角色扮演",
    ["fishing"] = "钓鱼", ["mining"] = "挖矿", ["farm"] = "农场",
    ["farming"] = "农场", ["restaurant"] = "餐厅", ["cafe"] = "咖啡馆",
    ["hotel"] = "酒店", ["hospital"] = "医院", ["airport"] = "机场",
    ["racing"] = "竞速", ["race"] = "竞速", ["car"] = "汽车", ["cars"] = "汽车",
    ["speed"] = "速度", ["driving"] = "驾驶", ["train"] = "火车",
    ["plane"] = "飞机", ["boat"] = "船", ["dog"] = "狗", ["cat"] = "猫",
    ["animal"] = "动物", ["football"] = "足球", ["soccer"] = "足球",
    ["basketball"] = "篮球", ["boxing"] = "拳击", ["strength"] = "力量",
    ["power"] = "力量", ["magic"] = "魔法", ["wizard"] = "巫师",
    ["demon"] = "恶魔", ["devil"] = "恶魔", ["angel"] = "天使",
    ["god"] = "神", ["gods"] = "神", ["slayer"] = "杀手",
    ["killer"] = "杀手", ["killers"] = "杀手", ["murder"] = "谋杀",
    ["mystery"] = "之谜", ["backrooms"] = "后室", ["apocalypse"] = "末日",
    ["disaster"] = "灾害", ["disasters"] = "灾害", ["natural"] = "自然",
    ["earthquake"] = "地震", ["tornado"] = "龙卷风", ["volcano"] = "火山",
    ["flood"] = "洪水", ["fire"] = "火焰", ["water"] = "水",
    ["earth"] = "大地", ["wind"] = "风", ["ice"] = "冰", ["snow"] = "雪",
    ["winter"] = "冬季", ["summer"] = "夏季", ["night"] = "夜晚",
    ["day"] = "白天", ["dark"] = "黑暗", ["light"] = "光明",
    ["shadow"] = "暗影", ["blood"] = "血", ["death"] = "死亡",
    ["soul"] = "灵魂", ["spirit"] = "灵魂", ["ghost"] = "幽灵",
    ["mansion"] = "豪宅", ["house"] = "房子", ["home"] = "家",
    ["base"] = "基地", ["online"] = "线上", ["multiplayer"] = "多人",
    ["official"] = "官方", ["beta"] = "测试版", ["test"] = "测试",
    ["update"] = "更新", ["remake"] = "重制", ["classic"] = "经典",
    ["original"] = "原版", ["old"] = "旧", ["first"] = "第一",
    ["one"] = "一", ["two"] = "二", ["three"] = "三",
    ["pizza"] = "披萨", ["food"] = "食物", ["cooking"] = "烹饪",
    ["bakery"] = "烘焙", ["shop"] = "商店", ["store"] = "商店",
    ["dress"] = "穿搭", ["impress"] = "惊艳", ["grow"] = "种植",
    ["garden"] = "花园", ["bee"] = "蜜蜂", ["swarm"] = "蜂群",
    ["steal"] = "偷取", ["brainrot"] = "脑腐", ["creatures"] = "生物",
    ["total"] = "大乱斗", ["drama"] = "乱斗", ["easy"] = "简单",
    ["hard"] = "困难", ["hell"] = "地狱", ["facility"] = "设施",
}

-- 本地词级翻译
local function dictTranslate(name)
    local s = tostring(name or "")
    if s == "" or hasCJK(s) then return s end

    local low = s:lower()
    local exact = ExactDict[low]
    if exact then return exact end

    -- 先做短语替换（长的优先，避免被短词拆散）
    local phrases = {}
    for k in pairs(PhraseDict) do
        table.insert(phrases, k)
    end
    table.sort(phrases, function(a, b) return #a > #b end)

    local work = " " .. low .. " "
    for _, k in ipairs(phrases) do
        work = work:gsub(k, " " .. PhraseDict[k] .. " ")
    end

    -- 剩下的英文单词逐个查词
    local out = {}
    for token in work:gmatch("%S+") do
        if token:find("[\128-\255]") then
            table.insert(out, token)                       -- 已经是中文
        else
            local w = token:gsub("^[^%w']+", ""):gsub("[^%w']+$", "")
            if w ~= "" then
                local trans = WordDict[w]
                if trans == nil then
                    trans = w                               -- 词典没有就保留原文
                end
                if trans ~= "" then
                    table.insert(out, trans)
                end
            end
        end
    end

    local result = table.concat(out)
    if result == "" then return s end
    return result
end

-- 联网翻译（Google → MyMemory 兜底）
local function requestTranslation(text)
    local ok, res = pcall(function()
        local url = "https://translate.googleapis.com/translate_a/single"
            .. "?client=gtx&sl=auto&tl=zh-CN&dt=t&q=" .. HttpService:UrlEncode(text)
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and res ~= "" then
        local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
        if ok2 and type(data) == "table" and data[1] and data[1][1] then
            local seg = data[1][1][1]
            if type(seg) == "string" and seg ~= "" then
                return seg
            end
        end
    end

    local ok3, res3 = pcall(function()
        local url = "https://api.mymemory.translated.net/get?q="
            .. HttpService:UrlEncode(text) .. "&langpair=en|zh-CN"
        return game:HttpGet(url)
    end)
    if ok3 and type(res3) == "string" and res3 ~= "" then
        local ok4, data2 = pcall(function() return HttpService:JSONDecode(res3) end)
        if ok4 and type(data2) == "table" and data2.responseData then
            local seg = data2.responseData.translatedText
            if type(seg) == "string" and seg ~= "" then
                return seg
            end
        end
    end
    return nil
end

local translating = {}     -- 正在翻译的名字（防重复请求）
local failedNames = {}     -- 翻译失败的名字（不再反复重试）
local onNameTranslated = nil

-- 把一个名字转成中文显示：有缓存用缓存，没缓存先用词典顶着，同时后台联网翻译
local function zhForName(raw)
    raw = tostring(raw or "")
    if raw == "" then return raw end
    if hasCJK(raw) then return raw end                       -- 本来就是中文

    local cached = NameCache[raw]
    if type(cached) == "string" and cached ~= "" then
        return cached
    end

    if AutoTranslate and not translating[raw] and not failedNames[raw] then
        translating[raw] = true
        task.spawn(function()
            local result = requestTranslation(raw)
            translating[raw] = nil
            if result and result ~= "" and result ~= raw then
                NameCache[raw] = result
                saveNameCache()
                if onNameTranslated then
                    pcall(onNameTranslated)
                end
            else
                failedNames[raw] = true
            end
        end)
    end

    return dictTranslate(raw)                                -- 先给个离线中文名
end

-- 生成「游戏：xxx」这一行的文字
-- 不是当前游戏保存的坐标 → 游戏名标红 + [非此游戏]
local RICH_RED = "rgb(255, 85, 85)"

-- 富文本转义（游戏名里可能有 & < >，不转义会破坏富文本）
local function escRich(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    return s
end

local function gameLabelFor(e)
    local sameGame = (e.gameId == nil) or (e.gameId == GameInfo.gameId)

    local gname = e.gameName
    if (not gname or gname == "") and sameGame then
        gname = GameInfo.name
    end
    if not gname or gname == "" then
        gname = e.placeName
    end
    if not gname or gname == "" then
        if e.gameId == nil then
            gname = "未知（旧记录）"
        elseif sameGame and not GameInfo.resolved then
            gname = "识别中…"
        else
            gname = "未知游戏"
        end
    end

    local tags = {}

    -- 子服务器标记（只有同一游戏才能用当前宇宙的 rootPlaceId 判断）
    local isSub = false
    if sameGame and e.placeId then
        if GameInfo.rootPlaceId and GameInfo.rootPlaceId > 0 then
            isSub = (e.placeId ~= GameInfo.rootPlaceId)
        elseif GameInfo.placeId and e.placeId ~= GameInfo.placeId then
            isSub = true
        end
    end
    if isSub then
        if e.placeName and e.placeName ~= "" and e.placeName ~= gname then
            table.insert(tags, "子服务器：" .. zhForName(e.placeName))
        else
            table.insert(tags, "子服务器")
        end
    end

    local suffix = ""
    if #tags > 0 then
        suffix = "（" .. table.concat(tags, "，") .. "）"
    end

    -- 英文名转成中文显示：先给离线词典结果，联网翻译回来后自动刷新
    local shown = escRich(zhForName(gname))

    -- 不是当前游戏保存的坐标 → 游戏名红色 + [非此游戏]
    if not sameGame then
        return "游戏：<font color=\"" .. RICH_RED .. "\">" .. shown .. "</font>"
            .. " <font color=\"" .. RICH_RED .. "\">[非此游戏]</font>" .. suffix
    end

    return "游戏：" .. shown .. suffix
end

-- ==================== 工具函数 ====================
-- 这条坐标是不是「别的游戏」保存的（旧记录没有 gameId → 当成当前游戏）
local function isOtherGame(e)
    if not e or not e.gameId or not GameInfo.gameId then return false end
    return e.gameId ~= GameInfo.gameId
end

local function getPos()
    local char = lp.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then return root.Position end
    local ok, pivot = pcall(function() return char:GetPivot() end)
    if ok and pivot then return pivot.Position end
    return nil
end

local function fmtPos(p)
    if not p then return "X: --, Y: --, Z: --" end
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", p.X, p.Y, p.Z)
end

local function fmtEntry(e)
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", e.x or 0, e.y or 0, e.z or 0)
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 自动命名：从 01 开始找第一个没被占用的编号（填补空缺）
-- 例：已有 坐标01、坐标03（02 被删了）→ 下一个是 坐标02
local function nextDefaultName()
    local used = {}
    for _, e in ipairs(Saves) do
        local n = tostring(e.name or ""):match("^坐标(%d+)$")
        if n then
            used[tonumber(n)] = true
        end
    end
    local i = 1
    while used[i] do
        i = i + 1
    end
    return string.format("坐标%02d", i)
end

local function notify(title, content, icon)
    pcall(function()
        WindUI:Notify({
            Title = tostring(title or "坐标传送"),
            Content = tostring(content or ""),
            Icon = icon or "map-pin",
            Duration = 3,
        })
    end)
end

-- 销毁元素（不同组件暴露的方法名不同，做兜底）
local function destroyElement(el)
    if not el then return end
    pcall(function()
        if type(el.Destroy) == "function" then
            el:Destroy()
        elseif el.ParagraphFrame then
            el.ParagraphFrame:Destroy()
        elseif el.ElementFrame then
            el.ElementFrame:Destroy()
        end
    end)
end

-- ==================== 核心功能 ====================
local Core = {}
Core.Saves = Saves
-- 外显坐标：显示区当前显示的数值。复制/保存都取它（所见即所得）
Core.displayedPos = nil

-- 传送
function Core.teleportTo(x, y, z)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not root then
        notify("传送失败", "角色不存在（可能正在重生）", "x")
        return false
    end
    local target = Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    local ok = pcall(function()
        char:PivotTo(CFrame.new(target))
    end)
    if not ok then
        ok = pcall(function()
            root.CFrame = CFrame.new(target)
        end)
    end
    if ok then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
        end)
        notify("传送成功", fmtPos(target), "check")
        return true
    end
    notify("传送失败", "该执行器不支持 PivotTo / CFrame 写入", "x")
    return false
end

-- 保存坐标（取外显数值：显示区显示什么就存什么）
function Core.saveCurrent(customName)
    local p = Core.displayedPos
    if not p then
        notify("保存失败", "显示区还没有坐标，请先点「刷新一次」", "x")
        return false
    end
    local name = trim(customName)
    if name == "" then
        name = nextDefaultName()
    end
    table.insert(Saves, {
        name = name,
        x = tonumber(string.format("%.2f", p.X)),
        y = tonumber(string.format("%.2f", p.Y)),
        z = tonumber(string.format("%.2f", p.Z)),
        -- 记录是在哪个游戏/哪个子服务器保存的
        gameId = GameInfo.gameId,
        placeId = GameInfo.placeId,
        gameName = GameInfo.name,
        placeName = GameInfo.placeName,
        savedAt = os.time(),
    })
    saveSavesToFile(Saves)
    notify("已保存", name .. "  " .. fmtPos(p), "check")
    return true
end

-- 复制坐标（取外显数值：显示区显示什么就复制什么）
function Core.copyCurrent()
    local p = Core.displayedPos
    if not p then
        notify("复制失败", "显示区还没有坐标，请先点「刷新一次」", "x")
        return false
    end
    local text = fmtPos(p)
    if setClipboard then
        pcall(setClipboard, text)
        notify("已复制到剪贴板", text, "copy")
    else
        notify("复制失败", "当前执行器没有 setclipboard", "x")
    end
    return true
end

getgenv().CoordTP = Core

-- ==================== 创建窗口 ====================
local win = WindUI:CreateWindow({
    Title = "坐标传送",
    Icon = "map-pin",
    Author = "by suif",
    Folder = "CoordTP",
    Size = UDim2.fromOffset(480, 520),
    ToggleKey = Enum.KeyCode.RightShift,
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    HideSearchBar = true,
})

local tab = win:Tab({ Title = "坐标传送", Icon = "map-pin", Locked = false })

-- 元素创建保护：某个元素创建失败只 warn，不影响其他元素
local function safe(what, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[坐标传送] 创建「" .. tostring(what) .. "」失败：" .. tostring(err))
    end
    return ok
end

-- ==================== 分组1：当前坐标 ====================
local mainSec = tab:Section({ Title = "当前坐标", Icon = "crosshair", Opened = true })

local PLACEHOLDER_TEXT = "X: --, Y: --, Z: --"
local descLabel = nil
local warnedNoLabel = false
local LiveRefresh = false

-- 在整个界面树里找显示坐标的那个 TextLabel
-- （不依赖 WindUI 内部结构，用占位文本 / "X: 数字" 这种独有格式匹配）
local function findDescLabel()
    local roots = {}
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then table.insert(roots, pg) end
    pcall(function()
        table.insert(roots, game:GetService("CoreGui"))
    end)
    for _, root in ipairs(roots) do
        local ok, found = pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local t = d.Text or ""
                    if t == PLACEHOLDER_TEXT or t:match("^X: %-?%d") then
                        return d
                    end
                end
            end
        end)
        if ok and found then
            return found
        end
    end
    return nil
end

local function refreshDisplay()
    local p = getPos()
    if not p then
        -- 拿不到角色坐标（重生中/未加载）：外显保持原样，不清空
        if not descLabel then descLabel = findDescLabel() end
        if descLabel and descLabel.Parent and not Core.displayedPos then
            descLabel.Text = PLACEHOLDER_TEXT
        end
        return
    end
    -- 更新外显值（复制/保存都取它）
    Core.displayedPos = p
    local text = fmtPos(p)
    if not descLabel or not descLabel.Parent then
        descLabel = findDescLabel()
        if not descLabel and not warnedNoLabel then
            warnedNoLabel = true
            warn("[坐标传送] 未能定位坐标显示控件，请把这条报错发给我")
        end
    end
    if descLabel and descLabel.Parent then
        pcall(function()
            descLabel.Text = text
        end)
    end
end

safe("坐标显示段落", function()
    mainSec:Paragraph({
        Title = "玩家当前位置",
        Desc = PLACEHOLDER_TEXT,
    })
end)

safe("实时刷新开关", function()
    mainSec:Toggle({
        Title = "实时刷新坐标",
        Desc = "开启后持续刷新上方坐标；关闭时坐标冻结，复制/保存取的仍是显示区那个值",
        Type = "Checkbox",
        Value = false,
        Callback = function(state)
            LiveRefresh = state and true or false
            if LiveRefresh then
                refreshDisplay()
            end
        end,
    })
end)

safe("刷新一次按钮", function()
    mainSec:Button({
        Title = "刷新一次",
        Desc = "把显示区更新为当前实际坐标",
        Icon = "refresh-cw",
        Callback = function()
            refreshDisplay()
            notify("已刷新", fmtPos(Core.displayedPos), "check")
        end,
    })
end)

safe("复制坐标按钮", function()
    mainSec:Button({
        Title = "复制当前坐标",
        Desc = "复制显示区上的坐标（外显数值）",
        Icon = "copy",
        Callback = function()
            Core.copyCurrent()
        end,
    })
end)

-- 名称输入框（不接收返回值：WindUI 元素方法返回的是 __type 字符串）
local INPUT_PLACEHOLDER = "留空自动命名"
local lastInputText = ""

safe("名称输入框", function()
    mainSec:Input({
        Title = "坐标名称",
        Desc = "留空自动命名：坐标01、坐标02、坐标03……",
        Placeholder = INPUT_PLACEHOLDER,
        Callback = function(v)
            lastInputText = tostring(v or "")
        end,
    })
end)

-- 按 PlaceholderText 定位这个输入框的 TextBox
local function findNameBox()
    local roots = {}
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then table.insert(roots, pg) end
    pcall(function()
        table.insert(roots, game:GetService("CoreGui"))
    end)
    for _, root in ipairs(roots) do
        local ok, found = pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextBox") and d.PlaceholderText == INPUT_PLACEHOLDER then
                    return d
                end
            end
        end)
        if ok and found then
            return found
        end
    end
    return nil
end

local function readInputText()
    -- 优先直接读输入框（用户可能还没回车就点了保存）
    local box = findNameBox()
    if box and box.Text and box.Text ~= "" then
        return tostring(box.Text)
    end
    -- 兜底：用回调缓存的值
    return lastInputText
end

-- 前置声明，供上方按钮回调引用
local rebuildList

safe("保存坐标按钮", function()
    mainSec:Button({
        Title = "保存当前坐标",
        Desc = "保存显示区上的坐标（外显数值）到下方列表",
        Icon = "save",
        Callback = function()
            if Core.saveCurrent(readInputText()) then
                if rebuildList then rebuildList() end
            end
        end,
    })
end)

-- ==================== 分组2：已保存坐标（可折叠） ====================
local listSec = tab:Section({ Title = "已保存坐标", Icon = "folder", Opened = false })

local listElements = {}

-- 过滤非当前游戏坐标（开关一开，列表里只留当前游戏保存的坐标）
local FilterOtherGame = false

safe("翻译开关", function()
    listSec:Toggle({
        Title = "英文游戏名翻译成中文",
        Desc = "联网翻译一次并缓存；关掉就显示游戏原始名字",
        Type = "Checkbox",
        Value = true,
        Callback = function(state)
            AutoTranslate = state and true or false
            if rebuildList then rebuildList() end
        end,
    })
end)

safe("刷新列表按钮", function()
    listSec:Button({
        Title = "刷新列表",
        Desc = "重新加载保存的坐标列表",
        Icon = "refresh-cw",
        Callback = function()
            if rebuildList then rebuildList() end
            notify("列表已刷新", tostring(#Saves) .. " 个坐标", "check")
        end,
    })
end)

safe("过滤开关", function()
    listSec:Toggle({
        Title = "过滤非当前游戏坐标",
        Desc = "开启后隐藏所有非当前游戏保存的坐标，直到关闭这个开关",
        Type = "Checkbox",
        Value = false,
        Callback = function(state)
            FilterOtherGame = state and true or false
            if rebuildList then rebuildList() end
            if FilterOtherGame then
                notify("已开启过滤", "只显示当前游戏保存的坐标", "filter")
            else
                notify("已关闭过滤", "显示全部坐标", "filter")
            end
        end,
    })
end)

rebuildList = function()
    -- 清掉旧条目
    for _, el in ipairs(listElements) do
        destroyElement(el)
    end
    listElements = {}

    if #Saves == 0 then
        local empty
        safe("空列表提示", function()
            empty = listSec:Paragraph({
                Title = "暂无保存的坐标",
                Desc = "在上方点「保存当前坐标」后，这里会显示",
            })
        end)
        if empty then
            table.insert(listElements, empty)
        end
        return
    end

    local hiddenCount = 0

    for i, entry in ipairs(Saves) do
        local item
        local idx = i
        -- 过滤：开启后跳过所有非当前游戏的坐标
        if FilterOtherGame and isOtherGame(entry) then
            hiddenCount = hiddenCount + 1
        else
        safe("列表条目", function()
            item = listSec:Paragraph({
                Title = tostring(entry.name or ("坐标" .. idx)),
                Desc = fmtEntry(entry) .. "\n" .. gameLabelFor(entry),
                Buttons = {
                    {
                        Title = "传送",
                        Icon = "target",
                        Variant = "Primary",
                        Callback = function()
                            -- 其他游戏保存的坐标，传送前提醒一下
                            if isOtherGame(entry) then
                                notify("注意",
                                    "该坐标是在「" .. zhForName(entry.gameName or entry.placeName or "其他游戏")
                                    .. "」保存的，位置可能对不上",
                                    "triangle-alert")
                            end
                            Core.teleportTo(entry.x, entry.y, entry.z)
                        end,
                    },
                    {
                        Title = "删除",
                        Icon = "trash",
                        Callback = function()
                            table.remove(Saves, idx)
                            saveSavesToFile(Saves)
                            notify("已删除", tostring(entry.name or ""), "x")
                            rebuildList()
                        end,
                    },
                },
            })
        end)
        if item then
            -- 打开富文本，才能让「非此游戏」的游戏名显示成红色
            pcall(function()
                local ui = item.ParagraphFrame and item.ParagraphFrame.UIElements
                local d = ui and ui.Desc
                if d and d:IsA("TextLabel") then d.RichText = true end
            end)
            table.insert(listElements, item)
        end
        end   -- /过滤判断
    end

    -- 过滤提示：告诉用户被藏起来了多少条
    if hiddenCount > 0 then
        local tip
        safe("过滤提示", function()
            tip = listSec:Paragraph({
                Title = string.format("已隐藏 %d 个非当前游戏的坐标", hiddenCount),
                Desc = "关掉上方「过滤非当前游戏坐标」开关即可重新显示",
            })
        end)
        if tip then
            table.insert(listElements, tip)
        end
    elseif FilterOtherGame and #Saves > 0 then
        local tip
        safe("过滤提示_无", function()
            tip = listSec:Paragraph({
                Title = "过滤已开启",
                Desc = "当前保存的坐标都属于这个游戏",
            })
        end)
        if tip then
            table.insert(listElements, tip)
        end
    end

    -- 让分组重新排版（不同版本方法名不同，做兜底）
    pcall(function()
        if type(listSec.Refresh) == "function" then
            listSec:Refresh()
        elseif type(listSec.Update) == "function" then
            listSec:Update()
        end
    end)
end

-- ==================== 初始化 ====================
-- 游戏名解析完成后：补上列表里的游戏名 + 顺手刷新一次显示
onGameInfoReady = function()
    rebuildList()
    refreshDisplay()
end

-- 联网翻译拿到结果后：刷新列表把中文名显示出来
onNameTranslated = function()
    rebuildList()
end

rebuildList()
refreshDisplay()
resolveGameInfo()   -- 异步查询主游戏名（不阻塞界面）

-- 实时刷新循环（默认关闭，开启后每 0.1 秒刷新）
task.spawn(function()
    while true do
        task.wait(0.1)
        if LiveRefresh then
            refreshDisplay()
        end
    end
end)

notify("坐标传送已加载", "右键 Shift 开关界面", "map-pin")
