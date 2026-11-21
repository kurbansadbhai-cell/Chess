local R = ...
local Chess = R("chess")
local HttpService = game:GetService("HttpService")

local Engine = {}
local INF, MATE = 1e9, 100000
local VALUE = { 100, 320, 330, 500, 900, 0 }

local env = (type(getgenv) == "function" and getgenv()) or _G

local CENTER = {}
for sq = 1, 64 do
    local f, r = Chess.fileOf(sq), Chess.rankOf(sq)
    CENTER[sq] = (math.min(f, 7 - f) + math.min(r, 7 - r)) * 4
end

local function evaluate(pos)
    local b, score = pos.board, 0
    for sq = 1, 64 do
        local p = b[sq]
        if p ~= 0 then
            local t, c = math.abs(p), p > 0 and 1 or -1
            local v = VALUE[t]
            if t == 2 or t == 3 then
                v += CENTER[sq]
            elseif t == 1 then
                local adv = (c == 1) and Chess.rankOf(sq) or (7 - Chess.rankOf(sq))
                v += adv * 6 + math.min(Chess.fileOf(sq), 7 - Chess.fileOf(sq)) * 2
            end
            score += c * v
        end
    end
    return score * pos.turn
end

local function order(pos, moves)
    local b, keys = pos.board, {}
    for i = 1, #moves do
        local m = moves[i]
        local from, to, promo = Chess.decode(m)
        local s = 0
        if b[to] ~= 0 then s = 1000 + 10 * VALUE[math.abs(b[to])] - VALUE[math.abs(b[from])] end
        if promo ~= 0 then s += VALUE[promo] end
        keys[m] = s
    end
    table.sort(moves, function(x, y) return keys[x] > keys[y] end)
    return moves
end

local function tickCtx(ctx)
    if ctx.nodes % 4096 == 0 then
        if tick() > ctx.deadline then ctx.stopped = true end
        task.wait()
    end
end

local function quiesce(pos, alpha, beta, ctx, ply)
    ctx.nodes += 1
    tickCtx(ctx)
    if ctx.stopped then return 0 end
    local stand = evaluate(pos)
    if ply >= 14 or stand >= beta then return stand end
    if stand > alpha then alpha = stand end
    local us = pos.turn
    local moves = order(pos, pos:pseudoMoves(true))
    for i = 1, #moves do
        pos:make(moves[i])
        if not pos:kingInCheck(us) then
            local score = -quiesce(pos, -beta, -alpha, ctx, ply + 1)
            pos:unmake()
            if ctx.stopped then return 0 end
            if score >= beta then return score end
            if score > alpha then alpha = score end
        else
            pos:unmake()
        end
    end
    return alpha
end

local function negamax(pos, depth, alpha, beta, ply, ctx)
    ctx.nodes += 1
    tickCtx(ctx)
    if ctx.stopped then return 0 end
    local us = pos.turn
    local checked = pos:kingInCheck(us)
    if checked and ply < 12 then depth += 1 end
    if depth <= 0 then return quiesce(pos, alpha, beta, ctx, ply) end
    if pos.halfmove >= 100 then return 0 end
    local moves = order(pos, pos:pseudoMoves(false))
    local legal, best = 0, -INF
    for i = 1, #moves do
        pos:make(moves[i])
        if not pos:kingInCheck(us) then
            legal += 1
            local score = -negamax(pos, depth - 1, -beta, -alpha, ply + 1, ctx)
            pos:unmake()
            if ctx.stopped then return 0 end
            if score > best then best = score end
            if score > alpha then alpha = score end
            if alpha >= beta then break end
        else
            pos:unmake()
        end
    end
    if legal == 0 then return checked and (-MATE + ply) or 0 end
    return best
end

function Engine.searchLocal(pos0, maxDepth, seconds)
    local pos = pos0:clone()
    local ctx = { nodes = 0, deadline = tick() + seconds, stopped = false }
    local rootMoves = order(pos, pos:legalMoves())
    if #rootMoves == 0 then return nil end
    local best = rootMoves[1]
    for depth = 1, maxDepth do
        local alpha, bestIter, bestScore = -INF, nil, -INF
        for _, m in ipairs(rootMoves) do
            pos:make(m)
            local score = -negamax(pos, depth - 1, -INF, -alpha, 1, ctx)
            pos:unmake()
            if ctx.stopped then break end
            if score > bestScore then bestScore, bestIter = score, m end
            if score > alpha then alpha = score end
        end
        if ctx.stopped or not bestIter then break end
        best = bestIter
        for i, m in ipairs(rootMoves) do
            if m == bestIter then
                table.remove(rootMoves, i)
                table.insert(rootMoves, 1, m)
                break
            end
        end
        if bestScore > MATE - 100 then break end
    end
    return best
end

local function httpRequest(opts)
    local fn = env.request or env.http_request or (env.syn and env.syn.request)
    if fn then
        local ok, res = pcall(fn, opts)
        if ok and type(res) == "table" and (res.Success or res.StatusCode == 200) and type(res.Body) == "string" then
            return res.Body
        end
        return nil
    end
    if opts.Method == "GET" then
        local ok, body = pcall(function() return game:HttpGet(opts.Url) end)
        if ok and type(body) == "string" then return body end
    end
    return nil
end

local MOVE = "([a-h][1-8][a-h][1-8][qrbn]?)"
local PROVIDERS = {}

-- response format from memory, unverified
function PROVIDERS.stockfish_online(fen, cfg)
    local url = string.format("https://stockfish.online/api/s/v2.php?fen=%s&depth=%d",
        HttpService:UrlEncode(fen), math.min(cfg.online_depth, 15))
    local body = httpRequest({ Url = url, Method = "GET" })
    return body and string.match(body, "bestmove%s+" .. MOVE)
end

-- response format from memory, unverified
function PROVIDERS.chess_api(fen, cfg)
    local body = httpRequest({
        Url = "https://chess-api.com/v1", Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({ fen = fen, depth = math.min(cfg.online_depth, 18), variants = 1 }),
    })
    return body and string.match(body, '"move"%s*:%s*"' .. MOVE .. '"')
end

local failedUntil = {}

-- returns (move, providerName); every provider answer is checked against the legal moves
function Engine.bestMove(pos, cfg)
    if cfg.engine_mode ~= "local" then
        local fen = pos:fen()
        for _, name in ipairs(cfg.providers) do
            local fn = PROVIDERS[name]
            if fn and (failedUntil[name] or 0) < tick() then
                local ok, uci = pcall(fn, fen, cfg)
                if ok and uci then
                    local m = pos:findUci(uci)
                    if m then return m, name end
                end
                failedUntil[name] = tick() + 60
            end
        end
    end
    return Engine.searchLocal(pos, cfg.local_depth, cfg.local_seconds), "local"
end

return Engine