local R = ...
local Chess = R("chess")

local Reader = {}

local TYPE_WORDS = { { "pawn", 1 }, { "knight", 2 }, { "bishop", 3 }, { "rook", 4 }, { "queen", 5 }, { "king", 6 } }
local EXPECTED = { [1] = 8, [2] = 2, [3] = 2, [4] = 2, [5] = 1, [6] = 1 }
local ATTRS = { "Color", "Colour", "Team", "Side", "Owner" }
local START_BOARD = Chess.fromFen(Chess.START_FEN).board

local function typeOf(inst)
    local n = string.lower(inst.Name)
    for _, w in ipairs(TYPE_WORDS) do
        if string.find(n, w[1], 1, true) then return w[2] end
    end
    return nil
end

local function textColor(s)
    s = string.lower(tostring(s))
    local w, b = string.find(s, "white", 1, true), string.find(s, "black", 1, true)
    if w and not b then return 1 end
    if b and not w then return -1 end
    return nil
end

local function nameColor(u) return textColor(u.Name) end
local function ancestorColor(u)
    local p = u.Parent
    while p and p ~= workspace do
        local c = textColor(p.Name)
        if c then return c end
        p = p.Parent
    end
    return nil
end
local function attributeColor(u)
    for _, key in ipairs(ATTRS) do
        local v = u:GetAttribute(key)
        if type(v) == "string" then
            local c = textColor(v)
            if c then return c end
        end
    end
    return nil
end
local NAMED = { name = nameColor, ancestor = ancestorColor, attribute = attributeColor }
local ORDER = { "name", "ancestor", "attribute" }

local function luma(u)
    local part = u:IsA("BasePart") and u or u:FindFirstChildWhichIsA("BasePart", true)
    if not part then return nil end
    local c = part.Color
    return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function pivotPos(u) return u:GetPivot().Position end

