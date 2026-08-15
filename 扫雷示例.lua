-- 扫雷自动机器人（WindUI 独立版）
-- 提取自 blockerman_full.lua：去除卡密系统，仅保留地雷相关功能
-- 功能：自动标记 / 自动行走 / 雷区ESP / 防爆炸

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- ===== 状态 =====
local autoWalkActive = false
local autoFlagActive = false
local espActive = false
local antiExplosionActive = false
local antiExplosionConn = nil
local AutoWalkToggle = nil

local customWalkSpeed = 16
local customJumpPower = 50
local flying = false
local flagDistance = 15
local flagDelay = 0.45
local espRefreshInterval = 0.2
local _lastEspRefresh = 0

-- ESP 颜色
local espSafeColor = Color3.fromRGB(0, 0, 255)
local espBombColor = Color3.fromRGB(255, 0, 0)
local espUncertainLow = Color3.fromRGB(255, 215, 0)
local espUncertainMed = Color3.fromRGB(255, 165, 0)
local espUncertainHigh = Color3.fromRGB(220, 20, 60)

local grid = {}
local W, H = 0, 0
local xToCol, zToRow = {}, {}
local localFlags = {}
local deducedBombs = {}

local espFolder = workspace:FindFirstChild("BotESPFolder")
if not espFolder then
    espFolder = Instance.new("Folder")
    espFolder.Name = "BotESPFolder"
    espFolder.Parent = workspace
end

local function notify(title, content)
    pcall(function()
        WindUI:Notify({ Title = title, Content = content, Icon = "bomb", Duration = 3 })
    end)
end

-- ============================================
-- 以下是扫雷核心逻辑（原样保留）
-- ============================================

-- ============================================
-- MOBILE-COMPATIBLE SECRET KEY SCANNER
-- Scans GC and upvalues for the Minesweeper game's auth key.
-- Compatible with Delta, Codex, Arceus X, and other Android executors.
-- ============================================

