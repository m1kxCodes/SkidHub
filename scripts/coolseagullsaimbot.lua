--[[
                    .__                                          .__  .__/\            _____  .__       ___.           __
  ____  ____   ____ |  |        ______ ____ _____     ____  __ __|  | |  )/  ______   /  _  \ |__| _____\_ |__   _____/  |_
_/ ___\/  _ \ /  _ \|  |       /  ___// __ \\__  \   / ___\|  |  \  | |  |  /  ___/  /  /_\  \|  |/     \| __ \ /  _ \   __\
\  \__(  <_> |  <_> )  |__     \___ \\  ___/ / __ \_/ /_/  >  |  /  |_|  |__\___ \  /    |    \  |  Y Y  \ \_\ (  <_> )  |
 \___  >____/ \____/|____/____/____  >\___  >____  /\___  /|____/|____/____/____  > \____|__  /__|__|_|  /___  /\____/|__|
     \/                 /_____/    \/     \/     \//_____/                      \/          \/         \/    \/

    Seagull Aimbot  -  by cool_seagull
--]]

-- ============================================================================
--  SERVICES
-- ============================================================================
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService   = game:GetService("GuiService")
local Lighting     = game:GetService("Lighting")
local StarterGui   = game:GetService("StarterGui")
local HttpService  = game:GetService("HttpService")
local TextService  = game:GetService("TextService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local Camera = workspace.CurrentCamera
local inset  = GuiService:GetGuiInset()

local highlightSupported = pcall(function()
    local h = Instance.new("Highlight")
    h:Destroy()
end)

-- ============================================================================
--  CONFIG
-- ============================================================================
local Config = {
    -- aimbot
    AimEnabled         = true,
    AimKey             = Enum.KeyCode.E,
    Prediction         = true,
    PredictionStrength = 0.15,
    Smoothing          = true,
    SmoothFactor       = 0.25,
    TargetPart         = "Head",
    Priority           = "Closest to Mouse",
    AimMethod          = "Mouse Move",
    TeamCheck          = true,
    WallCheck          = false,
    -- fov
    FOVEnabled         = true,
    FOVRadius          = 130,
    ShowFOV            = true,
    -- triggerbot
    Triggerbot         = false,
    TriggerDelay       = 0.06,
    -- esp
    EspEnabled         = false,
    EspBox             = true,
    EspName            = true,
    EspHealth          = true,
    EspTracer          = false,
    EspDistance        = true,
    EspTeamColor       = true,
    EspChams           = false,
    EspMaxDistance     = 1000,
    -- movement
    Bhop               = false,
    InfiniteJump       = false,
    SpeedEnabled       = false,
    SpeedValue         = 32,
    JumpEnabled        = false,
    JumpValue          = 75,
    Fly                = false,
    FlySpeed           = 60,
    -- world
    Fullbright         = false,
    -- colors
    UIColor            = Color3.fromRGB(235, 235, 240),
    FOVColor           = Color3.fromRGB(235, 235, 240),
    EspColor           = Color3.fromRGB(235, 235, 240),
}

local bodyParts       = { "Head", "Torso", "HumanoidRootPart" }
local targetPriorities= { "Closest to Mouse", "Closest to Player", "Lowest Health" }
local aimMethods      = { "Mouse Move", "Camera Lock" }
local changingKeybind = false
local keybindBtn
local mouseButtonDown = {}  -- [Enum.UserInputType] = true while a mouse button is held
local connections = {}   -- render/step loops, disconnected on close

-- The aim key may be a keyboard KeyCode or a mouse button (UserInputType).
-- Both are EnumItems, so config (de)serialization already handles them.
local mouseAimButtons = {
    [Enum.UserInputType.MouseButton1] = true,
    [Enum.UserInputType.MouseButton2] = true,
    [Enum.UserInputType.MouseButton3] = true,
}

-- Short, readable label for a bound key/button.
local function keyName(k)
    if typeof(k) ~= "EnumItem" then return "?" end
    local n = k.Name
    if n == "MouseButton1" then return "MOUSE1"
    elseif n == "MouseButton2" then return "MOUSE2"
    elseif n == "MouseButton3" then return "MOUSE3"
    end
    return n
end

-- True while the bound aim key/button is held down.
local function isAimKeyHeld()
    local k = Config.AimKey
    if mouseAimButtons[k] then return mouseButtonDown[k] == true end
    return UIS:IsKeyDown(k)
end
local destroyAll         -- forward declared; tears everything down
local activeSlider       -- the slider currently being dragged (set by addSlider)
local activePicker       -- the color picker square/hue currently being dragged
local currentPicker      -- the color popup currently open (so we can close others)
local accentText = {}    -- text elements recolored when the UI color changes
local setUIColor         -- forward declared; recolors the UI accent live
local fovStroke          -- forward declared; FOV circle outline
local notify             -- forward declared; SetCore toast helper
local confirmDialog      -- forward declared; themed yes/no modal

-- ============================================================================
--  CONFIG SAVING  (writefile/readfile via JSON; Color3 + KeyCode serialized)
-- ============================================================================
local CONFIG_FILE = "SeagullAimbot.json"
local fileOK = (writefile and readfile and isfile) and true or false

local function serializeConfig()
    local out = {}
    for k, v in pairs(Config) do
        local ty = typeof(v)
        if ty == "Color3" then
            out[k] = { __t = "Color3", r = v.R, g = v.G, b = v.B }
        elseif ty == "EnumItem" then
            out[k] = { __t = "Enum", e = tostring(v.EnumType), n = v.Name }
        else
            out[k] = v
        end
    end
    return out
end

local function applyConfig(data)
    for k, v in pairs(data) do
        if Config[k] ~= nil then
            if type(v) == "table" and v.__t == "Color3" then
                Config[k] = Color3.new(v.r, v.g, v.b)
            elseif type(v) == "table" and v.__t == "Enum" then
                local en = tostring(v.e):gsub("Enum%.", "")
                local ok, item = pcall(function() return Enum[en][v.n] end)
                if ok and item then Config[k] = item end
            elseif type(v) == type(Config[k]) then
                Config[k] = v
            end
        end
    end
end

local function saveConfig()
    if not fileOK then return false end
    local ok, json = pcall(function() return HttpService:JSONEncode(serializeConfig()) end)
    if ok and json then
        return (pcall(function() writefile(CONFIG_FILE, json) end))
    end
    return false
end

local function loadConfig()
    if not fileOK then return false end
    local exists = false
    pcall(function() exists = isfile(CONFIG_FILE) end)
    if not exists then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
    if ok and type(data) == "table" then
        applyConfig(data)
        return true
    end
    return false
end

loadConfig()  -- apply saved settings before the UI initialises from Config
-- notify() is defined later, once the GUI (custom toast holder) exists

-- ============================================================================
--  THEME (monochrome / space + code)
-- ============================================================================
local Theme = {
    Accent      = Color3.fromRGB(235, 235, 240),
    Accent2     = Color3.fromRGB(255, 255, 255),
    BG          = Color3.fromRGB(8, 8, 10),
    Panel       = Color3.fromRGB(13, 13, 16),
    Rail        = Color3.fromRGB(11, 11, 14),
    Module      = Color3.fromRGB(20, 20, 24),
    ModuleHover = Color3.fromRGB(31, 31, 37),
    Control     = Color3.fromRGB(5, 5, 7),
    Stroke      = Color3.fromRGB(58, 58, 68),
    Text        = Color3.fromRGB(238, 238, 245),
    SubText     = Color3.fromRGB(118, 118, 132),
    On          = Color3.fromRGB(96, 96, 108),
    Off         = Color3.fromRGB(40, 40, 47),
    Knob        = Color3.fromRGB(245, 245, 250),
}

local animatedAccents = {}     -- UIGradients that flow over time

local function lighten(c, amt)
    return c:Lerp(Color3.new(1, 1, 1), amt or 0.35)
end

-- Recolor every UI accent element to a new color, live.
setUIColor = function(c)
    Theme.Accent = c
    local c2 = lighten(c)
    for _, g in ipairs(animatedAccents) do
        g.Color = ColorSequence.new(c, c2)
    end
    for _, t in ipairs(accentText) do
        pcall(function() t.TextColor3 = c end)
    end
end

-- ============================================================================
--  UI HELPERS
-- ============================================================================
local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function accentGradient(inst, rotation, animate)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(Theme.Accent, Theme.Accent2)
    g.Rotation = rotation or 0
    g.Parent = inst
    if animate ~= false then table.insert(animatedAccents, g) end
    return g
end

local function tween(inst, time, props, style, dir)
    return TweenService:Create(
        inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    ):Play()
end

-- ============================================================================
--  MAIN WINDOW
-- ============================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeagullUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = player:FindFirstChild("PlayerGui") or player.PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Size = UDim2.new(0, 560, 0, 410)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.BackgroundColor3 = Theme.BG
main.BorderSizePixel = 0
main.Parent = screenGui
corner(main, 14)
stroke(main, Theme.Stroke, 1.5, 0.2)

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = main

-- black space background with drifting stars + faint code rain
local bg = Instance.new("Frame")
bg.Name = "BG"
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Theme.BG
bg.BorderSizePixel = 0
bg.ClipsDescendants = true
bg.ZIndex = 0
bg.Parent = main
corner(bg, 14)

-- faint scrolling binary (code aesthetic)
local codeRain = Instance.new("TextLabel")
codeRain.Name = "Code"
codeRain.BackgroundTransparency = 1
codeRain.Size = UDim2.new(1, -16, 2, 0)
codeRain.Position = UDim2.new(0, 10, 0, 0)
codeRain.Font = Enum.Font.Code
codeRain.TextColor3 = Color3.fromRGB(255, 255, 255)
codeRain.TextTransparency = 0.93
codeRain.TextSize = 12
codeRain.TextXAlignment = Enum.TextXAlignment.Left
codeRain.TextYAlignment = Enum.TextYAlignment.Top
codeRain.ZIndex = 0
codeRain.Parent = bg
do
    local lines = {}
    for i = 1, 46 do
        local s = ""
        for _ = 1, 70 do s = s .. (math.random() > 0.5 and "1" or "0") end
        lines[i] = s
    end
    codeRain.Text = table.concat(lines, "\n")
end

-- starfield
local starList = {}
for i = 1, 28 do
    local sz = math.random(1, 2)
    local star = Instance.new("Frame")
    star.Size = UDim2.new(0, sz, 0, sz)
    star.Position = UDim2.new(math.random(), 0, math.random(), 0)
    star.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    star.BackgroundTransparency = math.random(40, 80) / 100
    star.BorderSizePixel = 0
    star.ZIndex = 0
    star.Parent = bg
    starList[i] = { f = star, speed = math.random(2, 9) / 100, phase = math.random() * 6.28 }
end

-- soft shadow
local shadow = Instance.new("ImageLabel")
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Size = UDim2.new(1, 50, 1, 50)
shadow.Position = UDim2.new(0.5, 0, 0.5, 6)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://6014261993"
shadow.ImageColor3 = Color3.fromRGB(255, 255, 255)
shadow.ImageTransparency = 0.6
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(49, 49, 450, 450)
shadow.ZIndex = 0
shadow.Parent = main

-- ---------------------------------------------------------------------------
--  Top bar
-- ---------------------------------------------------------------------------
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 50)
topBar.BackgroundTransparency = 1
topBar.ZIndex = 3
topBar.Parent = main

