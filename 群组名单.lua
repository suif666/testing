--[[
    群组名单（后台版）by suif
    ------------------------------------------------------------
    思路：先让后台（Cloudflare Worker）把群组成员爬全，存进 KV；
          脚本这边只读后台，不在本地爬 —— 手机上不卡、不用一直挂着。

    配套后台：群组爬取Worker.js（部署到 Cloudflare Workers，绑定 KV 变量名 GROUPS）

    用法：
      1. 把 Worker 部署好，地址填到下面的「后台地址」
      2. 填「群组 ID」→ 点「测试后台」（会告诉你后台能不能直连 Roblox）
      3. 点「开始爬取」（会分批爬，爬完自动停；后台加了定时任务的话，点了就不用守着）
      4. 点「拉取名单」把名单拿到本地 → 可复制前 100 条 / 导出 CSV 到执行器文件夹

    兜底：如果后台直连 Roblox 被 403（Roblox.com is not available），
          点「本机爬取并上传」——由你的手机直接请求 Roblox 接口，
          分批把结果推到后台，之后照常从后台读。

    依赖：WindUI-Boreal（优先复用主脚本的 getgenv().WindUI）
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
        warn("[群组名单] WindUI 加载失败：" .. tostring(res))
        return
    end
end

-- ==================== 服务 ====================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local API = ""          -- 后台地址，例如 https://group-scraper.xxx.workers.dev
local GROUP = ""        -- 群组 ID
local KEY = ""          -- 后台设了 KEY 环境变量才需要
local Members = {}      -- 拉下来的名单
local Crawling = false
local PhoneCrawling = false

local STATUS_PLACEHOLDER = "群组名单状态：还没开始"
local statusLabel = nil

local function notify(title, content, icon, duration)
    pcall(function()
        WindUI:Notify({
            Title = tostring(title or "群组名单"),
            Content = tostring(content or ""),
            Icon = icon or "users",
            Image = icon or "users",   -- 库内部用的是 Image 字段，两个都带上保险
            Duration = duration or 4,
        })
    end)
end

-- 更新状态区文字（WindUI 的 Paragraph 没有 Set 方法，按占位文本找到那个 TextLabel 改）
local function findStatusLabel()
    if statusLabel and statusLabel.Parent then return statusLabel end
    local roots = {}
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then table.insert(roots, pg) end
    pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
    for _, root in ipairs(roots) do
        local ok, found = pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") and (d.Text == STATUS_PLACEHOLDER or tostring(d.Text):find("群组名单状态", 1, true)) then
                    return d
                end
            end
        end)
        if ok and found then
            statusLabel = found
            return found
        end
    end
    return nil
end

local function setStatus(text)
    local lbl = findStatusLabel()
    if lbl then
        pcall(function() lbl.Text = text end)
    else
        print("[群组名单] " .. tostring(text))
    end
end

-- ==================== 后台请求 ====================
local function buildUrl(path, params)
    local base = tostring(API or ""):gsub("/+$", "")
    local url = base .. path
    local parts = {}
    for k, v in pairs(params or {}) do
        if v ~= nil and tostring(v) ~= "" then
            parts[#parts + 1] = tostring(k) .. "=" .. HttpService:UrlEncode(tostring(v))
        end
    end
    if #parts > 0 then
        url = url .. "?" .. table.concat(parts, "&")
    end
    return url
end

local function apiGet(path, params)
    if API == "" then return nil, "还没填后台地址" end
    local p = {}
    for k, v in pairs(params or {}) do p[k] = v end
    if KEY ~= "" then p.key = KEY end
    local url = buildUrl(path, p)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then return nil, "请求失败：" .. tostring(res):sub(1, 120) end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 then return nil, "返回不是 JSON：" .. tostring(res):sub(1, 120) end
    return data
end

local function shortId()
    return tostring(GROUP or ""):gsub("[^0-9]", "")
end

-- ==================== 功能 ====================
local function testBackend()
    task.spawn(function()
        if shortId() == "" then
            notify("缺少群组ID", "先在上面填群组 ID", "x")
            return
        end
        setStatus("测试中…")
        local res, err = apiGet("/test", { groupId = shortId() })
        if not res then
            setStatus("测试失败：" .. tostring(err))
            notify("测试失败", tostring(err), "x", 6)
            return
        end
        if res.ok then
            setStatus("后台可以直连 Roblox ✅\n群组：" .. tostring(res.groupName) ..
                "\n总人数：" .. tostring(res.memberCount) ..
                "\n→ 直接点「开始爬取」就行")
            notify("后台正常", "群组：" .. tostring(res.groupName) .. "（" .. tostring(res.memberCount) .. " 人）", "check", 5)
        else
            setStatus("后台连不上 Roblox ❌（HTTP " .. tostring(res.rbxStatus) .. "）\n" ..
                tostring(res.hint or "") .. "\n→ 点「本机爬取并上传」")
            notify("后台被墙", "后台直连 Roblox 返回 " .. tostring(res.rbxStatus) .. "，用本机爬取兜底", "x", 8)
        end
    end)
end

local function refreshStatus()
    task.spawn(function()
        local res, err = apiGet("/status", { groupId = shortId() })
        if not res then
            setStatus("查进度失败：" .. tostring(err))
            return
        end
        if not res.ok then
            setStatus("后台里还没有这个群的数据：" .. tostring(res.error or ""))
            return
        end
        local m = res.meta
        local pct = (m.memberCount and m.memberCount > 0) and math.floor(m.scraped / m.memberCount * 100) or 0
        setStatus("群组：" .. tostring(m.name) .. "（ID " .. tostring(m.groupId) .. "）\n" ..
            "已爬：" .. tostring(m.scraped) .. " / " .. tostring(m.memberCount or "?") .. "（" .. pct .. "%）\n" ..
            "分片：" .. tostring(m.chunks) .. "    状态：" .. tostring(m.status) ..
            (m.lastError and ("\n上次出错：" .. tostring(m.lastError)) or ""))
    end)
end

local function crawlLoop()
    task.spawn(function()
        if Crawling then
            notify("正在爬", "已经在爬了，等它跑完（或改状态看进度）", "info")
            return
        end
        if shortId() == "" then
            notify("缺少群组ID", "先在上面填群组 ID", "x")
            return
        end
        Crawling = true
        local rounds = 0
        while Crawling do
            rounds = rounds + 1
            local res, err = apiGet("/crawl", { groupId = shortId(), pages = 20 })
            if not res then
                setStatus("爬取出错：" .. tostring(err))
                break
            end
            if res.rateLimited then
                setStatus("被 Roblox 限流（429），等 5 秒继续…（已爬 " .. tostring(res.meta and res.meta.scraped) .. "）")
                task.wait(5)
            elseif not res.ok then
                setStatus("爬取出错：HTTP " .. tostring(res.rbxStatus) .. "\n" ..
                    tostring(res.hint or res.error or "") .. "\n（若提示 IP 被拦，改用「本机爬取并上传」）")
                notify("爬取出错", tostring(res.hint or res.error or ("HTTP " .. tostring(res.rbxStatus))), "x", 8)
                break
            else
                local m = res.meta or {}
                local pct = (m.memberCount and m.memberCount > 0) and math.floor((m.scraped or 0) / m.memberCount * 100) or 0
                setStatus("爬取中（第 " .. rounds .. " 批）\n已爬：" .. tostring(m.scraped) .. " / " .. tostring(m.memberCount or "?") ..
                    "（" .. pct .. "%）\n分片：" .. tostring(m.chunks))
                if res.done then
                    setStatus("✅ 爬完了\n群组：" .. tostring(m.name) .. "\n共 " .. tostring(m.scraped) .. " 人 / 总分片 " .. tostring(m.chunks) ..
                        "\n→ 点「拉取名单」")
                    notify("爬取完成", "共 " .. tostring(m.scraped) .. " 人，点「拉取名单」", "check", 6)
                    break
                end
            end
            task.wait(0.5)
        end
        Crawling = false
    end)
end

local function fetchMembers(maxCount)
    task.spawn(function()
        maxCount = maxCount or 1000
        if shortId() == "" then
            notify("缺少群组ID", "先填群组 ID", "x")
            return
        end
        Members = {}
        local offset, limit = 0, 500
        local total = nil
        while #Members < maxCount do
            local res, err = apiGet("/users", { groupId = shortId(), offset = offset, limit = limit })
            if not res then
                setStatus("拉取失败：" .. tostring(err))
                return
            end
            if not res.ok then
                setStatus("拉取失败：" .. tostring(res.error or ""))
                return
            end
            total = res.memberCount or res.scrapedTotal
            for _, row in ipairs(res.users or {}) do
                Members[#Members + 1] = row
            end
            offset = offset + (res.returned or 0)
            setStatus("拉取中…已拿到 " .. #Members .. " / " .. tostring(res.scrapedTotal or "?"))
            if (res.returned or 0) < limit then break end
            if #Members >= maxCount then break end
            task.wait(0.2)
        end
        local first = Members[1]
        setStatus("✅ 名单已拿到本地：" .. #Members .. " 人" ..
            "\n（群里总人数 " .. tostring(total or "?") .. "）" ..
            (first and ("\n第一个：" .. tostring(first[2]) .. "（" .. tostring(first[1]) .. "）") or "") ..
            "\n→ 可以「复制前100条」或「导出CSV」")
        notify("名单已拉取", #Members .. " 人", "check", 5)
    end)
end

local function copyFirst()
    if #Members == 0 then
        notify("还没有名单", "先点「拉取名单」", "x")
        return
    end
    local lines = {}
    for i = 1, math.min(#Members, 100) do
        local r = Members[i]
        lines[#lines + 1] = tostring(r[1]) .. " " .. tostring(r[2]) .. " " .. tostring(r[3])
    end
    local clip = setclipboard or toclipboard or (syn and syn.setclipboard) or (getgenv and getgenv().setclipboard)
    if not clip then
        notify("不支持复制", "当前执行器没有 setclipboard", "x")
        return
    end
    pcall(clip, table.concat(lines, "\n"))
    notify("已复制", "前 " .. math.min(#Members, 100) .. " 条（userId 用户名 显示名）", "check", 5)
end

local function exportCsv()
    if #Members == 0 then
        notify("还没有名单", "先点「拉取名单」", "x")
        return
    end
    if not writefile then
        notify("不支持写文件", "当前执行器没有 writefile", "x")
        return
    end
    local lines = { "userId,username,displayName,rank,role" }
    for _, r in ipairs(Members) do
        lines[#lines + 1] = table.concat({
            tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]), tostring(r[5]),
        }, ",")
    end
    local fname = "group_" .. shortId() .. "_members.csv"
    local ok, err = pcall(writefile, fname, table.concat(lines, "\n"))
    if ok then
        notify("已导出", fname .. "（执行器文件夹里）", "check", 6)
    else
        notify("导出失败", tostring(err), "x", 6)
    end
end

-- ==================== 兜底：本机（手机）爬取并上传 ====================
local function sanitizeField(s)
    return tostring(s or ""):gsub("[:|]", ","):gsub("%s+", " ")
end

local function phoneCrawl()
    task.spawn(function()
        if PhoneCrawling then
            notify("正在爬", "本机爬取已经在跑", "info")
            return
        end
        local id = shortId()
        if id == "" then
            notify("缺少群组ID", "先填群组 ID", "x")
            return
        end
        PhoneCrawling = true

        -- 1) 先拿群组信息（顺便测试本机能不能连 Roblox）
        local name, memberCount = nil, nil
        local okInfo, raw = pcall(function()
            return game:HttpGet("https://groups.roblox.com/v1/groups/" .. id, true)
        end)
        if not okInfo then
            PhoneCrawling = false
            setStatus("本机也连不上 Roblox：" .. tostring(raw):sub(1, 100))
            notify("本机请求失败", tostring(raw):sub(1, 100), "x", 8)
            return
        end
        local okJ, j = pcall(function() return HttpService:JSONDecode(raw) end)
        if okJ then
            name, memberCount = j.name, j.memberCount
        end

        local cursor, pages, got = "", 0, 0
        local batch = {}
        while PhoneCrawling do
            local url = "https://groups.roblox.com/v1/groups/" .. id .. "/users?limit=100&sortOrder=Asc"
            if cursor ~= "" then
                url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
            end
            local ok, rawPage = pcall(function() return game:HttpGet(url, true) end)
            if not ok then
                setStatus("本机爬取出错：" .. tostring(rawPage):sub(0, 100) .. "\n已爬 " .. got)
                notify("本机爬取出错", tostring(rawPage):sub(0, 100), "x", 6)
                break
            end
            local okJ2, page = pcall(function() return HttpService:JSONDecode(rawPage) end)
            if not okJ2 then
                -- 多半是被限流了，等一下重试同一页
                setStatus("返回解析失败（可能被限流），5 秒后重试…已爬 " .. got)
                task.wait(5)
            else
                local data = page.data or {}
                for _, u in ipairs(data) do
                    local user = u.user or {}
                    batch[#batch + 1] = tostring(user.userId) .. ":" .. sanitizeField(user.username) .. ":" ..
                        sanitizeField(user.displayName) .. ":" .. tostring(u.role and u.role.rank or 0) .. ":" ..
                        sanitizeField(u.role and u.role.name or "")
                end
                cursor = page.nextPageCursor or ""
                pages = pages + 1
                got = got + #data
                -- 每 100 条往后台推一次（URL 别太长）
                if #batch >= 100 or cursor == "" then
                    local res = apiGet("/pushget", {
                        groupId = id,
                        name = name,
                        memberCount = memberCount,
                        done = (cursor == "" and "1" or "0"),
                        data = table.concat(batch, "|"),
                    })
                    if res and res.ok then
                        batch = {}
                    else
                        setStatus("上传后台失败：" .. tostring(res and res.error or "未知") .. "\n已爬 " .. got)
                        break
                    end
                end
                setStatus("本机爬取中（第 " .. pages .. " 页）\n已爬 " .. got .. " / " .. tostring(memberCount or "?"))
                if cursor == "" then break end
                task.wait(0.35)
            end
        end

        PhoneCrawling = false
        if got > 0 then
            setStatus("✅ 本机爬取完成，已推到后台\n共 " .. got .. " 人 / " .. pages .. " 页\n→ 点「刷新进度」或「拉取名单」")
            notify("本机爬取完成", got .. " 人已上传到后台", "check", 6)
        end
    end)
end

local function stopAll()
    Crawling = false
    PhoneCrawling = false
    setStatus("已停止（后台里已爬好的数据还在，随时可以继续）")
    notify("已停止", "可以点「刷新进度」看后台存了多少", "info", 4)
end

-- ==================== 界面 ====================
local uiOk, uiErr = pcall(function()
    local win = WindUI:CreateWindow({
        Title = "群组名单",
        Icon = "users",
        Author = "by suif",
        Folder = "GroupMembers",
        Size = UDim2.fromOffset(500, 560),
        ToggleKey = Enum.KeyCode.RightControl,
        Transparent = true,
        Theme = "Dark",
        Resizable = true,
        HideSearchBar = true,
    })

    local tab = win:Tab({ Title = "群组名单", Icon = "users", Locked = false })

    local setSec = tab:Section({ Title = "后台设置", Icon = "server", Opened = true })

    setSec:Input({
        Title = "后台地址",
        Desc = "Cloudflare Worker 的地址（部署群组爬取Worker.js 后得到）",
        Placeholder = "https://xxxx.workers.dev",
        Callback = function(v)
            API = tostring(v or ""):gsub("%s", "")
        end,
    })

    setSec:Input({
        Title = "群组 ID",
        Desc = "要爬的 Roblox 群组 ID（数字）",
        Placeholder = "例如 7",
        Callback = function(v)
            GROUP = tostring(v or "")
        end,
    })

    setSec:Input({
        Title = "后台密码（可选）",
        Desc = "Worker 里设了 KEY 环境变量才需要填",
        Placeholder = "没有就不用填",
        Callback = function(v)
            KEY = tostring(v or ""):gsub("%s", "")
        end,
    })

    local actSec = tab:Section({ Title = "操作", Icon = "play", Opened = true })

    actSec:Button({
        Title = "测试后台",
        Desc = "看后台能不能直连 Roblox（403 就要用本机爬取兜底）",
        Icon = "wifi",
        Callback = function() testBackend() end,
    })

    actSec:Button({
        Title = "开始爬取",
        Desc = "后台分批爬（每批 2000 人），爬完自动停；后台有定时任务的话点一次就行",
        Icon = "download",
        Callback = function() crawlLoop() end,
    })

    actSec:Button({
        Title = "刷新进度",
        Desc = "看后台存了多少人 / 什么状态",
        Icon = "refresh-cw",
        Callback = function() refreshStatus() end,
    })

    actSec:Button({
        Title = "拉取名单",
        Desc = "从后台取名单到本地（最多 5000 条）",
        Icon = "list",
        Callback = function() fetchMembers(5000) end,
    })

    actSec:Button({
        Title = "停止",
        Desc = "停掉正在跑的爬取（后台已爬的数据不会丢）",
        Icon = "square",
        Callback = function() stopAll() end,
    })

    local outSec = tab:Section({ Title = "导出", Icon = "file-down", Opened = true })

    outSec:Button({
        Title = "复制前 100 条",
        Desc = "格式：userId 用户名 显示名",
        Icon = "clipboard",
        Callback = function() copyFirst() end,
    })

    outSec:Button({
        Title = "导出 CSV 到执行器文件夹",
        Desc = "文件名 group_群组ID_members.csv",
        Icon = "file-text",
        Callback = function() exportCsv() end,
    })

    local fixSec = tab:Section({ Title = "兜底（后台被墙时用）", Icon = "alert-triangle", Opened = false })

    fixSec:Paragraph({
        Title = "后台连不上 Roblox 怎么办",
        Desc = "如果你的 Worker 出口 IP 被 Roblox 拦（返回 403 Roblox.com is not available），\n" ..
            "就用下面这个：由你的手机直接请求 Roblox 接口爬取，分批推到后台，之后照常从后台取名单。\n" ..
            "缺点：手机端慢（100 人/页，每页间隔 0.35 秒），爬大群要挂着。",
    })

    fixSec:Button({
        Title = "本机爬取并上传",
        Desc = "手机直接爬 → 推到后台（后台被墙时的替代方案）",
        Icon = "smartphone",
        Callback = function() phoneCrawl() end,
    })

    local stSec = tab:Section({ Title = "状态", Icon = "activity", Opened = true })

    stSec:Paragraph({
        Title = "当前进度",
        Desc = STATUS_PLACEHOLDER,
    })
end)

if not uiOk then
    warn("[群组名单] 界面创建失败：" .. tostring(uiErr))
    return
end

task.wait(0.6)
pcall(function() findStatusLabel() end)

notify("群组名单", "填「后台地址」和「群组 ID」→ 点「测试后台」", "check", 6)