function Reader.scan(root)
    local units, claimed = {}, {}
    for _, inst in ipairs(root:GetDescendants()) do
        if (inst:IsA("Model") or inst:IsA("BasePart")) and typeOf(inst) then
            local skip, p = false, inst.Parent
            while p and p ~= root do
                if claimed[p] then skip = true break end
                p = p.Parent
            end
            if not skip then
                claimed[inst] = true
                units[#units + 1] = inst
            end
        end
    end
    return units
end

local function assignColors(units)
    for _, method in ipairs(ORDER) do
        local fn, colors, w, bl, ok = NAMED[method], {}, 0, 0, true
        for i, u in ipairs(units) do
            local c = fn(u)
            if not c then ok = false break end
            colors[i] = c
            if c == 1 then w += 1 else bl += 1 end
        end
        if ok and w == 16 and bl == 16 then return colors, method end
    end
    local lumas = {}
    for i, u in ipairs(units) do
        local l = luma(u)
        if not l then return nil, "a piece has no BasePart to read a colour from" end
        lumas[i] = l
    end
    local sorted = table.clone(lumas)
    table.sort(sorted)
    if sorted[17] - sorted[16] < 0.05 then return nil, "no clean light/dark split by part colour" end
    local threshold = (sorted[16] + sorted[17]) / 2
    local colors = {}
    for i, l in ipairs(lumas) do colors[i] = l > threshold and 1 or -1 end
    return colors, "luma", threshold
end

local function squareOf(g, p)
    local rel = p - g.origin
    local fx, ry = rel:Dot(g.fileStep) / g.fileLen2, rel:Dot(g.rankStep) / g.rankLen2
    local f, r = math.floor(fx + 0.5), math.floor(ry + 0.5)
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil, "off board" end
    if math.abs(fx - f) > 0.4 or math.abs(ry - r) > 0.4 then return nil, "between squares" end
    return Chess.sqOf(f, r)
end

-- Learns piece colours and board geometry. Succeeds only at the standard starting layout.
function Reader.learn()
    local all = Reader.scan(workspace)
    local units
    if #all == 32 then
        units = all
    else
        local groups = {}
        for _, u in ipairs(all) do
            groups[u.Parent] = groups[u.Parent] or {}
            table.insert(groups[u.Parent], u)
        end
        for _, g in pairs(groups) do
            if #g == 32 then units = g break end
        end
    end
    if not units then return nil, string.format("found %d piece-like instances, need exactly 32 together", #all) end

    local colors, method, threshold = assignColors(units)
    if not colors then return nil, method end

    local by = { [1] = {}, [-1] = {} }
    for i, u in ipairs(units) do
        local t = typeOf(u)
        by[colors[i]][t] = by[colors[i]][t] or {}
        table.insert(by[colors[i]][t], u)
    end
    for _, c in ipairs({ 1, -1 }) do
        for t, n in pairs(EXPECTED) do
            if not by[c][t] or #by[c][t] ~= n then return nil, "piece counts do not match a starting position" end
        end
    end

    local wr, br = by[1][4], by[-1][4]
    local kingDir = pivotPos(by[1][6][1]) - pivotPos(by[1][5][1])
    local a1, h1 = pivotPos(wr[1]), pivotPos(wr[2])
    if (h1 - a1):Dot(kingDir) < 0 then a1, h1 = h1, a1 end
    local fileStep = (h1 - a1) / 7
    local p1, p2 = pivotPos(br[1]), pivotPos(br[2])
    local a8 = (p1:Dot(fileStep) <= p2:Dot(fileStep)) and p1 or p2
    local rankStep = (a8 - a1) / 7

    local fl, rl = fileStep.Magnitude, rankStep.Magnitude
    if fl < 0.05 or rl < 0.05 then return nil, "board axes collapsed" end
    if math.abs(fl - rl) > 0.25 * math.max(fl, rl) then return nil, "squares are not square" end
    if math.abs(fileStep:Dot(rankStep)) > 0.2 * fl * rl then return nil, "board axes are not perpendicular" end

    local geom = { origin = a1, fileStep = fileStep, rankStep = rankStep,
        fileLen2 = fileStep:Dot(fileStep), rankLen2 = rankStep:Dot(rankStep) }

    local board = {}
    for i = 1, 64 do board[i] = 0 end
    for i, u in ipairs(units) do
        local sq, why = squareOf(geom, pivotPos(u))
        if not sq or board[sq] ~= 0 then return nil, "pieces do not sit on an 8x8 lattice (" .. tostring(why or "overlap") .. ")" end
        board[sq] = colors[i] * typeOf(u)
    end
    if not Chess.sameBoard(board, START_BOARD) then
        return nil, "pieces fit the lattice but not the standard starting layout"
    end

    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position or a1
    local n = fileStep:Cross(rankStep).Unit
    if n:Dot(camPos - a1) < 0 then n = -n end
    local shift = 0
    for _, ru in ipairs({ wr[1], wr[2], br[1], br[2] }) do
        local cf, size
        if ru:IsA("Model") then cf, size = ru:GetBoundingBox() else cf, size = ru.CFrame, ru.Size end
        local half = 0.5 * (math.abs(n:Dot(cf.RightVector)) * size.X + math.abs(n:Dot(cf.UpVector)) * size.Y + math.abs(n:Dot(cf.LookVector)) * size.Z)
        shift += (cf.Position:Dot(n) - half) - pivotPos(ru):Dot(n)
    end
    geom.normal, geom.planeShift = n, shift / 4

    local container = units[1].Parent
    while container and container ~= workspace do
        local holdsAll = true
        for _, u in ipairs(units) do
            if not container:IsAncestorOf(u) then holdsAll = false break end
        end
        if holdsAll then break end
        container = container.Parent
    end
    container = container or workspace

    local nearColor = ((camPos - pivotPos(by[1][6][1])).Magnitude <= (camPos - pivotPos(by[-1][6][1])).Magnitude) and 1 or -1
    return { container = container, geom = geom, colorMethod = method, luma = threshold, nearColor = nearColor, board = board }
end

local function colorOf(u, st)
    if st.colorMethod == "luma" then
        local l = luma(u)
        return l and (l > st.luma and 1 or -1) or nil
    end
    return NAMED[st.colorMethod](u)
end

-- returns a 64-entry signed board, or nil plus a reason
function Reader.read(st)
    local container = st.container
    if not container or (container ~= workspace and not container.Parent) then return nil, "container gone" end
    local board = {}
    for i = 1, 64 do board[i] = 0 end
    for _, u in ipairs(Reader.scan(container)) do
        local t = typeOf(u)
        local color = colorOf(u, st)
        if not color then return nil, "cannot colour " .. u:GetFullName() end
        local sq, why = squareOf(st.geom, pivotPos(u))
        if sq then
            if board[sq] ~= 0 then return nil, "two pieces on one square" end
            board[sq] = color * t
        elseif why == "between squares" then
            return nil, "piece between squares"
        end
    end
    return board
end

function Reader.point(g, sq, onPlane)
    local p = g.origin + g.fileStep * Chess.fileOf(sq) + g.rankStep * Chess.rankOf(sq)
    if onPlane then p += g.normal * g.planeShift end
    return p
end

function Reader.dump(path)
    local lines, parents, n = {}, {}, 0
    for _, inst in ipairs(workspace:GetDescendants()) do
        if (inst:IsA("Model") or inst:IsA("BasePart")) and typeOf(inst) then
            n += 1
            local p = inst.Parent
            parents[p] = (parents[p] or 0) + 1
            if n <= 300 then
                local pv = pivotPos(inst)
                local attrs = {}
                for k, v in pairs(inst:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
                local l = luma(inst)
                table.insert(lines, string.format("%s | %s | pivot(%.2f, %.2f, %.2f) | luma %s | attrs: %s",
                    inst:GetFullName(), inst.ClassName, pv.X, pv.Y, pv.Z, l and string.format("%.3f", l) or "n/a", table.concat(attrs, ", ")))
            end
        end
    end
    local head = { "piece-like instances: " .. n, "parents by count:" }
    for p, c in pairs(parents) do table.insert(head, string.format("  %d  %s", c, p and p:GetFullName() or "nil")) end
    writefile(path, table.concat(head, "\n") .. "\n\n" .. table.concat(lines, "\n"))
    return n
end

return Reader