local logoDot = Instance.new("Frame")
logoDot.Size = UDim2.new(0, 10, 0, 10)
logoDot.Position = UDim2.new(0, 18, 0.5, -8)
logoDot.BackgroundColor3 = Theme.Accent
logoDot.BorderSizePixel = 0
logoDot.ZIndex = 4
logoDot.Parent = topBar
corner(logoDot, 5)
accentGradient(logoDot, 0)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 36, 0, 8)
title.Size = UDim2.new(0, 300, 0, 22)
title.Font = Enum.Font.Code
title.Text = "SEAGULL"
title.TextColor3 = Theme.Text
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 4
title.Parent = topBar

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 37, 0, 28)
subtitle.Size = UDim2.new(0, 300, 0, 14)
subtitle.Font = Enum.Font.Code
subtitle.Text = "// " .. (player.DisplayName or player.Name)
subtitle.TextColor3 = Theme.SubText
subtitle.TextSize = 11
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 4
subtitle.Parent = topBar

local function topBtn(txt, xOff, hoverColor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0.5, -14)
    b.BackgroundColor3 = Theme.Module
    b.Text = txt
    b.TextColor3 = Theme.Text
    b.Font = Enum.Font.Code
    b.TextSize = 15
    b.AutoButtonColor = false
    b.ZIndex = 4
    b.Parent = topBar
    corner(b, 8)
    b.MouseEnter:Connect(function() tween(b, 0.15, {BackgroundColor3 = hoverColor}) end)
    b.MouseLeave:Connect(function() tween(b, 0.15, {BackgroundColor3 = Theme.Module}) end)
    return b
end
local closeBtn = topBtn("X", -38, Theme.Off)
local minBtn   = topBtn("-", -74, Theme.Accent)

-- player avatar (headshot) next to the window buttons
local avatar = Instance.new("ImageLabel")
avatar.Name = "Avatar"
avatar.Size = UDim2.new(0, 30, 0, 30)
avatar.Position = UDim2.new(1, -112, 0.5, -15)
avatar.BackgroundColor3 = Theme.Module
avatar.BorderSizePixel = 0
avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=48&h=48"
avatar.ZIndex = 4
avatar.Parent = topBar
corner(avatar, 15)
stroke(avatar, Theme.Stroke, 1, 0.25)

-- animated accent line under the top bar
local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, -36, 0, 2)
accentLine.Position = UDim2.new(0, 18, 0, 50)
accentLine.BackgroundColor3 = Theme.Accent
accentLine.BorderSizePixel = 0
accentLine.ZIndex = 3
accentLine.Parent = main
corner(accentLine, 1)
accentGradient(accentLine, 0)

-- ---------------------------------------------------------------------------
--  Tab rail + content
-- ---------------------------------------------------------------------------
local rail = Instance.new("Frame")
rail.Name = "Rail"
rail.Position = UDim2.new(0, 12, 0, 62)
rail.Size = UDim2.new(0, 120, 1, -74)
rail.BackgroundColor3 = Theme.Rail
rail.BorderSizePixel = 0
rail.ZIndex = 2
rail.Parent = main
corner(rail, 10)

local railInner = Instance.new("Frame")
railInner.Name = "RailInner"
railInner.Size = UDim2.new(1, 0, 1, 0)
railInner.BackgroundTransparency = 1
railInner.ZIndex = 2
railInner.Parent = rail

local railList = Instance.new("UIListLayout")
railList.Padding = UDim.new(0, 6)
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.HorizontalAlignment = Enum.HorizontalAlignment.Center
railList.Parent = railInner
local railPad = Instance.new("UIPadding")
railPad.PaddingTop = UDim.new(0, 8)
railPad.Parent = railInner

local indicator = Instance.new("Frame")
indicator.Name = "Indicator"
indicator.Size = UDim2.new(0, 3, 0, 30)
indicator.Position = UDim2.new(0, 2, 0, 8)
indicator.BackgroundColor3 = Theme.Accent
indicator.BorderSizePixel = 0
indicator.ZIndex = 4
indicator.Parent = rail
corner(indicator, 2)
accentGradient(indicator, 90)

local contentArea = Instance.new("Frame")
contentArea.Name = "Content"
contentArea.Position = UDim2.new(0, 140, 0, 62)
contentArea.Size = UDim2.new(1, -152, 1, -74)
contentArea.BackgroundColor3 = Theme.Panel
contentArea.BorderSizePixel = 0
contentArea.ClipsDescendants = true
contentArea.ZIndex = 2
contentArea.Parent = main
corner(contentArea, 10)

-- ---------------------------------------------------------------------------
--  Custom toast notifications (bottom-right, themed, fade in/out)
-- ---------------------------------------------------------------------------
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(1, 1)
toastHolder.Position = UDim2.new(1, -16, 1, -16)
toastHolder.Size = UDim2.new(0, 280, 1, -32)
toastHolder.BackgroundTransparency = 1
toastHolder.ZIndex = 60
toastHolder.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 8)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder

local toastOrder = 0
notify = function(title, text, duration)
    duration = duration or 4
    title = tostring(title or "")
    text = tostring(text or "")
    toastOrder = toastOrder + 1

    local width, pad = 270, 10
    local bodyH = 14
    pcall(function()
        bodyH = TextService:GetTextSize(text, 13, Enum.Font.Code, Vector2.new(width - pad * 2 - 4, 400)).Y
    end)
    local height = pad + 15 + 3 + bodyH + pad

    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(0, width, 0, height)
    toast.BackgroundColor3 = Theme.Panel
    toast.BackgroundTransparency = 1
    toast.BorderSizePixel = 0
    toast.LayoutOrder = toastOrder
    toast.ZIndex = 61
    toast.Parent = toastHolder
    corner(toast, 8)
    local tStroke = stroke(toast, Theme.Stroke, 1, 1)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 1, -12)
    bar.Position = UDim2.new(0, 0, 0, 6)
    bar.BackgroundColor3 = Theme.Accent
    bar.BackgroundTransparency = 1
    bar.BorderSizePixel = 0
    bar.ZIndex = 62
    bar.Parent = toast
    corner(bar, 2)

    local titleL = Instance.new("TextLabel")
    titleL.BackgroundTransparency = 1
    titleL.Position = UDim2.new(0, pad + 4, 0, pad - 2)
    titleL.Size = UDim2.new(1, -(pad + 4) - pad, 0, 15)
    titleL.Font = Enum.Font.Code
    titleL.Text = title
    titleL.TextColor3 = Theme.Text
    titleL.TextSize = 14
    titleL.TextTransparency = 1
    titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.ZIndex = 62
    titleL.Parent = toast

    local bodyL = Instance.new("TextLabel")
    bodyL.BackgroundTransparency = 1
    bodyL.Position = UDim2.new(0, pad + 4, 0, pad + 14)
    bodyL.Size = UDim2.new(1, -(pad + 4) - pad, 0, bodyH)
    bodyL.Font = Enum.Font.Code
    bodyL.Text = text
    bodyL.TextColor3 = Theme.SubText
    bodyL.TextSize = 13
    bodyL.TextTransparency = 1
    bodyL.TextWrapped = true
    bodyL.TextXAlignment = Enum.TextXAlignment.Left
    bodyL.TextYAlignment = Enum.TextYAlignment.Top
    bodyL.ZIndex = 62
    bodyL.Parent = toast

    -- fade in
    tween(toast, 0.2, {BackgroundTransparency = 0})
    tween(tStroke, 0.2, {Transparency = 0.2})
    tween(bar, 0.2, {BackgroundTransparency = 0})
    tween(titleL, 0.2, {TextTransparency = 0})
    tween(bodyL, 0.2, {TextTransparency = 0})

    delay(duration, function()
        if not toast.Parent then return end
        tween(toast, 0.3, {BackgroundTransparency = 1})
        tween(tStroke, 0.3, {Transparency = 1})
        tween(bar, 0.3, {BackgroundTransparency = 1})
        tween(titleL, 0.3, {TextTransparency = 1})
        tween(bodyL, 0.3, {TextTransparency = 1})
        delay(0.32, function() toast:Destroy() end)
    end)
end

-- ---------------------------------------------------------------------------
--  Confirmation modal (dimmed backdrop + Yes / No)
-- ---------------------------------------------------------------------------
confirmDialog = function(message, onYes, onNo)
    local dim = Instance.new("Frame")
    dim.Name = "Confirm"
    dim.Size = UDim2.new(1, 0, 1, 0)
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.ZIndex = 80
    dim.Parent = screenGui

    -- swallow clicks on the backdrop so the UI behind can't be interacted with
    local blocker = Instance.new("TextButton")
    blocker.Size = UDim2.new(1, 0, 1, 0)
    blocker.BackgroundTransparency = 1
    blocker.Text = ""
    blocker.AutoButtonColor = false
    blocker.ZIndex = 80
    blocker.Parent = dim

    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.new(0, 340, 0, 160)
    panel.BackgroundColor3 = Theme.Panel
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.ZIndex = 81
    panel.Parent = dim
    corner(panel, 12)
    local pStroke = stroke(panel, Theme.Stroke, 1.5, 1)

    local titleL = Instance.new("TextLabel")
    titleL.BackgroundTransparency = 1
    titleL.Position = UDim2.new(0, 18, 0, 16)
    titleL.Size = UDim2.new(1, -36, 0, 18)
    titleL.Font = Enum.Font.Code
    titleL.Text = "CONFIRM"
    titleL.TextColor3 = Theme.Accent
    titleL.TextSize = 14
    titleL.TextTransparency = 1
    titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.ZIndex = 82
    titleL.Parent = panel
    table.insert(accentText, titleL)

    local msgL = Instance.new("TextLabel")
    msgL.BackgroundTransparency = 1
    msgL.Position = UDim2.new(0, 18, 0, 42)
    msgL.Size = UDim2.new(1, -36, 0, 60)
    msgL.Font = Enum.Font.Code
    msgL.Text = message
    msgL.TextColor3 = Theme.Text
    msgL.TextSize = 13
    msgL.TextTransparency = 1
    msgL.TextWrapped = true
    msgL.TextXAlignment = Enum.TextXAlignment.Left
    msgL.TextYAlignment = Enum.TextYAlignment.Top
    msgL.ZIndex = 82
    msgL.Parent = panel

    local function mkBtn(txt, xScale, isPrimary)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(xScale, 1)
        b.Position = UDim2.new(xScale, xScale == 0 and 18 or -18, 1, -16)
        b.Size = UDim2.new(0.5, -26, 0, 32)
        b.BackgroundColor3 = isPrimary and Theme.Module or Theme.Control
        b.AutoButtonColor = false
        b.Font = Enum.Font.Code
        b.Text = txt
        b.TextColor3 = isPrimary and Theme.Accent or Theme.SubText
        b.TextSize = 13
        b.TextTransparency = 1
        b.BackgroundTransparency = 1
        b.ZIndex = 82
        b.Parent = panel
        corner(b, 8)
        local s = stroke(b, Theme.Stroke, 1, 1)
        b.MouseEnter:Connect(function() tween(b, 0.15, {BackgroundColor3 = Theme.ModuleHover}) end)
        b.MouseLeave:Connect(function() tween(b, 0.15, {BackgroundColor3 = isPrimary and Theme.Module or Theme.Control}) end)
        if isPrimary then table.insert(accentText, b) end
        return b, s
    end
    local yesBtn, yesStroke = mkBtn("YES", 0, true)
    local noBtn,  noStroke  = mkBtn("NO", 1, false)

    -- fade in
    tween(dim, 0.2, {BackgroundTransparency = 0.45})
    tween(panel, 0.2, {BackgroundTransparency = 0})
    tween(pStroke, 0.2, {Transparency = 0.15})
    tween(titleL, 0.2, {TextTransparency = 0})
    tween(msgL, 0.2, {TextTransparency = 0})
    for _, b in ipairs({yesBtn, noBtn}) do tween(b, 0.2, {BackgroundTransparency = 0, TextTransparency = 0}) end
    tween(yesStroke, 0.2, {Transparency = 0.4})
    tween(noStroke, 0.2, {Transparency = 0.4})

    local done = false
    local function close(cb)
        if done then return end
        done = true
        tween(dim, 0.2, {BackgroundTransparency = 1})
        tween(panel, 0.2, {BackgroundTransparency = 1})
        tween(pStroke, 0.2, {Transparency = 1})
        delay(0.22, function() dim:Destroy() end)
        if cb then cb() end
    end
    yesBtn.MouseButton1Click:Connect(function() close(onYes) end)
    noBtn.MouseButton1Click:Connect(function() close(onNo) end)
end

-- ---------------------------------------------------------------------------
--  Tab / control library
-- ---------------------------------------------------------------------------
local tabs = {}
local currentTab
local tabOrder = 0

