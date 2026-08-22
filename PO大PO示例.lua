if getgenv().__SUTURE_PO_LOADED then
    return
end
getgenv().__SUTURE_PO_LOADED = true

local Tab = (getgenv().Tabs and getgenv().Tabs.POTab) or getgenv().SuturePOTab
if not Tab then
    warn("[po大po] 未找到 Tab，请检查主脚本赋值")
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 安全获取 RemoteEvent：任何游戏都不崩，找不到不提示、UI 照常挂载
local RemoteEvent = nil
pcall(function()
    RemoteEvent = ReplicatedStorage.Packets.Packet.RemoteEvent
end)

-- ==================== UI ====================
local sec = Tab:Section({ Title = "po大po 功能", Icon = "settings", Opened = true })

Tab:Paragraph({
    Title = "说明",
    Desc = "功能通过 Packets.Packet.RemoteEvent 发包实现\n卡服会被踢但很爽，谨慎使用"
})

-- 自动售卖
local run1 = false
Tab:Toggle({
    Title = "自动售卖",
    Desc = "自动卖臭臭（高速发包）",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        run1 = state
        if state then
            if not RemoteEvent then return end
            task.spawn(function()
                while run1 do
                    pcall(function()
                        RemoteEvent:FireServer(buffer.fromstring("\3\0"))
                    end)
                    task.wait(0.0001)
                end
            end)
        end
    end
})

-- 卡服
local run2 = false
Tab:Toggle({
    Title = "卡服",
    Desc = "拉很多臭臭（会被踢，但很爽）",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        run2 = state
        if state then
            if not RemoteEvent then return end
            task.spawn(function()
                while run2 do
                    pcall(function()
                        RemoteEvent:FireServer(buffer.fromstring("\0\0\0\0"))
                    end)
                    task.wait(0.00000000001)
                end
            end)
        end
    end
})

-- 自动拉屎
local run3 = false
Tab:Toggle({
    Title = "自动拉屎",
    Desc = "拉臭臭",
    Type = "Checkbox",
    Value = false,
    Callback = function(state)
        run3 = state
        if state then
            if not RemoteEvent then return end
            task.spawn(function()
                while run3 do
                    pcall(function()
                        RemoteEvent:FireServer(buffer.fromstring("\0\0\0\0"))
                    end)
                    task.wait(0.5)
                end
            end)
        end
    end
})
