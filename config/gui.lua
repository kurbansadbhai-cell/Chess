local R = ...
local Overlay = R("overlay")
local UIS = game:GetService("UserInputService")

local Gui = {}
Gui.__index = Gui

local BG = Color3.fromRGB(24, 24, 28)
local PANEL = Color3.fromRGB(44, 44, 52)
local ON = Color3.fromRGB(39, 160, 90)
local TEXT = Color3.fromRGB(232, 232, 234)

local function mk(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props) do i[k] = v end
    i.Parent = parent
    return i
end

-- h: { autoplay, arrow, side, engine, learn, resync, dump, test, unload } callbacks
function Gui.new(h)
    local self = setmetatable({ conns = {}, lines = {}, buttons = {} }, Gui)
    local sg = mk("ScreenGui", { Name = "RCH_Panel", ResetOnSpawn = false, DisplayOrder = 1001 }, nil)
    local panel = mk("Frame", { Size = UDim2.fromOffset(250, 376), Position = UDim2.fromOffset(20, 90), BackgroundColor3 = BG, BorderSizePixel = 0, Active = true }, sg)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
    local title = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "  rochess hax", TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, panel)

    local function button(name, text, x, y, w, cb)
        local b = mk("TextButton", { Size = UDim2.fromOffset(w, 28), Position = UDim2.fromOffset(x, y), BackgroundColor3 = PANEL, Text = text, TextColor3 = TEXT, Font = Enum.Font.GothamMedium, TextSize = 13, BorderSizePixel = 0 }, panel)
        mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        table.insert(self.conns, b.MouseButton1Click:Connect(cb))
        self.buttons[name] = b
        return b
    end

    button("autoplay", "Autoplay: off", 8, 36, 114, h.autoplay)
    button("arrow", "Arrow: on", 128, 36, 114, h.arrow)
    button("side", "Side: auto", 8, 70, 114, h.side)
    button("engine", "Engine: online", 128, 70, 114, h.engine)
    button("learn", "Learn now", 8, 104, 114, h.learn)
    button("resync", "Resync", 128, 104, 114, h.resync)
    button("dump", "Dump scan", 8, 138, 114, h.dump)
    button("test", "Self-test", 128, 138, 114, h.test)
    button("unload", "Unload", 8, 172, 234, h.unload)

    self.status = mk("TextLabel", { Size = UDim2.fromOffset(234, 34), Position = UDim2.fromOffset(8, 208), BackgroundTransparency = 1, Text = "starting", TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, panel)
    self.logLabel = mk("TextLabel", { Size = UDim2.fromOffset(234, 120), Position = UDim2.fromOffset(8, 246), BackgroundColor3 = Color3.fromRGB(16, 16, 19), BorderSizePixel = 0, Text = "", TextColor3 = Color3.fromRGB(180, 180, 186), Font = Enum.Font.Code, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, panel)

    local dragging, dragStart, startPos
    table.insert(self.conns, title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))
    table.insert(self.conns, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    Overlay.attach(sg)
    self.sg = sg
    return self
end

function Gui:setToggle(name, on)
    local b = self.buttons[name]
    if not b then return end
    local label = (name == "autoplay") and "Autoplay" or "Arrow"
    b.Text = label .. ": " .. (on and "ON" or "off")
    b.BackgroundColor3 = on and ON or PANEL
end

function Gui:setSide(s) self.buttons.side.Text = "Side: " .. s end
function Gui:setEngine(s) self.buttons.engine.Text = "Engine: " .. s end
function Gui:setStatus(s) self.status.Text = s end
function Gui:setVisible(v) self.sg.Enabled = v end
function Gui:toggleVisible() self.sg.Enabled = not self.sg.Enabled end

function Gui:log(line)
    table.insert(self.lines, line)
    while #self.lines > 8 do table.remove(self.lines, 1) end
    self.logLabel.Text = table.concat(self.lines, "\n")
end

function Gui:destroy()
    for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
    self.sg:Destroy()
end

return Gui