local function selectTab(tab)
    if currentTab == tab then return end
    for _, t in ipairs(tabs) do
        local active = (t == tab)
        t.page.Visible = active
        tween(t.label, 0.15, {TextColor3 = active and Theme.Text or Theme.SubText})
        tween(t.btn, 0.15, {BackgroundColor3 = active and Theme.Module or Theme.Rail})
    end
    -- indicator aligns with the selected button (list layout: top=8, step=36)
    tween(indicator, 0.2, {Position = UDim2.new(0, 2, 0, 8 + (tab.order - 1) * 36)})
    -- slide page in
    tab.page.Position = UDim2.new(0, 14, 0, 0)
    tween(tab.page, 0.22, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Quint)
    currentTab = tab
end

local function makeTab(name)
    tabOrder = tabOrder + 1

    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(1, -12, 0, 30)
    btn.BackgroundColor3 = Theme.Rail
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.LayoutOrder = tabOrder
    btn.ZIndex = 3
    btn.Parent = railInner
    corner(btn, 8)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -10, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Font = Enum.Font.Code
    label.Text = name
    label.TextColor3 = Theme.SubText
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4
    label.Parent = btn

    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Theme.Accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false
    page.ZIndex = 2
    page.Parent = contentArea

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)

    local tab = { btn = btn, label = label, page = page, order = tabOrder }
    btn.MouseButton1Click:Connect(function() selectTab(tab) end)
    btn.MouseEnter:Connect(function()
        if currentTab ~= tab then tween(btn, 0.15, {BackgroundColor3 = Theme.Module}) end
    end)
    btn.MouseLeave:Connect(function()
        if currentTab ~= tab then tween(btn, 0.15, {BackgroundColor3 = Theme.Rail}) end
    end)
    table.insert(tabs, tab)

    -- ---- control factories ------------------------------------------------
    local function newRow(h)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, h or 34)
        row.BackgroundColor3 = Theme.Module
        row.BorderSizePixel = 0
        row.ZIndex = 2
        row.Parent = page
        corner(row, 8)
        return row
    end

    local function rowLabel(row)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.Size = UDim2.new(1, -150, 1, 0)
        lbl.Font = Enum.Font.Code
        lbl.TextColor3 = Theme.Text
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 3
        lbl.Parent = row
        return lbl
    end

    local function hoverable(row)
        row.MouseEnter:Connect(function() tween(row, 0.15, {BackgroundColor3 = Theme.ModuleHover}) end)
        row.MouseLeave:Connect(function() tween(row, 0.15, {BackgroundColor3 = Theme.Module}) end)
    end

    function tab:addHeader(text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 22)
        row.BackgroundTransparency = 1
        row.ZIndex = 2
        row.Parent = page
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, -8, 1, 0)
        lbl.Position = UDim2.new(0, 4, 0, 0)
        lbl.Font = Enum.Font.Code
        lbl.Text = string.upper(text)
        lbl.TextColor3 = Theme.Accent
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 3
        lbl.Parent = row
        table.insert(accentText, lbl)
    end

    function tab:addToggle(text, key, callback)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text
        local on = Config[key]

        local track = Instance.new("TextButton")
        track.AnchorPoint = Vector2.new(1, 0.5)
        track.Position = UDim2.new(1, -12, 0.5, 0)
        track.Size = UDim2.new(0, 42, 0, 22)
        track.BackgroundColor3 = on and Theme.On or Theme.Off
        track.AutoButtonColor = false
        track.Text = ""
        track.ZIndex = 3
        track.Parent = row
        corner(track, 11)

        local knob = Instance.new("Frame")
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Size = UDim2.new(0, 17, 0, 17)
        knob.Position = on and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)
        knob.BackgroundColor3 = Theme.Knob
        knob.BorderSizePixel = 0
        knob.ZIndex = 4
        knob.Parent = track
        corner(knob, 9)

        track.MouseButton1Click:Connect(function()
            on = not on
            Config[key] = on
            tween(track, 0.15, {BackgroundColor3 = on and Theme.On or Theme.Off})
            tween(knob, 0.18, {Position = on and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)})
            if callback then callback(on) end
        end)
    end

    function tab:addSlider(text, key, minV, maxV, dec, suffix)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text

        local valLabel = Instance.new("TextLabel")
        valLabel.AnchorPoint = Vector2.new(1, 0.5)
        valLabel.BackgroundTransparency = 1
        valLabel.Size = UDim2.new(0, 42, 1, 0)
        valLabel.Position = UDim2.new(1, -12, 0.5, 0)
        valLabel.Font = Enum.Font.Code
        valLabel.TextColor3 = Theme.Accent
        valLabel.TextSize = 12
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.ZIndex = 3
        valLabel.Parent = row
        table.insert(accentText, valLabel)

        local track = Instance.new("Frame")
        track.AnchorPoint = Vector2.new(1, 0.5)
        track.Size = UDim2.new(0, 96, 0, 6)
        track.Position = UDim2.new(1, -58, 0.5, 0)
        track.BackgroundColor3 = Theme.Control
        track.BorderSizePixel = 0
        track.ZIndex = 3
        track.Parent = row
        corner(track, 3)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Theme.Accent
        fill.BorderSizePixel = 0
        fill.ZIndex = 3
        fill.Parent = track
        corner(fill, 3)
        accentGradient(fill, 0)

        local knob = Instance.new("Frame")
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Size = UDim2.new(0, 12, 0, 12)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.BackgroundColor3 = Theme.Knob
        knob.BorderSizePixel = 0
        knob.ZIndex = 4
        knob.Parent = track
        corner(knob, 6)

        local function apply(v)
            v = math.clamp(v, minV, maxV)
            Config[key] = v
            local a = (v - minV) / (maxV - minV)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
            valLabel.Text = string.format("%." .. dec .. "f", v) .. (suffix or "")
        end
        apply(Config[key])

        local function setFromX(px)
            local a = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            apply(minV + (maxV - minV) * a)
        end
        local function beginDrag(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                activeSlider = setFromX
                setFromX(input.Position.X)
            end
        end
        track.InputBegan:Connect(beginDrag)
        knob.InputBegan:Connect(beginDrag)
    end

    function tab:addCycle(text, key, optionsList)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text

        local btnC = Instance.new("TextButton")
        btnC.AnchorPoint = Vector2.new(1, 0.5)
        btnC.Position = UDim2.new(1, -12, 0.5, 0)
        btnC.Size = UDim2.new(0, 132, 0, 26)
        btnC.BackgroundColor3 = Theme.Control
        btnC.AutoButtonColor = false
        btnC.Font = Enum.Font.Code
        btnC.TextColor3 = Theme.Accent
        btnC.TextSize = 12
        btnC.Text = Config[key]
        btnC.ZIndex = 3
        btnC.Parent = row
        corner(btnC, 7)
        stroke(btnC, Theme.Stroke, 1, 0.4)

        table.insert(accentText, btnC)
        local idx = 1
        for i, v in ipairs(optionsList) do if v == Config[key] then idx = i end end
        btnC.MouseButton1Click:Connect(function()
            idx = (idx % #optionsList) + 1
            Config[key] = optionsList[idx]
            btnC.Text = optionsList[idx]
        end)
    end

    function tab:addKeybind(text, key)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text

        local btnK = Instance.new("TextButton")
        btnK.AnchorPoint = Vector2.new(1, 0.5)
        btnK.Position = UDim2.new(1, -12, 0.5, 0)
        btnK.Size = UDim2.new(0, 96, 0, 26)
        btnK.BackgroundColor3 = Theme.Control
        btnK.AutoButtonColor = false
        btnK.Font = Enum.Font.Code
        btnK.TextColor3 = Theme.Accent
        btnK.TextSize = 12
        btnK.Text = "[ " .. keyName(Config[key]) .. " ]"
        btnK.ZIndex = 3
        btnK.Parent = row
        corner(btnK, 7)
        stroke(btnK, Theme.Stroke, 1, 0.4)

        btnK.MouseButton1Click:Connect(function()
            changingKeybind = true
            btnK.Text = "[ ... ]"
            btnK.TextColor3 = Theme.On
        end)
        keybindBtn = btnK
    end

    function tab:addButton(text, btnText, callback)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text

        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -12, 0.5, 0)
        b.Size = UDim2.new(0, 96, 0, 26)
        b.BackgroundColor3 = Theme.Control
        b.AutoButtonColor = false
        b.Font = Enum.Font.Code
        b.TextColor3 = Theme.Accent
        b.TextSize = 12
        b.Text = btnText or "RUN"
        b.ZIndex = 3
        b.Parent = row
        corner(b, 7)
        stroke(b, Theme.Stroke, 1, 0.4)
        table.insert(accentText, b)
        b.MouseButton1Click:Connect(function()
            tween(b, 0.1, {BackgroundColor3 = Theme.ModuleHover})
            delay(0.12, function() tween(b, 0.1, {BackgroundColor3 = Theme.Control}) end)
            if callback then callback() end
        end)
    end

    function tab:addColorPicker(text, key, onChange)
        local row = newRow()
        hoverable(row)
        rowLabel(row).Text = text

        local swatch = Instance.new("TextButton")
        swatch.AnchorPoint = Vector2.new(1, 0.5)
        swatch.Position = UDim2.new(1, -12, 0.5, 0)
        swatch.Size = UDim2.new(0, 44, 0, 22)
        swatch.AutoButtonColor = false
        swatch.Text = ""
        swatch.BackgroundColor3 = Config[key]
        swatch.ZIndex = 3
        swatch.Parent = row
        corner(swatch, 6)
        stroke(swatch, Theme.Stroke, 1, 0.3)

        -- popup parented to main so the scrolling page can't clip it
        local pop = Instance.new("Frame")
        pop.Size = UDim2.new(0, 192, 0, 140)
        pop.BackgroundColor3 = Theme.Panel
        pop.BorderSizePixel = 0
        pop.Visible = false
        pop.ZIndex = 20
        pop.Parent = main
        corner(pop, 8)
        stroke(pop, Theme.Stroke, 1, 0.15)

        -- saturation / value square
        local sv = Instance.new("Frame")
        sv.Position = UDim2.new(0, 12, 0, 12)
        sv.Size = UDim2.new(0, 140, 0, 116)
        sv.BorderSizePixel = 0
        sv.ZIndex = 21
        sv.Parent = pop
        corner(sv, 6)
        local whiteOv = Instance.new("Frame")
        whiteOv.Size = UDim2.new(1, 0, 1, 0)
        whiteOv.BackgroundColor3 = Color3.new(1, 1, 1)
        whiteOv.BorderSizePixel = 0
        whiteOv.ZIndex = 21
        whiteOv.Parent = sv
        corner(whiteOv, 6)
        local whiteGrad = Instance.new("UIGradient")
        whiteGrad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
        })
        whiteGrad.Parent = whiteOv
        local blackOv = Instance.new("Frame")
        blackOv.Size = UDim2.new(1, 0, 1, 0)
        blackOv.BackgroundColor3 = Color3.new(0, 0, 0)
        blackOv.BorderSizePixel = 0
        blackOv.ZIndex = 21
        blackOv.Parent = sv
        corner(blackOv, 6)
        local blackGrad = Instance.new("UIGradient")
        blackGrad.Rotation = 90
        blackGrad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
        })
        blackGrad.Parent = blackOv
        local svDot = Instance.new("Frame")
        svDot.Size = UDim2.new(0, 8, 0, 8)
        svDot.AnchorPoint = Vector2.new(0.5, 0.5)
        svDot.BackgroundColor3 = Color3.new(1, 1, 1)
        svDot.BorderSizePixel = 0
        svDot.ZIndex = 23
        svDot.Parent = sv
        corner(svDot, 4)
        stroke(svDot, Color3.new(0, 0, 0), 1, 0)

        -- hue bar
        local hueBar = Instance.new("Frame")
        hueBar.Position = UDim2.new(0, 162, 0, 12)
        hueBar.Size = UDim2.new(0, 18, 0, 116)
        hueBar.BorderSizePixel = 0
        hueBar.ZIndex = 21
        hueBar.Parent = pop
        corner(hueBar, 4)
        local hueGrad = Instance.new("UIGradient")
        hueGrad.Rotation = 90
        hueGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
        })
        hueGrad.Parent = hueBar
        local hueDot = Instance.new("Frame")
        hueDot.Size = UDim2.new(1, 4, 0, 3)
        hueDot.AnchorPoint = Vector2.new(0.5, 0.5)
        hueDot.Position = UDim2.new(0.5, 0, 0, 0)
        hueDot.BackgroundColor3 = Color3.new(1, 1, 1)
        hueDot.BorderSizePixel = 0
        hueDot.ZIndex = 23
        hueDot.Parent = hueBar
        stroke(hueDot, Color3.new(0, 0, 0), 1, 0)

        local h, s, v = Config[key]:ToHSV()
        local function refresh()
            local col = Color3.fromHSV(h, s, v)
            Config[key] = col
            swatch.BackgroundColor3 = col
            sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            svDot.Position = UDim2.new(s, 0, 1 - v, 0)
            hueDot.Position = UDim2.new(0.5, 0, h, 0)
            if onChange then onChange(col) end
        end
        refresh()

        local function svFromPos(px, py)
            s = math.clamp((px - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
            v = 1 - math.clamp((py - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
            refresh()
        end
        local function hueFromPos(py)
            h = math.clamp((py - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
            refresh()
        end
        sv.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                activePicker = function(p) svFromPos(p.X, p.Y) end
                svFromPos(inp.Position.X, inp.Position.Y)
            end
        end)
        hueBar.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                activePicker = function(p) hueFromPos(p.Y) end
                hueFromPos(inp.Position.Y)
            end
        end)

        swatch.MouseButton1Click:Connect(function()
            if currentPicker and currentPicker ~= pop then currentPicker.Visible = false end
            pop.Visible = not pop.Visible
            currentPicker = pop.Visible and pop or nil
            if pop.Visible then
                local sp, mp = swatch.AbsolutePosition, main.AbsolutePosition
                pop.Position = UDim2.new(0, sp.X - mp.X - 150, 0, sp.Y - mp.Y + 26)
            end
        end)
    end

    return tab
end

-- ============================================================================
--  BUILD TABS
-- ============================================================================
local combatTab   = makeTab("Combat")
local visualsTab  = makeTab("Visuals")
local movementTab = makeTab("Movement")
local worldTab    = makeTab("World")

-- Combat -------------------------------------------------------------------
combatTab:addHeader("Aimbot")
combatTab:addToggle("Enabled", "AimEnabled")
combatTab:addKeybind("Aim Key", "AimKey")
combatTab:addCycle("Target Part", "TargetPart", bodyParts)
combatTab:addCycle("Priority", "Priority", targetPriorities)
combatTab:addCycle("Aim Method", "AimMethod", aimMethods)
combatTab:addToggle("Prediction", "Prediction")
combatTab:addSlider("Pred. Amount", "PredictionStrength", 0, 0.5, 2, "")
combatTab:addToggle("Smoothing", "Smoothing")
combatTab:addSlider("Aim Speed", "SmoothFactor", 0.05, 1, 2, "")
combatTab:addToggle("Team Check", "TeamCheck")
combatTab:addToggle("Wall Check", "WallCheck")
combatTab:addHeader("FOV")
combatTab:addToggle("FOV Limit", "FOVEnabled")
combatTab:addToggle("Show Circle", "ShowFOV")
combatTab:addSlider("Radius", "FOVRadius", 30, 500, 0, "")
combatTab:addColorPicker("FOV Color", "FOVColor")
combatTab:addHeader("Triggerbot")
combatTab:addToggle("Enabled", "Triggerbot")
combatTab:addSlider("Delay", "TriggerDelay", 0, 0.5, 2, "s")

-- Visuals ------------------------------------------------------------------
visualsTab:addHeader("ESP")
visualsTab:addToggle("Enabled", "EspEnabled")
visualsTab:addToggle("Boxes", "EspBox")
visualsTab:addToggle("Names", "EspName")
visualsTab:addToggle("Health Bars", "EspHealth")
visualsTab:addToggle("Distance", "EspDistance")
visualsTab:addToggle("Tracers", "EspTracer")
visualsTab:addToggle("Team Color", "EspTeamColor")
if highlightSupported then
    visualsTab:addToggle("Chams", "EspChams")
end
visualsTab:addSlider("Max Distance", "EspMaxDistance", 100, 5000, 0, "")
visualsTab:addColorPicker("ESP Color", "EspColor")

-- Movement -----------------------------------------------------------------
movementTab:addHeader("Jump")
movementTab:addToggle("Bunny Hop", "Bhop")
movementTab:addToggle("Infinite Jump", "InfiniteJump")
movementTab:addToggle("Jump Power", "JumpEnabled")
movementTab:addSlider("Power", "JumpValue", 50, 300, 0, "")
movementTab:addHeader("Speed")
movementTab:addToggle("Walk Speed", "SpeedEnabled")
movementTab:addSlider("Speed", "SpeedValue", 16, 200, 0, "")
movementTab:addHeader("Fly")
movementTab:addToggle("Enabled", "Fly")
movementTab:addSlider("Fly Speed", "FlySpeed", 20, 250, 0, "")

-- World --------------------------------------------------------------------
worldTab:addHeader("Lighting")
worldTab:addToggle("Fullbright", "Fullbright")
worldTab:addHeader("Interface")
worldTab:addColorPicker("UI Color", "UIColor", setUIColor)
worldTab:addHeader("Config")
worldTab:addButton("Save Settings", "SAVE", function()
    notify("Seagull", saveConfig() and "Config saved" or "Saving not supported", 4)
end)
worldTab:addButton("Reset Settings", "RESET", function()
    if fileOK and delfile then pcall(function() delfile(CONFIG_FILE) end) end
    notify("Seagull", "Config reset - re-execute to load defaults", 5)
end)

selectTab(combatTab)
setUIColor(Config.UIColor)

if fileOK then
    notify("Seagull", "Config loaded - auto-saves on close", 4)
end

-- ============================================================================
--  WINDOW BEHAVIOUR (drag / min / close / open-close anim)
-- ============================================================================
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    rail.Visible = not minimized
    contentArea.Visible = not minimized
    accentLine.Visible = not minimized
    tween(main, 0.25, {Size = minimized and UDim2.new(0, 560, 0, 50) or UDim2.new(0, 560, 0, 410)})
end)

local menuOpen = true
local function setMenu(open)
    menuOpen = open
    if open then main.Visible = true end
    tween(uiScale, 0.25, {Scale = open and 1 or 0},
        Enum.EasingStyle.Back, open and Enum.EasingDirection.Out or Enum.EasingDirection.In)
    if not open then
        delay(0.25, function() if not menuOpen then main.Visible = false end end)
    end
end

-- Close just hides the UI - all logic (aimbot, ESP, movement, etc.) keeps
-- running. Right Shift / Insert reopens it.
closeBtn.MouseButton1Click:Connect(function()
    setMenu(false)
    pcall(saveConfig)
    notify("SEAGULL", "Press Right Shift to reopen!", 5)
end)

local dragging, dragStart, startPos
topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        if dragging then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                      startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
        if activeSlider then activeSlider(input.Position.X) end
        if activePicker then activePicker(input.Position) end
    end
end)
UIS.InputEnded:Connect(function(input)
    if mouseAimButtons[input.UserInputType] then
        mouseButtonDown[input.UserInputType] = nil
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        activeSlider = nil
        activePicker = nil
    end
end)

-- ============================================================================
--  FOV CIRCLE
-- ============================================================================
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FOV"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.ZIndex = 1
fovCircle.Parent = screenGui
corner(fovCircle, 1000)
fovStroke = Instance.new("UIStroke")
fovStroke.Color = Config.FOVColor
fovStroke.Thickness = 1.5
fovStroke.Transparency = 0.2
fovStroke.Parent = fovCircle

-- ============================================================================
--  TARGETING HELPERS
-- ============================================================================
local function getHumanoid(character)
    return character:FindFirstChildWhichIsA("Humanoid")
end

local function getRoot(character)
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
end

local function getAimPart(character)
    return character:FindFirstChild(Config.TargetPart)
        or character:FindFirstChild("Head")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

local function isAlive(plr)
    local char = plr.Character
    if not char then return false end
    local hum = getHumanoid(char)
    if not hum or hum.Health <= 0 then return false end
    if char:FindFirstChildOfClass("ForceField") then return false end
    return true
end

local function isFriendly(plr)
    if not Config.TeamCheck then return false end
    if plr.Neutral then return false end
    return plr.Team ~= nil and plr.Team == player.Team
end

local function isVisible(character, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter = { Camera }
    if player.Character then table.insert(filter, player.Character) end
    params.FilterDescendantsInstances = filter
    local origin = Camera.CFrame.Position
    local result = workspace:Raycast(origin, part.Position - origin, params)
    return (not result) or result.Instance:IsDescendantOf(character)
end

local function evaluate(plr, mousePos, radius)
    if plr == player or not isAlive(plr) or isFriendly(plr) then return nil end
    local char = plr.Character
    local part = getAimPart(char)
    if not part then return nil end
    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil end
    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
    if Config.FOVEnabled and dist > radius then return nil end
    if Config.WallCheck and not isVisible(char, part) then return nil end
    return part, dist
end

local function getTarget()
    local mousePos = UIS:GetMouseLocation()
    local best, bestValue = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        local part, dist = evaluate(plr, mousePos, Config.FOVRadius)
        if part then
            local value
            if Config.Priority == "Closest to Player" then
                value = (Camera.CFrame.Position - part.Position).Magnitude
            elseif Config.Priority == "Lowest Health" then
                local hum = getHumanoid(plr.Character)
                value = hum and hum.Health or math.huge
            else
                value = dist
            end
            if value < bestValue then
                bestValue = value
                best = plr
            end
        end
    end
    return best
end

-- ============================================================================
--  AIMBOT
-- ============================================================================
local ZERO3 = Vector3.new()

-- Where to aim: the part's position plus a velocity look-ahead. The whole
-- assembly shares one velocity, but some rigs report ~0 on the head, so we
-- fall back to the root part's velocity when the chosen part reads still.
local function getAimPosition(part, character)
    if not Config.Prediction then return part.Position end
    local vel = part.AssemblyLinearVelocity
    if not vel or vel.Magnitude < 0.05 then
        local root = character and getRoot(character)
        vel = root and (root.AssemblyLinearVelocity or root.Velocity) or ZERO3
    end
    return part.Position + vel * Config.PredictionStrength
end

-- Executor mouse-movement primitives (present on most injectors).
local mouseMoveRel = mousemoverel
local mouseMoveAbs = mousemoveabs
local canMoveMouse = (mouseMoveRel ~= nil) or (mouseMoveAbs ~= nil)
if not canMoveMouse then
    warn("[Seagull] mousemoverel/abs unavailable - falling back to camera lock")
end

local function smoothAlpha(dt)
    return Config.Smoothing and math.clamp(Config.SmoothFactor * dt * 60, 0, 1) or 1
end

-- Mouse-move aim: smartly nudge the real cursor toward the target's on-screen
-- position. Roblox turns that cursor delta into camera rotation (locked mouse)
-- or slides the pointer onto the target (free mouse), so it respects the game's
-- own sensitivity and never fights a scripted camera. Eases each frame and
-- converges, with a small dead-zone to kill micro-jitter.
local function aimWithMouse(worldPos, dt)
    local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
    if not onScreen then return end
    local cur = UIS:GetMouseLocation()
    local dx = (screenPos.X - cur.X) * smoothAlpha(dt)
    local dy = (screenPos.Y - cur.Y) * smoothAlpha(dt)
    if math.abs(dx) < 0.15 and math.abs(dy) < 0.15 then return end
    if mouseMoveRel then
        mouseMoveRel(dx, dy)
    else
        -- absolute path needs the topbar inset added back
        mouseMoveAbs(cur.X + dx, cur.Y + dy + inset.Y)
    end
end

-- Camera-lock aim: interpolate the look *direction* (no roll) and rebuild with
-- world-up. Framerate-independent ease. Used when mouse-move isn't available
-- or the user picks "Camera Lock".
local function aimWithCamera(worldPos, dt)
    local origin = Camera.CFrame.Position
    local goalDir = worldPos - origin
    if goalDir.Magnitude < 1e-4 then return end
    goalDir = goalDir.Unit
    if Config.Smoothing then
        local newDir = Camera.CFrame.LookVector:Lerp(goalDir, smoothAlpha(dt))
        if newDir.Magnitude > 1e-4 then
            Camera.CFrame = CFrame.new(origin, origin + newDir.Unit)
        end
    else
        Camera.CFrame = CFrame.new(origin, origin + goalDir)
    end
end

local currentTarget = nil
-- A target stays locked while it's still alive and inside an enlarged FOV
-- (hysteresis), so the aim doesn't flicker between players; only when it falls
-- out do we re-pick the best target.
local function stillLockable(plr)
    return plr ~= nil and evaluate(plr, UIS:GetMouseLocation(), Config.FOVRadius * 1.4) ~= nil
end

local function updateAimbot(dt)
    if not (Config.AimEnabled and not changingKeybind and isAimKeyHeld()) then
        currentTarget = nil
        return
    end
    if not stillLockable(currentTarget) then
        currentTarget = getTarget()
    end
    local char = currentTarget and currentTarget.Character
    if char then
        local part = getAimPart(char)
        if part then
            local aimPos = getAimPosition(part, char)
            if canMoveMouse and Config.AimMethod == "Mouse Move" then
                aimWithMouse(aimPos, dt)
            else
                aimWithCamera(aimPos, dt)
            end
        end
    end
end

-- ============================================================================
--  TRIGGERBOT
-- ============================================================================
local lastTrigger = 0
-- Raycast straight out of the camera (crosshair direction). Works in first and
-- third person and follows the aimbot, unlike the raw mouse cursor.
local function triggerTarget()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local filter = { Camera }
    if player.Character then table.insert(filter, player.Character) end
    params.FilterDescendantsInstances = filter
    local res = workspace:Raycast(Camera.CFrame.Position, Camera.CFrame.LookVector * 5000, params)
    if not res then return nil end
    local model = res.Instance:FindFirstAncestorWhichIsA("Model")
    return model and Players:GetPlayerFromCharacter(model)
end

local function updateTriggerbot()
    if not Config.Triggerbot then return end
    if tick() - lastTrigger < Config.TriggerDelay then return end
    local plr = triggerTarget()
    if plr and plr ~= player and isAlive(plr) and not isFriendly(plr) then
        lastTrigger = tick()
        if mouse1click then
            mouse1click()
        elseif mouse1press and mouse1release then
            mouse1press(); wait(); mouse1release()
        end
    end
end

-- ============================================================================
--  ESP
-- ============================================================================
local drawingOK = pcall(function()
    local t = Drawing.new("Square")
    t:Remove()
end)
if not drawingOK then
    warn("[Seagull] Drawing API not available on this executor - ESP disabled")
end

-- holder in DataModel for Highlight chams (Drawing objects live outside the GUI)
local espHolder = Instance.new("Folder")
espHolder.Name = "SeagullEsp"
pcall(function() espHolder.Parent = game:GetService("CoreGui") end)
if not espHolder.Parent then
    espHolder.Parent = player:FindFirstChild("PlayerGui") or player.PlayerGui
end

local espObjects = {}
local DRAW_KEYS = { "boxOutline", "box", "healthOutline", "health", "name", "dist", "tracer" }

local function newDraw(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function buildEsp(plr)
    local obj = {}
    obj.boxOutline    = newDraw("Square", { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0), Transparency = 0.7, Visible = false, ZIndex = 1 })
    obj.box           = newDraw("Square", { Thickness = 1, Filled = false, Color = Theme.Accent, Visible = false, ZIndex = 2 })
    obj.healthOutline = newDraw("Square", { Thickness = 1, Filled = true,  Color = Color3.new(0, 0, 0), Transparency = 0.7, Visible = false, ZIndex = 1 })
    obj.health        = newDraw("Square", { Thickness = 1, Filled = true,  Color = Color3.fromRGB(0, 255, 120), Visible = false, ZIndex = 2 })
    obj.name          = newDraw("Text",   { Size = 14, Center = true, Outline = true, Color = Theme.Text, Visible = false, ZIndex = 3 })
    obj.dist          = newDraw("Text",   { Size = 12, Center = true, Outline = true, Color = Theme.SubText, Visible = false, ZIndex = 3 })
    obj.tracer        = newDraw("Line",   { Thickness = 1, Color = Theme.Accent, Transparency = 0.85, Visible = false, ZIndex = 1 })
    if highlightSupported then
        local hl = Instance.new("Highlight")
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.Enabled = false
        hl.Parent = espHolder
        obj.highlight = hl
    end
    espObjects[plr] = obj
    return obj
end

local function hideEsp(obj)
    for _, k in ipairs(DRAW_KEYS) do obj[k].Visible = false end
    if obj.highlight then obj.highlight.Enabled = false end
end

local function removeEsp(plr)
    local obj = espObjects[plr]
    if obj then
        for _, k in ipairs(DRAW_KEYS) do pcall(function() obj[k]:Remove() end) end
        if obj.highlight then obj.highlight:Destroy() end
        espObjects[plr] = nil
    end
end

Players.PlayerRemoving:Connect(removeEsp)

local function updateEsp()
    if not drawingOK then return end
    if not Config.EspEnabled then
        for _, obj in pairs(espObjects) do hideEsp(obj) end
        return
    end

    local vp = Camera.ViewportSize
    local camPos = Camera.CFrame.Position

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player then
            local obj = espObjects[plr] or buildEsp(plr)
            local char = plr.Character
            local hum = char and getHumanoid(char)
            local root = char and getRoot(char)
            local ok = char and hum and hum.Health > 0 and root

            local dist = 0
            if ok then
                dist = (camPos - root.Position).Magnitude
                if Config.EspMaxDistance > 0 and dist > Config.EspMaxDistance then ok = false end
            end

            if not ok then
                hideEsp(obj)
            else
                local gotBox, cf, size = pcall(function() return char:GetBoundingBox() end)
                if not gotBox or not cf then
                    hideEsp(obj)
                else
                    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
                    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                    local front = false
                    local pts = {
                        Vector3.new( hx,  hy,  hz), Vector3.new( hx,  hy, -hz),
                        Vector3.new( hx, -hy,  hz), Vector3.new( hx, -hy, -hz),
                        Vector3.new(-hx,  hy,  hz), Vector3.new(-hx,  hy, -hz),
                        Vector3.new(-hx, -hy,  hz), Vector3.new(-hx, -hy, -hz),
                    }
                    for _, p in ipairs(pts) do
                        local world = (cf * CFrame.new(p)).Position
                        local v = Camera:WorldToViewportPoint(world)
                        if v.Z > 0 then front = true end
                        if v.X < minX then minX = v.X end
                        if v.X > maxX then maxX = v.X end
                        if v.Y < minY then minY = v.Y end
                        if v.Y > maxY then maxY = v.Y end
                    end

                    if not front then
                        hideEsp(obj)
                    else
                        local color = Config.EspColor
                        if Config.EspTeamColor and plr.Team then color = plr.TeamColor.Color end
                        local bw, bh = maxX - minX, maxY - minY
                        local cx = minX + bw / 2
                        local topLeft = Vector2.new(minX, minY)

                        -- box (colored line over a black outline for contrast)
                        local showBox = Config.EspBox
                        obj.boxOutline.Visible = showBox
                        obj.box.Visible = showBox
                        if showBox then
                            obj.boxOutline.Size = Vector2.new(bw, bh)
                            obj.boxOutline.Position = topLeft
                            obj.box.Size = Vector2.new(bw, bh)
                            obj.box.Position = topLeft
                            obj.box.Color = color
                        end

                        -- name
                        obj.name.Visible = Config.EspName
                        if Config.EspName then
                            obj.name.Text = plr.Name
                            obj.name.Color = color
                            obj.name.Position = Vector2.new(cx, minY - 16)
                        end

                        -- distance
                        obj.dist.Visible = Config.EspDistance
                        if Config.EspDistance then
                            obj.dist.Text = math.floor(dist) .. "m"
                            obj.dist.Position = Vector2.new(cx, maxY + 2)
                        end

                        -- health bar on the left edge
                        local showHp = Config.EspHealth
                        obj.healthOutline.Visible = showHp
                        obj.health.Visible = showHp
                        if showHp then
                            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            obj.healthOutline.Position = Vector2.new(minX - 7, minY - 1)
                            obj.healthOutline.Size = Vector2.new(4, bh + 2)
                            local barH = bh * frac
                            obj.health.Position = Vector2.new(minX - 6, minY + (bh - barH))
                            obj.health.Size = Vector2.new(2, barH)
                            obj.health.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 120), frac)
                        end

                        -- tracer from bottom-center of the screen
                        obj.tracer.Visible = Config.EspTracer
                        if Config.EspTracer then
                            obj.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                            obj.tracer.To = Vector2.new(cx, maxY)
                            obj.tracer.Color = color
                        end

                        -- chams (Highlight)
                        if obj.highlight then
                            obj.highlight.Enabled = Config.EspChams
                            if Config.EspChams then
                                obj.highlight.Adornee = char
                                obj.highlight.FillColor = color
                                obj.highlight.OutlineColor = color
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
--  MOVEMENT
-- ============================================================================
UIS.JumpRequest:Connect(function()
    if Config.InfiniteJump then
        local hum = player.Character and getHumanoid(player.Character)
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

local function updateBhop()
    if not Config.Bhop then return end
    local char = player.Character
    local hum = char and getHumanoid(char)
    if not hum then return end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then return end
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
end

local function updateSpeedJump()
    local char = player.Character
    local hum = char and getHumanoid(char)
    if not hum then return end
    if Config.SpeedEnabled then hum.WalkSpeed = Config.SpeedValue end
    if Config.JumpEnabled then
        pcall(function() hum.UseJumpPower = true end)
        pcall(function() hum.JumpPower = Config.JumpValue end)
    end
end

local flying = false
local flyVel = nil
local function updateFly()
    local char = player.Character
    local hum = char and getHumanoid(char)
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if Config.Fly and hum and root then
        if not flying then
            flying = true
            hum.PlatformStand = true
            flyVel = Instance.new("BodyVelocity")
            flyVel.MaxForce = Vector3.new(1, 1, 1) * 1e6
            flyVel.Velocity = Vector3.new(0, 0, 0)
            flyVel.Parent = root
        end
        local dir = Vector3.new(0, 0, 0)
        local cf = Camera.CFrame
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
        if dir.Magnitude > 0 then dir = dir.Unit end
        flyVel.Velocity = dir * Config.FlySpeed
    elseif flying then
        flying = false
        if flyVel then flyVel:Destroy(); flyVel = nil end
        if hum then hum.PlatformStand = false end
    end
end

-- ============================================================================
--  WORLD
-- ============================================================================
local fbApplied = false
local savedLighting = {}
local function updateFullbright()
    if Config.Fullbright and not fbApplied then
        fbApplied = true
        savedLighting.Brightness = Lighting.Brightness
        savedLighting.ClockTime  = Lighting.ClockTime
        savedLighting.FogEnd     = Lighting.FogEnd
        savedLighting.Ambient    = Lighting.Ambient
        Lighting.Brightness = 2
        Lighting.ClockTime  = 14
        Lighting.FogEnd     = 1e6
        Lighting.Ambient    = Color3.fromRGB(255, 255, 255)
    elseif not Config.Fullbright and fbApplied then
        fbApplied = false
        Lighting.Brightness = savedLighting.Brightness
        Lighting.ClockTime  = savedLighting.ClockTime
        Lighting.FogEnd     = savedLighting.FogEnd
        Lighting.Ambient    = savedLighting.Ambient
    end
end

-- ============================================================================
--  INPUT (menu toggle / keybind capture)
-- ============================================================================
UIS.InputBegan:Connect(function(input, gameProcessed)
    -- track held mouse buttons so they can be used as the aim key
    if mouseAimButtons[input.UserInputType] then
        mouseButtonDown[input.UserInputType] = true
    end

    if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.Insert then
        setMenu(not menuOpen)
        return
    end
    if changingKeybind then
        local bound
        if input.UserInputType == Enum.UserInputType.Keyboard then
            bound = input.KeyCode
        elseif mouseAimButtons[input.UserInputType] then
            bound = input.UserInputType
        end
        if bound then
            changingKeybind = false
            local function apply()
                Config.AimKey = bound
                if keybindBtn then
                    keybindBtn.Text = "[ " .. keyName(Config.AimKey) .. " ]"
                    keybindBtn.TextColor3 = Theme.Accent
                end
            end
            local function revert()
                if keybindBtn then
                    keybindBtn.Text = "[ " .. keyName(Config.AimKey) .. " ]"
                    keybindBtn.TextColor3 = Theme.Accent
                end
            end
            -- Left/right click double as UI/camera input, so confirm first.
            if bound == Enum.UserInputType.MouseButton1 or bound == Enum.UserInputType.MouseButton2 then
                local click = bound == Enum.UserInputType.MouseButton1 and "Left Click" or "Right Click"
                confirmDialog(
                    "Are you sure you want to put " .. bound.Name .. " (" .. click .. ") as your aim keybind?",
                    apply, revert)
            else
                apply()
            end
        end
    end
end)

-- ============================================================================
--  LOOPS
-- ============================================================================
connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
    -- Always use the live camera. Caching it once breaks aim in games that
    -- swap CurrentCamera (spectate, custom cams, respawn) - a common cause of
    -- "the aimbot doesn't work here".
    local cam = workspace.CurrentCamera
    if cam then Camera = cam end

    updateAimbot(dt)
    updateTriggerbot()
    updateEsp()

    -- FOV circle
    fovCircle.Visible = Config.ShowFOV and Config.FOVEnabled
    if fovCircle.Visible then
        local m = UIS:GetMouseLocation()
        fovStroke.Color = Config.FOVColor
        fovCircle.Size = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2)
        fovCircle.Position = UDim2.fromOffset(m.X, m.Y + inset.Y)
    end
end)

