local HttpService = game:GetService("HttpService")

local Config = {}

Config.defaults = {
    poll_seconds = 0.15,
    stable_polls = 3,
    autoplay = false,
    arrow = true,
    side = "auto", -- "auto" | "white" | "black"
    engine_mode = "online", -- "online" (falls back to local) | "local"
    providers = { "stockfish_online", "chess_api" },
    online_depth = 12,
    local_depth = 4,
    local_seconds = 2.5,
    autoplay_min_delay = 0.4,
    autoplay_max_delay = 1.2,
    autoplay_retry = 1.5,
    autoplay_max_attempts = 3,
    input_method = "vim", -- "vim" | "executor"
    move_style = "click", -- "click" | "drag"
    click_hold = 0.04,
    drag_steps = 12,
    hotkeys = { gui = "RightShift", autoplay = "F6", arrow = "F7" },
}

function Config.load(path)
    local cfg = {}
    for k, v in pairs(Config.defaults) do
        cfg[k] = (type(v) == "table") and table.clone(v) or v
    end
    if isfile(path) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                if cfg[k] ~= nil and type(cfg[k]) == type(v) then cfg[k] = v end
            end
        end
    end
    return cfg
end

function Config.save(path, cfg)
    writefile(path, HttpService:JSONEncode(cfg))
end

return Config