local function getSecretKey()
    -- 1. Check workspace Salasana value object (some game versions)
    local salasana = workspace:FindFirstChild("Salasana")
    if salasana and salasana:IsA("ValueObject") and salasana.Value ~= 0 then
        return tostring(salasana.Value)
    end

    -- 2. GC scan for MouseControl upvalues (primary method)
    if getgc then
        for _, v in pairs(getgc(true)) do
            if type(v) == "function" then
                local ok, info = pcall(debug.info, v, "s")
                info = ok and info or ""
                if info:find("MouseControl") then
                    local ok2, upvals = pcall(debug.getupvalues, v)
                    if ok2 and upvals then
                        local hasPlaceFlag = false
                        local potentialKey = nil
                        for _, uv in pairs(upvals) do
                            if typeof(uv) == "Instance" and (uv.Name == "PlaceFlag" or uv.Name == "FlagEvents" or uv.Name == "ReplicatedStorage") then
                                hasPlaceFlag = true
                            elseif type(uv) == "string" and #uv >= 10 and tonumber(uv) ~= nil then
                                potentialKey = uv
                            elseif type(uv) == "number" and uv > 1000 then
                                potentialKey = tostring(uv)
                            end
                        end
                        if hasPlaceFlag and potentialKey then
                            return potentialKey
                        end
                    end
                end
            end
        end

        -- Generic GC fallback
        for _, v in pairs(getgc(true)) do
            if type(v) == "function" then
                local ok2, upvals = pcall(debug.getupvalues, v)
                if ok2 and upvals then
                    local hasPlaceFlag = false
                    local potentialKey = nil
                    for _, uv in pairs(upvals) do
                        if typeof(uv) == "Instance" and (uv.Name == "PlaceFlag" or uv.Name == "FlagEvents" or uv.Name == "ReplicatedStorage") then
                            hasPlaceFlag = true
                        elseif type(uv) == "string" and #uv >= 10 and tonumber(uv) ~= nil then
                            potentialKey = uv
                        elseif type(uv) == "number" and uv > 1000 then
                            potentialKey = tostring(uv)
                        end
                    end
                    if hasPlaceFlag and potentialKey then
                        return potentialKey
                    end
                end
            end
        end
    end

    -- 3. Connection scanning fallback (PC compatibility)
    local function scanUpvaluesForKey(func, depth, maxDepth)
        depth = depth or 0
        maxDepth = maxDepth or 3
        if depth > maxDepth then return nil end
        local ok, upvals = pcall(debug.getupvalues, func)
        if not ok or not upvals then return nil end
        for _, v in pairs(upvals) do
            if type(v) == "string" and (tonumber(v) ~= nil or #v > 10) then
                return v
            elseif type(v) == "number" then
                return tostring(v)
            elseif type(v) == "function" then
                local nested = scanUpvaluesForKey(v, depth + 1, maxDepth)
                if nested then return nested end
            end
        end
        return nil
    end

    local function getConnectionsForEvent(event)
        local connections = {}
        local success, conns = pcall(getconnections, event)
        if success and conns then
            for _, conn in ipairs(conns) do
                table.insert(connections, conn)
            end
        end
        return connections
    end

    local mouse = player:GetMouse()
    local allEvents = {
        mouse.Button1Down, mouse.Button2Down,
        UserInputService.TouchTap, UserInputService.TouchTapInWorld,
        UserInputService.TouchLongPress, UserInputService.TouchMoved,
        UserInputService.TouchPan, UserInputService.TouchPinch,
        UserInputService.TouchRotate, UserInputService.TouchSwipe,
        UserInputService.TouchStarted, UserInputService.TouchEnded,
        UserInputService.InputBegan, UserInputService.InputEnded, UserInputService.InputChanged
    }

    for _, event in ipairs(allEvents) do
        for _, conn in ipairs(getConnectionsForEvent(event)) do
            local func = conn.Function
            if func then
                local key = scanUpvaluesForKey(func)
                if key then return key end
            end
        end
    end

    return nil
end

-- ============================================
-- FLAG & BLOCK CHECKS
-- ============================================

local function hasServerFlag(part)
    if not part then return false end
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("Model") then return true end
    end
    return false
end

local function checkFlagged(part)
    return localFlags[part] == true or deducedBombs[part] == true
end

local function checkBlocked(part)
    return localFlags[part] == true or deducedBombs[part] == true or hasServerFlag(part)
end

-- ============================================
-- ESP SYSTEM
-- ============================================

local function clearESP()
    espFolder:ClearAllChildren()
end

local function updateESP(safeTiles, borderProbabilities)
    clearESP()
    if not espActive then return end

    -- Deduced bombs
    for part in pairs(deducedBombs) do
        if part and part.Parent then
            local box = Instance.new("SelectionBox")
            box.Adornee = part
            box.Color3 = espBombColor
            box.LineThickness = 0.06
            box.SurfaceColor3 = espBombColor
            box.SurfaceTransparency = 0.45
            box.Parent = espFolder
        end
    end

    -- Deduced safe tiles
    for _, cell in pairs(safeTiles) do
        if cell.part and cell.part.Parent then
            local box = Instance.new("SelectionBox")
            box.Adornee = cell.part
            box.Color3 = espSafeColor
            box.LineThickness = 0.06
            box.SurfaceColor3 = espSafeColor
            box.SurfaceTransparency = 0.45
            box.Parent = espFolder
        end
    end

    -- Uncertain tiles: colored border + probability billboard
    for part, P in pairs(borderProbabilities) do
        if part and part.Parent then
            local color = espUncertainMed
            if P < 0.35 then
                color = espUncertainLow
            elseif P > 0.65 then
                color = espUncertainHigh
            end

            local box = Instance.new("SelectionBox")
            box.Adornee = part
            box.Color3 = color
            box.LineThickness = 0.05
            box.SurfaceColor3 = color
            box.SurfaceTransparency = 0.6
            box.Parent = espFolder

            local bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 100, 0, 40)
            bb.AlwaysOnTop = true
            bb.Adornee = part
            bb.StudsOffset = Vector3.new(0, 3, 0)

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.TextSize = 26
            label.TextColor3 = color
            label.Font = Enum.Font.GothamBold
            label.TextStrokeTransparency = 0
            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            label.Text = string.format("%.0f%%", P * 100)
            label.Parent = bb
            bb.Parent = espFolder
        end
    end
end

-- ============================================
-- GRID INITIALIZATION
-- ============================================