connections[#connections + 1] = RunService.Heartbeat:Connect(function()
    updateBhop()
    updateSpeedJump()
    updateFly()
    updateFullbright()
end)

-- space/code animation: drifting + twinkling stars, scrolling binary, pulsing dot
connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
    local t = tick()
    for _, st in ipairs(starList) do
        local p = st.f.Position
        local y = p.Y.Scale - st.speed * dt
        if y < 0 then y = 1 end
        st.f.Position = UDim2.new(p.X.Scale, 0, y, 0)
        st.f.BackgroundTransparency = 0.35 + 0.4 * math.abs(math.sin(t * 1.5 + st.phase))
    end
    local cy = codeRain.Position.Y.Offset - 14 * dt
    if cy < -220 then cy = 0 end
    codeRain.Position = UDim2.new(0, 10, 0, cy)

    local off = Vector2.new(math.sin(t * 0.4) * 0.3, 0)
    for _, g in ipairs(animatedAccents) do g.Offset = off end
    logoDot.BackgroundTransparency = 0.15 + 0.35 * math.abs(math.sin(t * 2))
end)

-- full teardown: stop loops, clear drawings, restore world, destroy GUI
destroyAll = function()
    pcall(saveConfig)  -- auto-save settings on close
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for plr in pairs(espObjects) do removeEsp(plr) end
    Config.Fullbright = false
    pcall(updateFullbright)
    if flyVel then pcall(function() flyVel:Destroy() end) end
    pcall(function() espHolder:Destroy() end)
    pcall(function() screenGui:Destroy() end)
end

-- ============================================================================
--  WELCOME
-- ============================================================================
notify("SEAGULL",
    "RightShift / Insert = menu  |  Hold " .. keyName(Config.AimKey) .. " = aim", 7)
