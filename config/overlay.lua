local RunService = game:GetService("RunService")

local Overlay = {}
Overlay.__index = Overlay

local COLOR = Color3.fromRGB(39, 224, 107)

function Overlay.attach(sg)
    local targets = {
        function() return (type(gethui) == "function") and gethui() or nil end,
        function() return game:GetService("CoreGui") end,
        function() return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 5) end,
    }
    for _, get in ipairs(targets) do
        local ok = pcall(function()
            local p = get()
            if p then sg.Parent = p end
        end)
        if ok and sg.Parent then return true end
    end
    return false
end

local function bar(parent)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.BackgroundColor3 = COLOR
    f.BorderSizePixel = 0
    f.Visible = false
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = f
    f.Parent = parent
    return f
end

function Overlay.new()
    local self = setmetatable({ world = nil }, Overlay)
    local sg = Instance.new("ScreenGui")
    sg.Name = "RCH_Overlay"
    sg.IgnoreGuiInset = true
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 1000
    Overlay.attach(sg)
    self.gui = sg
    self.shaft, self.headA, self.headB, self.dot = bar(sg), bar(sg), bar(sg), bar(sg)
    self.conn = RunService.RenderStepped:Connect(function() self:_draw() end)
    return self
end

function Overlay:setMove(w0, w1) self.world = { w0, w1 } end
function Overlay:clear() self.world = nil end

function Overlay:_hide()
    for _, f in ipairs({ self.shaft, self.headA, self.headB, self.dot }) do f.Visible = false end
end

function Overlay:_draw()
    local w, cam = self.world, workspace.CurrentCamera
    if not w or not cam then return self:_hide() end
    local a = cam:WorldToViewportPoint(w[1])
    local b = cam:WorldToViewportPoint(w[2])
    if a.Z <= 0 or b.Z <= 0 then return self:_hide() end
    local p0, p1 = Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y)
    local d = p1 - p0
    local len = d.Magnitude
    if len < 4 then return self:_hide() end
    local dir = d.Unit
    local ang = math.deg(math.atan2(dir.Y, dir.X))
    local thick = math.clamp(len * 0.08, 4, 10)
    local head = math.clamp(len * 0.3, 14, 34)
    local shaftLen = len - head * 0.8
    local mid = p0 + dir * (shaftLen / 2)
    self.shaft.Size = UDim2.fromOffset(shaftLen, thick)
    self.shaft.Position = UDim2.fromOffset(mid.X, mid.Y)
    self.shaft.Rotation = ang
    for i, f in ipairs({ self.headA, self.headB }) do
        local a2 = ang + (i == 1 and 150 or -150)
        local v = Vector2.new(math.cos(math.rad(a2)), math.sin(math.rad(a2)))
        local c = p1 + v * (head / 2)
        f.Size = UDim2.fromOffset(head, thick)
        f.Position = UDim2.fromOffset(c.X, c.Y)
        f.Rotation = a2
        f.Visible = true
    end
    self.dot.Size = UDim2.fromOffset(thick * 2.2, thick * 2.2)
    self.dot.Position = UDim2.fromOffset(p0.X, p0.Y)
    self.shaft.Visible, self.dot.Visible = true, true
end

function Overlay:destroy()
    if self.conn then self.conn:Disconnect() end
    if self.gui then self.gui:Destroy() end
end

return Overlay