local function initGrid()
    grid = {}
    xToCol = {}
    zToRow = {}
    localFlags = {}
    deducedBombs = {}
    clearESP()

    local flag = workspace:FindFirstChild("Flag")
    local partsFolder = flag and flag:FindFirstChild("Parts")
    local parts = partsFolder and partsFolder:GetChildren()
    if not parts then return end

    local xCoords = {}
    local zCoords = {}

    for _, p in ipairs(parts) do
        xCoords[math.floor(p.Position.X + 0.5)] = true
        zCoords[math.floor(p.Position.Z + 0.5)] = true
    end

    local sortedX = {}
    for x in pairs(xCoords) do table.insert(sortedX, x) end
    table.sort(sortedX)

    local sortedZ = {}
    for z in pairs(zCoords) do table.insert(sortedZ, z) end
    table.sort(sortedZ)

    for col, x in ipairs(sortedX) do xToCol[x] = col end
    for row, z in ipairs(sortedZ) do zToRow[z] = row end

    W = #sortedX
    H = #sortedZ

    for col = 1, W do
        grid[col] = {}
        for row = 1, H do
            grid[col][row] = {
                part = nil,
                isOpened = false,
                isFlagged = false,
                isBlocked = false,
                value = 0,
                col = col,
                row = row
            }
        end
    end

    for _, p in ipairs(parts) do
        local x = math.floor(p.Position.X + 0.5)
        local z = math.floor(p.Position.Z + 0.5)
        local col = xToCol[x]
        local row = zToRow[z]
        if col and row then
            grid[col][row].part = p
        end
    end

    -- Seed deducedBombs from existing server flags at initialization
    for col = 1, W do
        for row = 1, H do
            local cell = grid[col][row]
            if cell.part and hasServerFlag(cell.part) then
                deducedBombs[cell.part] = true
                cell.isFlagged = true
                cell.isBlocked = true
            end
        end
    end

    print("[Grid] Mapped: " .. W .. "x" .. H)
end

local function checkGridValid()
    if W == 0 or H == 0 then return false end
    for col = 1, W do
        if not grid[col] then return false end
        for row = 1, H do
            local cell = grid[col][row]
            if not cell or not cell.part or not cell.part:IsDescendantOf(workspace) then
                return false
            end
        end
    end
    return true
end

-- ============================================
-- BOARD SCANNING
-- ============================================

local function scanBoard()
    local state = {}
    for col = 1, W do
        state[col] = {}
        for row = 1, H do
            local cell = grid[col][row]
            local isOpened = false
            local value = 0
            local isFlagged = false
            local isBlocked = false

            if cell.part then
                isOpened = cell.part:FindFirstChild("NumberGui") ~= nil
                if isOpened then
                    local label = cell.part.NumberGui:FindFirstChild("TextLabel")
                    local text = label and label.Text or ""
                    value = tonumber(text) or 0
                end
                isFlagged = checkFlagged(cell.part)
                isBlocked = checkBlocked(cell.part)
            end

            state[col][row] = {
                isOpened = isOpened,
                value = value,
                isFlagged = isFlagged,
                isBlocked = isBlocked
            }
        end
    end
    return state
end

-- ============================================
-- PATHFINDING
-- ============================================

