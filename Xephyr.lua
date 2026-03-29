local libhelper = loadstring(game:HttpGet("https://raw.githubusercontent.com/4dops/XephyrUI/refs/heads/main/ui.luau"))()

local Window = Library:Window({
    Name = "Xephyr.lua",
    FadeSpeed = 0.3
})

local aimbot   = Window:Page({Name = "aimbot",        Columns = 3})
local visuals  = Window:Page({Name = "visuals",       Columns = 2})
local misc     = Window:Page({Name = "miscellaneous", Columns = 4})
local settings = Window:Page({Name = "settings",      Columns = 3})

local Players          = game:GetService("Players")
local LocalPlayer      = Players.LocalPlayer
local RunService       = game:GetService("RunService")
local Camera           = workspace:WaitForChild("Camera")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

-- ── module resolver (twinkhook method) ────────────────────────────────────────
local require = getrenv().shared and getrenv().shared.require
if not require then warn("[xephyr] shared require not found – aborting") return end

local ReplicationInterface = require("ReplicationInterface")

-- ── chams ─────────────────────────────────────────────────────────────────────
local Chams = {
    Enabled  = false,
    Color    = Color3.fromRGB(84, 132, 171),
    Trans    = 0.5,
    OnTop    = true,
    EnemyOnly = true,
    Active   = {},   -- [entry] = {bha, bha, ...}
}

local function CreateBHA(part)
    local bha = Instance.new("BoxHandleAdornment")
    bha.Adornee      = part
    bha.Size         = part.Size
    bha.Color3       = Chams.Color
    bha.Transparency = Chams.Trans
    bha.AlwaysOnTop  = Chams.OnTop
    bha.ZIndex       = 1
    bha.Parent       = CoreGui
    return bha
end

local function ClearEntry(entry)
    local adornments = Chams.Active[entry]
    if not adornments then return end
    for _, bha in ipairs(adornments) do
        pcall(function() bha:Destroy() end)
    end
    Chams.Active[entry] = nil
end

local function ApplyEntry(entry)
    ClearEntry(entry)
    if not Chams.Enabled then return end
    if not entry:isAlive() then return end
    if Chams.EnemyOnly and not entry:isEnemy() then return end

    local charModel = entry:getThirdPersonObject() and entry:getThirdPersonObject():getCharacterModel()
    if not charModel then return end

    local adornments = {}
    for _, part in ipairs(charModel:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(adornments, CreateBHA(part))
        end
    end
    Chams.Active[entry] = adornments
end

local function UpdateProperties()
    for _, adornments in pairs(Chams.Active) do
        for _, bha in ipairs(adornments) do
            bha.Color3       = Chams.Color
            bha.Transparency = Chams.Trans
            bha.AlwaysOnTop  = Chams.OnTop
        end
    end
end

local function RefreshAll()
    -- clear everything first
    for entry in pairs(Chams.Active) do
        ClearEntry(entry)
    end
    -- re-apply to all current entries
    local entries = ReplicationInterface.getEntries and ReplicationInterface.getEntries()
                 or ReplicationInterface.entries
    if not entries then return end
    for _, entry in pairs(entries) do
        ApplyEntry(entry)
    end
end

-- hook spawned/died per entry so chams stay live without polling
local function HookEntry(entry)
    if entry._player == LocalPlayer then return end

    -- spawned
    if entry.spawned then
        entry.spawned:Connect(function()
            task.wait()          -- let the character model populate
            ApplyEntry(entry)
        end)
    end

    -- died / removed
    if entry.died then
        entry.died:Connect(function()
            ClearEntry(entry)
        end)
    end

    -- apply immediately if already alive
    if entry:isAlive() then
        ApplyEntry(entry)
    end
end

-- hook all existing entries and listen for new ones
do
    local entries = ReplicationInterface.getEntries and ReplicationInterface.getEntries()
                 or ReplicationInterface.entries
    if entries then
        for _, entry in pairs(entries) do
            HookEntry(entry)
        end
    end

    if ReplicationInterface.entryAdded then
        ReplicationInterface.entryAdded:Connect(function(entry)
            HookEntry(entry)
        end)
    end

    if ReplicationInterface.entryRemoved then
        ReplicationInterface.entryRemoved:Connect(function(entry)
            ClearEntry(entry)
        end)
    end
end

-- ── aimbot ────────────────────────────────────────────────────────────────────
local Aimbot = {
    Enabled    = false,
    strength   = 0.15,
    FOV        = 150,
    TargetPart = "Head",
    TeamCheck  = true,
    HoldingRMB = false
}

local function GetPartFromEntry(entry)
    local hash = entry:getThirdPersonObject() and entry:getThirdPersonObject():getCharacterHash()
    if not hash then return nil end
    if Aimbot.TargetPart == "Head"  then return hash.Head  end
    if Aimbot.TargetPart == "Torso" then return hash.Torso end
    return nil
end

local function GetClosestTarget()
    local closest      = nil
    local shortestDist = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    local entries = ReplicationInterface.getEntries and ReplicationInterface.getEntries()
                 or ReplicationInterface.entries
    if not entries then return nil end

    for _, entry in pairs(entries) do
        if entry._player == LocalPlayer then continue end
        if not entry:isAlive() then continue end
        if Aimbot.TeamCheck and not entry:isEnemy() then continue end

        local part = GetPartFromEntry(entry)
        if not part then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if dist < Aimbot.FOV and dist < shortestDist then
            shortestDist = dist
            closest      = part
        end
    end

    return closest
end

-- fov circle
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness    = 1
fovCircle.Color        = Color3.fromRGB(255, 255, 255)
fovCircle.NumSides     = 64
fovCircle.Radius       = Aimbot.FOV
fovCircle.Filled       = false
fovCircle.Transparency = 0.7
fovCircle.Visible      = false

RunService.RenderStepped:Connect(function()
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    fovCircle.Radius   = Aimbot.FOV
    fovCircle.Visible  = Aimbot.Enabled
end)

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        Aimbot.HoldingRMB = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        Aimbot.HoldingRMB = false
    end
end)

