local R = ...
local Chess, Config, Reader, Engine, Input, Overlay, Gui =
    R("chess"), R("config"), R("board_reader"), R("engine"), R("input"), R("overlay"), R("gui")
local UIS = game:GetService("UserInputService")

local App = {}
local START_BOARD = Chess.fromFen(Chess.START_FEN).board

local function keyCode(name)
    local ok, v = pcall(function() return Enum.KeyCode[name] end)
    return ok and v or nil
end

function App.start(opts)
    local settingsPath = opts.root .. "/settings.json"
    local cfg = Config.load(settingsPath)
    local running, busy, focused = true, false, true
    local reader, pos, synced = nil, nil, false
    local ourColor = 1
    local pending, pendingCount, processed = nil, 0, nil
    local curKey, curStatus = nil, "ongoing"
    local requestedKey, best, bestKey, arrowKey = nil, nil, nil, nil
    local dueAt, attempts, nextAttemptAt, nextLearnAt = {}, {}, 0, 0
    local conns, gui, overlay, handle = {}, nil, nil, {}
    local lastStatus = ""

    local function log(msg)
        print("[rochess hax] " .. msg)
        if gui then gui:log(msg) end
    end
    local function setStatus(s)
        if s ~= lastStatus and gui then
            lastStatus = s
            gui:setStatus(s)
        end
    end
    local function save() pcall(Config.save, settingsPath, cfg) end

    local function refreshPos()
        curKey = pos:fen()
        curStatus = pos:status()
        best, bestKey, arrowKey, requestedKey = nil, nil, nil, nil
        if overlay then overlay:clear() end
    end

    local function applySide()
        if cfg.side == "white" then ourColor = 1
        elseif cfg.side == "black" then ourColor = -1
        elseif reader then ourColor = reader.nearColor end
    end

    local function newGame()
        pos = Chess.fromFen(Chess.START_FEN)
        synced, processed = true, nil
        applySide()
        refreshPos()
        log(("new game: you are %s (piece colour read via %s)"):format(ourColor == 1 and "white" or "black", reader.colorMethod))
    end

    local function sync(board)
        if Chess.sameBoard(board, START_BOARD) then
            if not pos or #pos.stack > 0 then newGame() end
            synced = true
            return
        end
        if not pos then
            synced = false
            setStatus("waiting for a starting position")
            return
        end
        if Chess.sameBoard(board, pos.board) then
            synced = true
            return
        end
        local seq = Chess.matchMoves(pos, board, 2)
        if seq then
            for _, m in ipairs(seq) do
                log("move seen: " .. Chess.moveToUci(m))
                pos:make(m)
            end
            synced = true
            refreshPos()
            return
        end
        synced = false
        setStatus("desync: board matches no legal move (Resync, then start a fresh game)")
        if tick() >= nextLearnAt then
            nextLearnAt = tick() + 1
            local st = Reader.learn()
            if st then
                reader = st
                newGame()
            end
        end
    end

    local function request()
        if requestedKey == curKey then return end
        requestedKey = curKey
        local key, snap = curKey, pos:clone()
        task.spawn(function()
            local ok, mv, src = pcall(Engine.bestMove, snap, cfg)
            if not ok then
                log("engine error: " .. tostring(mv))
                return
            end
            if running and mv and requestedKey == key then
                best, bestKey = mv, key
                log(("best move %s (%s)"):format(Chess.moveToUci(mv), src))
            end
        end)
    end

    local function showArrow()
        if arrowKey == curKey then return end
        local from, to = Chess.decode(best)
        overlay:setMove(Reader.point(reader.geom, from, true), Reader.point(reader.geom, to, true))
        arrowKey = curKey
    end

    local function autoplayStep()
        if not focused or busy then return end
        local now = tick()
        dueAt[curKey] = dueAt[curKey] or (now + cfg.autoplay_min_delay + math.random() * (cfg.autoplay_max_delay - cfg.autoplay_min_delay))
        if now < dueAt[curKey] or now < nextAttemptAt or (attempts[curKey] or 0) >= cfg.autoplay_max_attempts then return end
        local fresh = Reader.read(reader)
        if not fresh or not Chess.sameBoard(fresh, pos.board) or pos.turn ~= ourColor then return end
        local cam = workspace.CurrentCamera
        local from, to, promo = Chess.decode(best)
        local function screen(sq, onPlane)
            local v, on = cam:WorldToViewportPoint(Reader.point(reader.geom, sq, onPlane))
            if not on or v.Z <= 0 then return nil end
            return Vector2.new(v.X, v.Y)
        end
        local a, d = screen(from, false), screen(to, true)
        if not a or not d then
            setStatus("your move: squares off screen, pan the camera")
            return
        end
        attempts[curKey] = (attempts[curKey] or 0) + 1
        nextAttemptAt = now + cfg.autoplay_retry
        busy = true
        local ok, err = pcall(Input.perform, cfg, a, d)
        Input.release()
        busy = false
        if not ok then log("input error: " .. tostring(err)) return end
        log(("played %s (attempt %d)"):format(Chess.moveToUci(best), attempts[curKey]))
        if promo ~= 0 then log("promotion: picker behaviour in RoChess is unknown, pick manually if it asks") end
    end

    local function act()
        if not synced or not pos then return end
        if curStatus ~= "ongoing" then
            setStatus("game over: " .. curStatus)
            overlay:clear()
            arrowKey = nil
            return
        end
        if pos.turn ~= ourColor then
            setStatus("opponent to move")
            overlay:clear()
            arrowKey = nil
            return
        end
        if not (cfg.arrow or cfg.autoplay) then
            setStatus("your move")
            return
        end
        request()
        if bestKey ~= curKey or not best then
            setStatus("your move: thinking")
            return
        end
        setStatus("your move: " .. Chess.moveToUci(best))
        if cfg.arrow then
            showArrow()
        elseif arrowKey then
            overlay:clear()
            arrowKey = nil
        end
        if cfg.autoplay then autoplayStep() end
    end

    local function step()
        if busy then return end
        if not reader then
            if tick() < nextLearnAt then return end
            nextLearnAt = tick() + 1
            local st, why = Reader.learn()
            if not st then
                pos, synced = nil, false
                setStatus("waiting for a start position: " .. tostring(why))
                return
            end
            reader = st
            newGame()
        end
        local board, why = Reader.read(reader)
        if not board then
            if why == "container gone" then
                reader, pos, synced = nil, nil, false
                overlay:clear()
            else
                setStatus("reading board: " .. tostring(why))
            end
            pending, pendingCount = nil, 0
            return
        end
        if pending and Chess.sameBoard(board, pending) then
            pendingCount += 1
        else
            pending, pendingCount = board, 1
        end
        if pendingCount < cfg.stable_polls then return end
        if not (processed and Chess.sameBoard(board, processed)) then
            sync(board)
            processed = synced and board or nil
        end
        act()
    end

    local function setAutoplay(on)
        cfg.autoplay = on
        if not on then Input.release() end
        gui:setToggle("autoplay", on)
        save()
        log("autoplay " .. (on and "ON" or "off"))
    end
    local function setArrow(on)
        cfg.arrow = on
        if not on then
            overlay:clear()
            arrowKey = nil
        end
        gui:setToggle("arrow", on)
        save()
    end

    local function destroy()
        if not running then return end
        running = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        Input.release()
        if overlay then overlay:destroy() end
        if gui then gui:destroy() end
        local env = (type(getgenv) == "function" and getgenv()) or _G
        if env.RochessHax == handle then env.RochessHax = nil end
    end
    handle.Destroy = destroy

    overlay = Overlay.new()
    gui = Gui.new({
        autoplay = function() setAutoplay(not cfg.autoplay) end,
        arrow = function() setArrow(not cfg.arrow) end,
        side = function()
            cfg.side = (cfg.side == "auto" and "white") or (cfg.side == "white" and "black") or "auto"
            gui:setSide(cfg.side)
            applySide()
            save()
        end,
        engine = function()
            cfg.engine_mode = (cfg.engine_mode == "online") and "local" or "online"
            gui:setEngine(cfg.engine_mode)
            requestedKey, best, bestKey = nil, nil, nil
            save()
        end,
        learn = function()
            local st, why = Reader.learn()
            if st then
                reader = st
                newGame()
            else
                log("learn failed: " .. tostring(why))
            end
        end,
        resync = function()
            pos, synced, processed = nil, false, nil
            overlay:clear()
            log("tracking cleared; waiting for a starting position")
        end,
        dump = function()
            local ok, n = pcall(Reader.dump, opts.root .. "/scan.txt")
            log(ok and (n .. " piece-like instances written to " .. opts.root .. "/scan.txt") or ("dump failed: " .. tostring(n)))
        end,
        test = function()
            task.spawn(function()
                local a = Chess.perft(Chess.fromFen(Chess.START_FEN), 3)
                local k = Chess.perft(Chess.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"), 2)
                log(("perft start d3 = %d (expect 8902); kiwipete d2 = %d (expect 2039)"):format(a, k))
            end)
        end,
        unload = destroy,
    })
    gui:setToggle("autoplay", cfg.autoplay)
    gui:setToggle("arrow", cfg.arrow)
    gui:setSide(cfg.side)
    gui:setEngine(cfg.engine_mode)

    local kGui, kAuto, kArrow = keyCode(cfg.hotkeys.gui), keyCode(cfg.hotkeys.autoplay), keyCode(cfg.hotkeys.arrow)
    table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == kGui then gui:toggleVisible()
        elseif input.KeyCode == kAuto then setAutoplay(not cfg.autoplay)
        elseif input.KeyCode == kArrow then setArrow(not cfg.arrow) end
    end))
    table.insert(conns, UIS.WindowFocused:Connect(function() focused = true end))
    table.insert(conns, UIS.WindowFocusReleased:Connect(function()
        focused = false
        Input.release()
    end))

    task.spawn(function()
        while running do
            local ok, err = pcall(step)
            if not ok then
                log("error: " .. tostring(err))
                task.wait(1)
            end
            task.wait(cfg.poll_seconds)
        end
    end)

    log("ready. RightShift hides the panel, F6 autoplay, F7 arrow. Stand at a starting position.")
    return handle
end

return App