local function getCurrentPlayerGrid()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil end

    local nearestCol, nearestRow = nil, nil
    local minDist = math.huge

    for col = 1, W do
        for row = 1, H do
            local cell = grid[col][row]
            if cell.part then
                local dist = (cell.part.Position - root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    nearestCol = col
                    nearestRow = row
                end
            end
        end
    end
    return nearestCol, nearestRow
end

local function findPath(startCol, startRow, targetCol, targetRow)
    local queue = {{startCol, startRow, {}}}
    local visited = {}
    visited[startCol .. "_" .. startRow] = true

    while #queue > 0 do
        local curr = table.remove(queue, 1)
        local c, r, path = curr[1], curr[2], curr[3]

        if c == targetCol and r == targetRow then
            return path
        end

        local dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
        for _, dir in ipairs(dirs) do
            local nc = c + dir[1]
            local nr = r + dir[2]
            local key = nc .. "_" .. nr

            if nc >= 1 and nc <= W and nr >= 1 and nr <= H and not visited[key] then
                local neighbor = grid[nc][nr]
                local isFlaggedOnServer = hasServerFlag(neighbor.part)
                if neighbor.isOpened or isFlaggedOnServer or (nc == targetCol and nr == targetRow) then
                    visited[key] = true
                    local newPath = {}
                    for _, p in ipairs(path) do table.insert(newPath, p) end
                    table.insert(newPath, neighbor.part)
                    table.insert(queue, {nc, nr, newPath})
                end
            end
        end
    end
    return nil
end

local function getConnectedComponent(startCol, startRow)
    local queue = {{startCol, startRow}}
    local visited = {}
    visited[startCol .. "_" .. startRow] = true
    local component = {}

    while #queue > 0 do
        local curr = table.remove(queue, 1)
        local c, r = curr[1], curr[2]
        table.insert(component, grid[c][r])

        local dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
        for _, dir in ipairs(dirs) do
            local nc = c + dir[1]
            local nr = r + dir[2]
            local key = nc .. "_" .. nr

            if nc >= 1 and nc <= W and nr >= 1 and nr <= H and not visited[key] then
                local neighbor = grid[nc][nr]
                local isFlaggedOnServer = hasServerFlag(neighbor.part)
                if neighbor.isOpened or isFlaggedOnServer then
                    visited[key] = true
                    table.insert(queue, {nc, nr})
                end
            end
        end
    end
    return component
end

local function getLocalGuessCandidates(pCol, pRow)
    local component = getConnectedComponent(pCol, pRow)
    local candidates = {}
    local seen = {}

    for _, cell in ipairs(component) do
        local dirs = {
            {1, 0}, {-1, 0}, {0, 1}, {0, -1},
            {1, 1}, {-1, 1}, {1, -1}, {-1, -1}
        }
        for _, dir in ipairs(dirs) do
            local nc = cell.col + dir[1]
            local nr = cell.row + dir[2]
            if nc >= 1 and nc <= W and nr >= 1 and nr <= H then
                local neighbor = grid[nc][nr]
                if not neighbor.isOpened and not neighbor.isBlocked then
                    local key = nc .. "_" .. nr
                    if not seen[key] then
                        seen[key] = true
                        table.insert(candidates, neighbor)
                    end
                end
            end
        end
    end
    return candidates
end

-- ============================================
-- SOLVER ENGINE
-- ============================================

local function solveEquations(safeTiles, borderProbabilities)
    local clues = {}
    local borderMap = {}
    local borderList = {}

    for col = 1, W do
        for row = 1, H do
            local cell = grid[col][row]
            if cell.isOpened and cell.value > 0 then
                local unopened = {}
                local flaggedCount = 0
                for dc = -1, 1 do
                    for dr = -1, 1 do
                        if not (dc == 0 and dr == 0) then
                            local nc = col + dc
                            local nr = row + dr
                            if nc >= 1 and nc <= W and nr >= 1 and nr <= H then
                                local nCell = grid[nc][nr]
                                if nCell.isFlagged then
                                    flaggedCount = flaggedCount + 1
                                elseif not nCell.isOpened then
                                    table.insert(unopened, nCell)
                                end
                            end
                        end
                    end
                end

                if #unopened > 0 then
                    table.insert(clues, {
                        cell = cell,
                        unopened = unopened,
                        target = cell.value - flaggedCount
                    })
                    for _, nCell in ipairs(unopened) do
                        if not borderMap[nCell] then
                            borderMap[nCell] = true
                            table.insert(borderList, nCell)
                        end
                    end
                end
            end
        end
    end

    if #borderList == 0 then return end

    -- Group into independent connected constraint components
    local components = {}
    local visitedClues = {}
    local visitedVars = {}

    for _, clue in ipairs(clues) do
        if not visitedClues[clue] then
            local compClues = {}
            local compVars = {}
            local queue = {clue}
            visitedClues[clue] = true

            while #queue > 0 do
                local currClue = table.remove(queue, 1)
                table.insert(compClues, currClue)

                for _, nCell in ipairs(currClue.unopened) do
                    if not visitedVars[nCell] then
                        visitedVars[nCell] = true
                        table.insert(compVars, nCell)

                        for _, otherClue in ipairs(clues) do
                            if not visitedClues[otherClue] then
                                local contains = false
                                for _, c in ipairs(otherClue.unopened) do
                                    if c == nCell then contains = true; break end
                                end
                                if contains then
                                    visitedClues[otherClue] = true
                                    table.insert(queue, otherClue)
                                end
                            end
                        end
                    end
                end
            end
            table.insert(components, {clues = compClues, vars = compVars})
        end
    end

    -- Solve each component via backtracking (capped at 20 vars)
    for _, comp in ipairs(components) do
        local vars = comp.vars
        local compClues = comp.clues

        if #vars <= 20 then
            local solutions = {}
            local currentAssignment = {}

            local function backtrack(varIndex)
                if varIndex > #vars then
                    for _, clue in ipairs(compClues) do
                        local sum = 0
                        for _, nCell in ipairs(clue.unopened) do
                            sum = sum + (currentAssignment[nCell] or 0)
                        end
                        if sum ~= clue.target then return end
                    end
                    local sol = {}
                    for k, v in pairs(currentAssignment) do sol[k] = v end
                    table.insert(solutions, sol)
                    return
                end

                local currentVar = vars[varIndex]

                for _, clue in ipairs(compClues) do
                    local sum = 0
                    local unassigned = 0
                    for _, nCell in ipairs(clue.unopened) do
                        local assign = currentAssignment[nCell]
                        if assign then
                            sum = sum + assign
                        else
                            unassigned = unassigned + 1
                        end
                    end
                    if sum > clue.target or sum + unassigned < clue.target then
                        return
                    end
                end

                currentAssignment[currentVar] = 0
                backtrack(varIndex + 1)
                currentAssignment[currentVar] = 1
                backtrack(varIndex + 1)
                currentAssignment[currentVar] = nil
            end

            backtrack(1)

            if #solutions > 0 then
                for _, var in ipairs(vars) do
                    local bombCount = 0
                    for _, sol in ipairs(solutions) do
                        if sol[var] == 1 then bombCount = bombCount + 1 end
                    end
                    local P = bombCount / #solutions
                    if P == 0 then
                        safeTiles[var.col .. "_" .. var.row] = var
                    elseif P == 1 then
                        deducedBombs[var.part] = true
                    else
                        borderProbabilities[var.part] = P
                    end
                end
            end
        end
    end
end

local function updateDeductions()
    -- Double scan for stability
    local state1 = scanBoard()
    task.wait(0.05)
    local state2 = scanBoard()

    local stable = true
    for col = 1, W do
        for row = 1, H do
            local c1 = state1[col][row]
            local c2 = state2[col][row]
            if c1.isOpened ~= c2.isOpened or c1.value ~= c2.value or c1.isFlagged ~= c2.isFlagged or c1.isBlocked ~= c2.isBlocked then
                stable = false; break
            end
        end
        if not stable then break end
    end

    if not stable then return false end

    for col = 1, W do
        for row = 1, H do
            local cell = grid[col][row]
            local st = state1[col][row]
            cell.isOpened = st.isOpened
            cell.value = st.value
            cell.isFlagged = st.isFlagged
            cell.isBlocked = st.isBlocked
        end
    end

    local safeTiles = {}
    local borderProbabilities = {}
    local deducedNewBomb = false

    -- Global constraint: if remaining unopened == remaining mines, all are bombs
    local totalUnopened = {}
    local totalFlagged = 0
    for col = 1, W do
        for row = 1, H do
            local cell = grid[col][row]
            if cell.part then
                if cell.isFlagged then
                    totalFlagged = totalFlagged + 1
                elseif not cell.isOpened then
                    table.insert(totalUnopened, cell)
                end
            end
        end
    end

    local minesVal = ReplicatedStorage:FindFirstChild("Info") and
        ReplicatedStorage.Info:FindFirstChild("Mines") and
        ReplicatedStorage.Info.Mines.Value or 0
    local remainingMines = minesVal - totalFlagged

    if #totalUnopened > 0 then
        if #totalUnopened == remainingMines then
            for _, cell in ipairs(totalUnopened) do
                if not deducedBombs[cell.part] then
                    deducedBombs[cell.part] = true
                    cell.isFlagged = true
                    cell.isBlocked = true
                    deducedNewBomb = true
                end
            end
        elseif remainingMines == 0 then
            for _, cell in ipairs(totalUnopened) do
                safeTiles[cell.col .. "_" .. cell.row] = cell
            end
        end
    end

    -- Matrix solver + fallback single-cell rules
    if not deducedNewBomb then
        solveEquations(safeTiles, borderProbabilities)

        for col = 1, W do
            for row = 1, H do
                local cell = grid[col][row]
                if cell.isOpened and cell.value > 0 then
                    local flaggedNeighbors = 0
                    local unopenedNeighbors = {}

                    for dc = -1, 1 do
                        for dr = -1, 1 do
                            if not (dc == 0 and dr == 0) then
                                local nc = col + dc
                                local nr = row + dr
                                if nc >= 1 and nc <= W and nr >= 1 and nr <= H then
                                    local nCell = grid[nc][nr]
                                    if nCell.isFlagged then
                                        flaggedNeighbors = flaggedNeighbors + 1
                                    elseif not nCell.isOpened then
                                        table.insert(unopenedNeighbors, nCell)
                                    end
                                end
                            end
                        end
                    end

                    if cell.value - flaggedNeighbors == #unopenedNeighbors and #unopenedNeighbors > 0 then
                        for _, nCell in ipairs(unopenedNeighbors) do
                            if not deducedBombs[nCell.part] then
                                deducedBombs[nCell.part] = true
                                nCell.isFlagged = true
                                nCell.isBlocked = true
                                deducedNewBomb = true
                            end
                        end
                    end

                    if cell.value == flaggedNeighbors and #unopenedNeighbors > 0 then
                        for _, nCell in ipairs(unopenedNeighbors) do
                            if not nCell.isFlagged and not nCell.isOpened then
                                safeTiles[nCell.col .. "_" .. nCell.row] = nCell
                            end
                        end
                    end
                end
            end
        end
    end

    if espActive then
        updateESP(safeTiles, borderProbabilities)
    end

    return true, safeTiles, borderProbabilities, deducedNewBomb
end

-- ============================================
-- MOVEMENT & WALKING
-- ============================================

local function walkTo(part)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    hum.WalkSpeed = customWalkSpeed
    local targetPos = Vector3.new(part.Position.X, root.Position.Y, part.Position.Z)
    hum:MoveTo(targetPos)

    local startT = os.clock()
    while (root.Position - targetPos).Magnitude > 1.0 and autoWalkActive do
        if os.clock() - startT > 3 then break end
        task.wait()
        hum:MoveTo(targetPos)
    end
end

local function walkPath(path)
    for _, part in ipairs(path) do
        if not autoWalkActive then break end
        walkTo(part)
    end
end

-- ============================================
task.spawn(function()
    while true do
        task.wait(espRefreshInterval)

        if autoWalkActive or autoFlagActive or espActive then
            local gameRunningVal = ReplicatedStorage:FindFirstChild("Info") and
                ReplicatedStorage.Info:FindFirstChild("GameRunning") and
                ReplicatedStorage.Info.GameRunning.Value

            if not gameRunningVal then
                localFlags = {}
                deducedBombs = {}
                clearESP()
                task.wait(0.5)
                continue
            end

            if not checkGridValid() then
                initGrid()
                task.wait(0.1)
                continue
            end

            local success, safeTiles, borderProbabilities, deducedNewBomb = updateDeductions()
            if not success then continue end

            -- Auto Flag: place flags within flagDistance studs, with flagDelay between each
            if autoFlagActive then
                local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local key = getSecretKey()
                if root and key then
                    for part in pairs(deducedBombs) do
                        if not hasServerFlag(part) then
                            local dist = (part.Position - root.Position).Magnitude
                            if dist < flagDistance then
                                ReplicatedStorage.Events.FlagEvents.PlaceFlag:FireServer(part, key, true)
                                localFlags[part] = true
                                if flagDelay > 0 then task.wait(flagDelay) end
                            end
                        end
                    end
                end
            end

            -- Auto Walk: navigate to safest reachable tile
            if autoWalkActive and not deducedNewBomb then
                local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local pCol, pRow = getCurrentPlayerGrid()
                if root and pCol and pRow then
                    local openedCount = 0
                    for col = 1, W do
                        for row = 1, H do
                            if grid[col][row].isOpened then openedCount = openedCount + 1 end
                        end
                    end

                    if openedCount == 0 then
                        local midCol = math.floor(W / 2) + 1
                        local midRow = math.floor(H / 2) + 1
                        local targetPart = grid[midCol][midRow].part
                        if targetPart then
                            walkTo(targetPart)
                            task.wait(0.3)
                        end
                    else
                        local key = getSecretKey()
                        if key then
                            -- Find nearest safe tile by BFS path length
                            local targetCell = nil
                            local bestPath = nil
                            local minPathLen = math.huge

                            for _, cell in pairs(safeTiles) do
                                local path = findPath(pCol, pRow, cell.col, cell.row)
                                if path and #path < minPathLen then
                                    minPathLen = #path
                                    targetCell = cell
                                    bestPath = path
                                end
                            end

                            if bestPath and targetCell then
                                walkPath(bestPath)
                                local startWait = os.clock()
                                while not targetCell.part:FindFirstChild("NumberGui") and
                                    os.clock() - startWait < 1.0 and autoWalkActive do
                                    task.wait(0.05)
                                end
                            else
                                -- Probability guess: lowest mine probability
                                local bestGuessCell = nil
                                local minProb = math.huge

                                for part, P in pairs(borderProbabilities) do
                                    local x = math.floor(part.Position.X + 0.5)
                                    local z = math.floor(part.Position.Z + 0.5)
                                    local col = xToCol[x]
                                    local row = zToRow[z]
                                    if col and row and P < minProb then
                                        minProb = P
                                        bestGuessCell = grid[col][row]
                                    end
                                end

                                if bestGuessCell then
                                    local path = findPath(pCol, pRow, bestGuessCell.col, bestGuessCell.row)
                                    if path then walkPath(path) else walkTo(bestGuessCell.part) end
                                    local startWait = os.clock()
                                    while not bestGuessCell.part:FindFirstChild("NumberGui") and
                                        os.clock() - startWait < 1.0 and autoWalkActive do
                                        task.wait(0.05)
                                    end
                                else
                                    -- Final fallback: random local guess
                                    local candidates = getLocalGuessCandidates(pCol, pRow)
                                    if #candidates > 0 then
                                        local guessCell = candidates[math.random(1, #candidates)]
                                        local path = findPath(pCol, pRow, guessCell.col, guessCell.row)
                                        if path then walkPath(path) else walkTo(guessCell.part) end
                                        local startWait = os.clock()
                                        while not guessCell.part:FindFirstChild("NumberGui") and
                                            os.clock() - startWait < 1.0 and autoWalkActive do
                                            task.wait(0.05)
                                        end
                                    else
                                        autoWalkActive = false
                                        if AutoWalkToggle then AutoWalkToggle:Set(false) end
                                        notify("Auto Walk", "Stopped — no reachable candidates.")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else
            clearESP()
            task.wait(0.2)
        end
    end
end)
local function applyAntiExplosion(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 3)
    if not hum then return end

    if antiExplosionConn then antiExplosionConn:Disconnect(); antiExplosionConn = nil end

    if not antiExplosionActive then return end

    -- Intercept Dead state only — let HP drain so the server fires the
    -- explosion animation, then snap the humanoid back to Running.
    antiExplosionConn = hum.StateChanged:Connect(function(old, new)
        if not antiExplosionActive then return end
        if new == Enum.HumanoidStateType.Dead then
            task.defer(function()
                if hum and hum.Parent then
                    hum.Health = hum.MaxHealth
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end
            end)
        end
    end)
end

-- Re-apply on every character spawn (also needed if player does die before toggle is on)
player.CharacterAdded:Connect(function(char)
    if antiExplosionActive then
        task.defer(function() applyAntiExplosion(char) end)
    end
end)

if player.Character and antiExplosionActive then
    applyAntiExplosion(player.Character)
end

-- ============================================
-- CHARACTER RESPAWN HANDLER
-- ============================================

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.UseJumpPower = true
        hum.WalkSpeed = customWalkSpeed
        hum.JumpPower = customJumpPower
    end
    if flying then task.spawn(function()
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if root then
            if flyGyro then flyGyro:Destroy() end
            if flyVelocity then flyVelocity:Destroy() end
            flyGyro = Instance.new("BodyGyro")
            flyGyro.P = 9e4
            flyGyro.maxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyGyro.cframe = root.CFrame
            flyGyro.Parent = root
            flyVelocity = Instance.new("BodyVelocity")
            flyVelocity.velocity = Vector3.new(0, 0.1, 0)
            flyVelocity.maxForce = Vector3.new(9e9, 9e9, 9e9)
            flyVelocity.Parent = root
            hum.PlatformStand = true
        end
    end) end
end

if player.Character then task.spawn(onCharacterAdded, player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- ============================================

-- ============================================
-- WINDUI 界面
-- ============================================

local win = WindUI:CreateWindow({
    Title = "扫雷自动机器人",
    Icon = "bomb",
    Author = "Suture",
    Folder = "MinesweeperBot",
    Size = UDim2.fromOffset(620, 460),
    MinSize = Vector2.new(560, 350),
    Resizable = true,
    Theme = "Dark",
    SideBarWidth = 160,
})

local botSec = win:Section({ Title = "扫雷机器人", Icon = "folder", Opened = true })
local mainTab = botSec:Tab({ Title = "自动", Icon = "bot" })
local espTab = botSec:Tab({ Title = "ESP", Icon = "eye" })
local safeTab = botSec:Tab({ Title = "安全", Icon = "shield" })

-- ===== 自动 =====
local autoSec = mainTab:Section({ Title = "自动功能", Icon = "settings", Opened = true })

local function setAutoWalk(val)
    autoWalkActive = val
    if val then
        initGrid()
        notify("自动行走", "已开启")
    else
        notify("自动行走", "已关闭")
    end
end

local function setAutoFlag(val)
    autoFlagActive = val
    if val then
        initGrid()
        notify("自动标记", "已开启")
    else
        notify("自动标记", "已关闭")
    end
end

AutoWalkToggle = autoSec:Toggle({
    Title = "自动行走",
    Desc = "自动走向最安全 / 确定安全的格子",
    Value = false,
    Callback = setAutoWalk,
})

autoSec:Toggle({
    Title = "自动标记",
    Desc = "自动给推断出的雷插旗",
    Value = false,
    Callback = setAutoFlag,
})

autoSec:Slider({
    Title = "标记距离",
    Step = 5,
    Value = { Min = 5, Max = 30, Default = flagDistance },
    Callback = function(v) flagDistance = v end,
})

autoSec:Slider({
    Title = "标记间隔（秒）",
    Step = 0.1,
    Value = { Min = 0, Max = 2, Default = flagDelay },
    Callback = function(v) flagDelay = v end,
})

autoSec:Slider({
    Title = "行走速度",
    Step = 1,
    Value = { Min = 16, Max = 150, Default = customWalkSpeed },
    Callback = function(v)
        customWalkSpeed = v
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = v end
    end,
})

autoSec:Button({
    Title = "重新初始化棋盘",
    Desc = "进入对局后棋盘没识别到时手动点一下",
    Callback = function()
        initGrid()
        notify("棋盘", "已重新初始化")
    end,
})

-- ===== ESP =====
local espSec = espTab:Section({ Title = "ESP 设置", Icon = "eye", Opened = true })

espSec:Toggle({
    Title = "ESP 开关",
    Desc = "高亮雷 / 安全 / 不确定格子",
    Value = false,
    Callback = function(val)
        espActive = val
        if val then
            initGrid()
            notify("ESP", "已开启")
        else
            clearESP()
            notify("ESP", "已关闭")
        end
    end,
})

espSec:Slider({
    Title = "刷新间隔（秒）",
    Step = 0.05,
    Value = { Min = 0.05, Max = 5, Default = espRefreshInterval },
    Callback = function(v) espRefreshInterval = v end,
})

-- ===== 安全 =====
local safeSec = safeTab:Section({ Title = "安全", Icon = "shield", Opened = true })

safeSec:Toggle({
    Title = "防爆炸（无敌）",
    Desc = "踩雷不会死，服务器仍会触发爆炸动画",
    Value = false,
    Callback = function(val)
        antiExplosionActive = val
        if val then
            applyAntiExplosion(player.Character)
            notify("防爆炸", "已开启")
        else
            if antiExplosionConn then
                antiExplosionConn:Disconnect()
                antiExplosionConn = nil
            end
            notify("防爆炸", "已关闭")
        end
    end,
})

mainTab:Select()
WindUI:Notify({ Title = "扫雷自动机器人", Content = "加载完成", Icon = "bomb", Duration = 3 })
