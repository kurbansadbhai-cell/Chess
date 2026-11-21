local Chess = {}

local P, N, B, R, Q, K = 1, 2, 3, 4, 5, 6
Chess.P, Chess.N, Chess.B, Chess.R, Chess.Q, Chess.K = P, N, B, R, Q, K
Chess.START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local LETTER = { p = P, n = N, b = B, r = R, q = Q, k = K }
local SYMBOL = { [P] = "p", [N] = "n", [B] = "b", [R] = "r", [Q] = "q", [K] = "k" }

-- squares are 1..64, a1 = 1, h1 = 8, a8 = 57; pieces are signed (white +, black -)
local function fileOf(sq) return (sq - 1) % 8 end
local function rankOf(sq) return (sq - 1) // 8 end
local function sqOf(f, r) return r * 8 + f + 1 end
Chess.fileOf, Chess.rankOf, Chess.sqOf = fileOf, rankOf, sqOf

local function squareName(sq) return string.char(97 + fileOf(sq)) .. tostring(rankOf(sq) + 1) end

local KNIGHT, KING, ORTHO, DIAG = {}, {}, {}, {}
local function ray(f, r, df, dr)
    local out = {}
    f, r = f + df, r + dr
    while f >= 0 and f < 8 and r >= 0 and r < 8 do
        out[#out + 1] = sqOf(f, r)
        f, r = f + df, r + dr
    end
    return out
end
for sq = 1, 64 do
    local f, r = fileOf(sq), rankOf(sq)
    KNIGHT[sq], KING[sq], ORTHO[sq], DIAG[sq] = {}, {}, {}, {}
    for _, d in ipairs({ { 1, 2 }, { 2, 1 }, { -1, 2 }, { -2, 1 }, { 1, -2 }, { 2, -1 }, { -1, -2 }, { -2, -1 } }) do
        local nf, nr = f + d[1], r + d[2]
        if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 then table.insert(KNIGHT[sq], sqOf(nf, nr)) end
    end
    for df = -1, 1 do
        for dr = -1, 1 do
            if df ~= 0 or dr ~= 0 then
                local nf, nr = f + df, r + dr
                if nf >= 0 and nf < 8 and nr >= 0 and nr < 8 then table.insert(KING[sq], sqOf(nf, nr)) end
                local rr = ray(f, r, df, dr)
                if #rr > 0 then
                    if df == 0 or dr == 0 then table.insert(ORTHO[sq], rr) else table.insert(DIAG[sq], rr) end
                end
            end
        end
    end
end

-- castling rights bits: 1 = white kingside, 2 = white queenside, 4 = black kingside, 8 = black queenside
local CASTLE_KEEP = { [1] = 13, [8] = 14, [5] = 12, [57] = 7, [64] = 11, [61] = 3 }

local Position = {}
Position.__index = Position
Chess.Position = Position

function Chess.fromFen(fen)
    local parts = {}
    for w in string.gmatch(fen, "%S+") do parts[#parts + 1] = w end
    if #parts < 4 then return nil, "fen needs at least 4 fields" end
    local board = {}
    for i = 1, 64 do board[i] = 0 end
    local r, f = 7, 0
    for c in string.gmatch(parts[1], ".") do
        if c == "/" then
            r, f = r - 1, 0
        elseif tonumber(c) then
            f += tonumber(c)
        else
            local t = LETTER[string.lower(c)]
            if not t or f > 7 or r < 0 then return nil, "bad fen board" end
            board[sqOf(f, r)] = (c == string.upper(c)) and t or -t
            f += 1
        end
    end
    local pos = setmetatable({
        board = board, turn = parts[2] == "b" and -1 or 1, castling = 0, ep = 0,
        halfmove = tonumber(parts[5]) or 0, fullmove = tonumber(parts[6]) or 1,
        stack = {}, ksq = { [1] = 0, [-1] = 0 },
    }, Position)
    local c = parts[3]
    if string.find(c, "K", 1, true) then pos.castling += 1 end
    if string.find(c, "Q", 1, true) then pos.castling += 2 end
    if string.find(c, "k", 1, true) then pos.castling += 4 end
    if string.find(c, "q", 1, true) then pos.castling += 8 end
    if parts[4] ~= "-" and #parts[4] >= 2 then
        local ef, er = string.byte(parts[4], 1) - 97, (tonumber(string.sub(parts[4], 2, 2)) or 0) - 1
        if ef >= 0 and ef <= 7 and er >= 0 and er <= 7 then pos.ep = sqOf(ef, er) end
    end
    for sq = 1, 64 do
        if board[sq] == K then pos.ksq[1] = sq elseif board[sq] == -K then pos.ksq[-1] = sq end
    end
    if pos.ksq[1] == 0 or pos.ksq[-1] == 0 then return nil, "fen needs both kings" end
    return pos
end

function Position:clone()
    return setmetatable({
        board = table.clone(self.board), turn = self.turn, castling = self.castling, ep = self.ep,
        halfmove = self.halfmove, fullmove = self.fullmove, stack = {},
        ksq = { [1] = self.ksq[1], [-1] = self.ksq[-1] },
    }, Position)
end

function Position:attacked(sq, by)
    local b = self.board
    local f, r = fileOf(sq), rankOf(sq)
    local pr = r - by
    if pr >= 0 and pr < 8 then
        if f > 0 and b[sqOf(f - 1, pr)] == by * P then return true end
        if f < 7 and b[sqOf(f + 1, pr)] == by * P then return true end
    end
    local kn = KNIGHT[sq]
    for i = 1, #kn do if b[kn[i]] == by * N then return true end end
    local kg = KING[sq]
    for i = 1, #kg do if b[kg[i]] == by * K then return true end end
    local o = ORTHO[sq]
    for i = 1, #o do
        local rl = o[i]
        for j = 1, #rl do
            local p = b[rl[j]]
            if p ~= 0 then
                if p == by * R or p == by * Q then return true end
                break
            end
        end
    end
    local d = DIAG[sq]
    for i = 1, #d do
        local rl = d[i]
        for j = 1, #rl do
            local p = b[rl[j]]
            if p ~= 0 then
                if p == by * B or p == by * Q then return true end
                break
            end
        end
    end
    return false
end

function Position:kingInCheck(color) return self:attacked(self.ksq[color], -color) end
function Position:inCheck() return self:kingInCheck(self.turn) end

local function gen(pos, caps)
    local moves, n = {}, 0
    local b, us = pos.board, pos.turn
    local function add(from, to, promo)
        n += 1
        moves[n] = (from - 1) + (to - 1) * 64 + (promo or 0) * 4096
    end
    local function promos(from, to)
        add(from, to, Q)
        if not caps then add(from, to, R); add(from, to, B); add(from, to, N) end
    end
    local function slide(from, lists)
        for i = 1, #lists do
            local rl = lists[i]
            for j = 1, #rl do
                local to = rl[j]
                local tp = b[to]
                if tp == 0 then
                    if not caps then add(from, to) end
                else
                    if (tp > 0) ~= (us > 0) then add(from, to) end
                    break
                end
            end
        end
    end
    for from = 1, 64 do
        local p = b[from]
        if p ~= 0 and (p > 0) == (us > 0) then
            local t = p * us
            if t == P then
                local f, r = fileOf(from), rankOf(from)
                local r1 = r + us
                if r1 >= 0 and r1 <= 7 then
                    local last = (r1 == 7 or r1 == 0)
                    local to = sqOf(f, r1)
                    if b[to] == 0 then
                        if last then
                            promos(from, to)
                        elseif not caps then
                            add(from, to)
                            if r == (us == 1 and 1 or 6) and b[to + 8 * us] == 0 then add(from, to + 8 * us) end
                        end
                    end
                    for df = -1, 1, 2 do
                        local nf = f + df
                        if nf >= 0 and nf <= 7 then
                            local to2 = sqOf(nf, r1)
                            local tp = b[to2]
                            if tp ~= 0 and (tp > 0) ~= (us > 0) then
                                if last then promos(from, to2) else add(from, to2) end
                            elseif tp == 0 and to2 == pos.ep then
                                add(from, to2)
                            end
                        end
                    end
                end
            elseif t == N or t == K then
                local list = (t == N) and KNIGHT[from] or KING[from]
                for i = 1, #list do
                    local to = list[i]
                    local tp = b[to]
                    if tp == 0 then
                        if not caps then add(from, to) end
                    elseif (tp > 0) ~= (us > 0) then
                        add(from, to)
                    end
                end
                if t == K and not caps then
                    local home = (us == 1) and 5 or 61
                    if from == home then
                        local ksBit, qsBit = (us == 1) and 1 or 4, (us == 1) and 2 or 8
                        local enemy = -us
                        local checked
                        if bit32.band(pos.castling, ksBit) ~= 0 and b[home + 1] == 0 and b[home + 2] == 0 and b[home + 3] == us * R then
                            checked = pos:attacked(home, enemy)
                            if not checked and not pos:attacked(home + 1, enemy) and not pos:attacked(home + 2, enemy) then
                                add(from, home + 2)
                            end
                        end
                        if bit32.band(pos.castling, qsBit) ~= 0 and b[home - 1] == 0 and b[home - 2] == 0 and b[home - 3] == 0 and b[home - 4] == us * R then
                            if checked == nil then checked = pos:attacked(home, enemy) end
                            if not checked and not pos:attacked(home - 1, enemy) and not pos:attacked(home - 2, enemy) then
                                add(from, home - 2)
                            end
                        end
                    end
                end
            else
                if t == B or t == Q then slide(from, DIAG[from]) end
                if t == R or t == Q then slide(from, ORTHO[from]) end
            end
        end
    end
    return moves
end

function Position:pseudoMoves(caps) return gen(self, caps) end

function Chess.decode(m) return m % 64 + 1, (m // 64) % 64 + 1, m // 4096 end

function Position:make(m)
    local b, us = self.board, self.turn
    local from, to, promo = m % 64 + 1, (m // 64) % 64 + 1, m // 4096
    local piece, captured = b[from], b[to]
    local t = piece * us
    local u = { m = m, piece = piece, captured = captured, castling = self.castling, ep = self.ep, half = self.halfmove, ksq = self.ksq[us] }
    b[from] = 0
    if t == P and captured == 0 and fileOf(from) ~= fileOf(to) then
        local cs = to - 8 * us
        u.epcap = b[cs]
        b[cs] = 0
    end
    b[to] = (promo ~= 0) and promo * us or piece
    if t == K then
        self.ksq[us] = to
        if to - from == 2 then
            b[to - 1] = b[to + 1]; b[to + 1] = 0
        elseif from - to == 2 then
            b[to + 1] = b[to - 2]; b[to - 2] = 0
        end
    end
    self.castling = bit32.band(self.castling, CASTLE_KEEP[from] or 15, CASTLE_KEEP[to] or 15)
    self.ep = (t == P and math.abs(to - from) == 16) and (from + to) // 2 or 0
    self.halfmove = (t == P or captured ~= 0) and 0 or self.halfmove + 1
    if us == -1 then self.fullmove += 1 end
    self.turn = -us
    self.stack[#self.stack + 1] = u
end

function Position:unmake()
    local u = table.remove(self.stack)
    local b = self.board
    local from, to = u.m % 64 + 1, (u.m // 64) % 64 + 1
    local us = -self.turn
    self.turn = us
    b[from] = u.piece
    b[to] = u.captured
    if u.epcap then b[to - 8 * us] = u.epcap end
    if u.piece * us == K then
        self.ksq[us] = u.ksq
        if to - from == 2 then
            b[to + 1] = b[to - 1]; b[to - 1] = 0
        elseif from - to == 2 then
            b[to - 2] = b[to + 1]; b[to + 1] = 0
        end
    end
    self.castling, self.ep, self.halfmove = u.castling, u.ep, u.half
    if us == -1 then self.fullmove -= 1 end
end

function Position:legalMoves()
    local out, us = {}, self.turn
    for _, m in ipairs(gen(self, false)) do
        self:make(m)
        if not self:kingInCheck(us) then out[#out + 1] = m end
        self:unmake()
    end
    return out
end

function Position:status()
    if #self:legalMoves() == 0 then return self:inCheck() and "checkmate" or "stalemate" end
    if self.halfmove >= 100 then return "draw (fifty-move)" end
    return "ongoing"
end

function Position:fen()
    local rows = {}
    for r = 7, 0, -1 do
        local row, empty = {}, 0
        for f = 0, 7 do
            local p = self.board[sqOf(f, r)]
            if p == 0 then
                empty += 1
            else
                if empty > 0 then row[#row + 1] = tostring(empty); empty = 0 end
                local s = SYMBOL[math.abs(p)]
                row[#row + 1] = p > 0 and string.upper(s) or s
            end
        end
        if empty > 0 then row[#row + 1] = tostring(empty) end
        rows[#rows + 1] = table.concat(row)
    end
    local c = ""
    if bit32.band(self.castling, 1) ~= 0 then c ..= "K" end
    if bit32.band(self.castling, 2) ~= 0 then c ..= "Q" end
    if bit32.band(self.castling, 4) ~= 0 then c ..= "k" end
    if bit32.band(self.castling, 8) ~= 0 then c ..= "q" end
    if c == "" then c = "-" end
    return string.format("%s %s %s %s %d %d", table.concat(rows, "/"), self.turn == 1 and "w" or "b",
        c, self.ep ~= 0 and squareName(self.ep) or "-", self.halfmove, self.fullmove)
end

function Chess.moveToUci(m)
    local from, to, promo = Chess.decode(m)
    return squareName(from) .. squareName(to) .. (promo ~= 0 and SYMBOL[promo] or "")
end

function Position:findUci(uci)
    uci = string.lower(uci)
    for _, m in ipairs(self:legalMoves()) do
        if Chess.moveToUci(m) == uci then return m end
    end
    return nil
end

function Chess.sameBoard(a, b)
    for i = 1, 64 do if a[i] ~= b[i] then return false end end
    return true
end

-- finds the 1 or 2 legal plies that turn `pos` into the observed board
function Chess.matchMoves(pos, observed, maxPlies)
    local work = pos:clone()
    for _, m1 in ipairs(work:legalMoves()) do
        work:make(m1)
        local hit = Chess.sameBoard(work.board, observed)
        work:unmake()
        if hit then return { m1 } end
    end
    if (maxPlies or 2) < 2 then return nil end
    for _, m1 in ipairs(work:legalMoves()) do
        work:make(m1)
        for _, m2 in ipairs(work:legalMoves()) do
            work:make(m2)
            local hit = Chess.sameBoard(work.board, observed)
            work:unmake()
            if hit then
                work:unmake()
                return { m1, m2 }
            end
        end
        work:unmake()
    end
    return nil
end

function Chess.perft(pos, depth)
    if depth == 0 then return 1 end
    local n = 0
    for _, m in ipairs(pos:legalMoves()) do
        pos:make(m)
        n += Chess.perft(pos, depth - 1)
        pos:unmake()
    end
    return n
end

return Chess