RunService.RenderStepped:Connect(function()
    if not Aimbot.Enabled or not Aimbot.HoldingRMB then return end

    local target = GetClosestTarget()
    if not target then return end

    local targetPos, onScreen = Camera:WorldToViewportPoint(target.Position)
    if not onScreen then return end

    local mousePos = UserInputService:GetMouseLocation()
    mousemoverel(
        (targetPos.X - mousePos.X) * Aimbot.strength,
        (targetPos.Y - mousePos.Y) * Aimbot.strength
    )
end)

-- ── UI ────────────────────────────────────────────────────────────────────────
local aimbotSection = aimbot:Section({Name = "aimbot", Side = 1})

aimbotSection:Toggle({
    Name     = "enabled",
    Flag     = "aimbot_enabled",
    Default  = false,
    Callback = function(state) Aimbot.Enabled = state end
})

aimbotSection:Slider({
    Name     = "strength",
    Flag     = "aimbot_strength",
    Min      = 0.01,
    Max      = 1,
    Decimals = 0.01,
    Default  = 0.15,
    Callback = function(value) Aimbot.strength = value end
})

aimbotSection:Slider({
    Name     = "fov",
    Flag     = "aimbot_fov",
    Min      = 10,
    Max      = 500,
    Decimals = 1,
    Default  = 150,
    Callback = function(value) Aimbot.FOV = value end
})

aimbotSection:Dropdown({
    Name     = "target part",
    Flag     = "aimbot_targetpart",
    Multi    = false,
    Default  = "Head",
    Items    = {"Head", "Torso"},
    Callback = function(selected) Aimbot.TargetPart = selected end
})

aimbotSection:Toggle({
    Name     = "team check",
    Flag     = "aimbot_teamcheck",
    Default  = true,
    Callback = function(state) Aimbot.TeamCheck = state end
})

local chamsSection = visuals:Section({Name = "chams", Side = 2})

local chamsToggle = chamsSection:Toggle({
    Name     = "enabled",
    Flag     = "chams_enabled",
    Default  = false,
    Callback = function(state)
        Chams.Enabled = state
        RefreshAll()
    end
})

chamsToggle:Colorpicker({
    Name     = "color",
    Flag     = "chams_color",
    Alpha    = 0,
    Default  = Color3.fromRGB(255, 85, 0),
    Callback = function(color)
        Chams.Color = color
        UpdateProperties()
    end
})

chamsSection:Slider({
    Name     = "transparency",
    Flag     = "chams_transparency",
    Min      = 0,
    Max      = 1,
    Decimals = 0.01,
    Default  = 0.5,
    Callback = function(value)
        Chams.Trans = value
        UpdateProperties()
    end
})

chamsSection:Dropdown({
    Name     = "depth mode",
    Flag     = "chams_depth",
    Multi    = false,
    Default  = "AlwaysOnTop",
    Items    = {"AlwaysOnTop", "Occluded"},
    Callback = function(selected)
        Chams.OnTop = (selected == "AlwaysOnTop")
        UpdateProperties()
    end
})

chamsSection:Toggle({
    Name     = "enemy only",
    Flag     = "chams_enemy_only",
    Default  = true,
    Callback = function(state)
        Chams.EnemyOnly = state
        RefreshAll()
    end
})
