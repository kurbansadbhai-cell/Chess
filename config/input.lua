local Input = {}

local env = (type(getgenv) == "function" and getgenv()) or _G
local VIM
do
    local ok, v = pcall(function() return game:GetService("VirtualInputManager") end)
    if ok then VIM = v end
end

local held = nil

local function move(x, y, method)
    if method == "executor" and env.mousemoveabs then
        env.mousemoveabs(x, y)
    elseif VIM then
        VIM:SendMouseMoveEvent(x, y, game)
    end
end

local function button(x, y, down, method)
    if method == "executor" and env.mouse1press and env.mouse1release then
        if down then env.mouse1press() else env.mouse1release() end
    elseif VIM then
        VIM:SendMouseButtonEvent(x, y, 0, down, game, 0)
    end
end

local function click(p, cfg)
    local m = cfg.input_method
    move(p.X, p.Y, m)
    task.wait(0.03)
    button(p.X, p.Y, true, m)
    held = { p = p, m = m }
    pcall(task.wait, cfg.click_hold)
    button(p.X, p.Y, false, m)
    held = nil
end

local function drag(a, d, cfg)
    local m = cfg.input_method
    move(a.X, a.Y, m)
    task.wait(0.05)
    button(a.X, a.Y, true, m)
    held = { p = a, m = m }
    for i = 1, cfg.drag_steps do
        local p = a:Lerp(d, i / cfg.drag_steps)
        move(p.X, p.Y, m)
        task.wait(0.01)
    end
    task.wait(0.05)
    button(d.X, d.Y, false, m)
    held = nil
end

-- a and d are viewport-pixel Vector2s
function Input.perform(cfg, a, d)
    if cfg.move_style == "drag" then
        drag(a, d, cfg)
    else
        click(a, cfg)
        task.wait(0.12)
        click(d, cfg)
    end
end

function Input.release()
    if held then
        pcall(button, held.p.X, held.p.Y, false, held.m)
        held = nil
    end
end

return Input