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

-- ── module resolver ────────────────────────────────────────────────────────────
local require = getrenv().shared and getrenv().shared.require
if not require then warn("[xephyr] shared require not found") return end

local ReplicationInterface = require("ReplicationInterface")
local operateOnAllEntries  = ReplicationInterface.operateOnAllEntries

-- ── chams ─────────────────────────────────────────────────────────────────────
local Chams = {
    Enabled   = false,
    Color     = Color3.fromRGB(84, 132, 171),
    Trans     = 0.5,
    OnTop     = true,
    EnemyOnly = true,
    -- [Player] = { inner = {bha,...}, outer = {bha,...} }
    Cache     = {},
}

local Storage = Instance.new("Folder")
Storage.Name   = "XephyrChams"
Storage.Parent = CoreGui

local function IsEnemy(player)
    return player.Team ~= LocalPlayer.Team
end

local function MakeBHA(part, alwaysOnTop, sizeOffset)
    local bha         = Instance.new("BoxHandleAdornment")
    bha.Adornee       = part
    bha.Size          = part.Size + sizeOffset
    bha.Color3        = Chams.Color
    bha.Transparency  = Chams.Trans
    bha.AlwaysOnTop   = alwaysOnTop
    bha.ZIndex        = alwaysOnTop and 10 or 5
    bha.Visible       = false
    bha.Parent        = Storage
    return bha
end

local ZERO_OFFSET  = Vector3.new(0,    0,    0   )
local OUTER_OFFSET = Vector3.new(0.15, 0.15, 0.15)

local function BuildChams(player, entry)
    -- clean up any existing ones first
    local existing = Chams.Cache[player]
    if existing then
        for _, bha in ipairs(existing.inner) do pcall(function() bha:Destroy() end) end
        for _, bha in ipairs(existing.outer) do pcall(function() bha:Destroy() end) end
        Chams.Cache[player] = nil
    end

    if not Chams.Enabled then return end
    if not entry._alive   then return end
    if Chams.EnemyOnly and not IsEnemy(player) then return end

    local tpo = entry:getThirdPersonObject()
    if not tpo then return end

    local hash = tpo:getCharacterHash()
    if not hash then return end

    local inner, outer = {}, {}

    for _, part in pairs(hash) do
        if typeof(part) == "Instance" and part:IsA("BasePart") then
            table.insert(inner, MakeBHA(part, true,  ZERO_OFFSET ))
            table.insert(outer, MakeBHA(part, false, OUTER_OFFSET))
        end
    end

    Chams.Cache[player] = { inner = inner, outer = outer }
end

local function KillChams(player)
    local c = Chams.Cache[player]
    if not c then return end
    for _, bha in ipairs(c.inner) do pcall(function() bha:Destroy() end) end
    for _, bha in ipairs(c.outer) do pcall(function() bha:Destroy() end) end
    Chams.Cache[player] = nil
end

local function SetChamsVisible(player, visible)
    local c = Chams.Cache[player]
    if not c then return end
    for _, bha in ipairs(c.inner) do bha.Visible = visible end
    for _, bha in ipairs(c.outer) do bha.Visible = visible end
end

local function UpdateProperties()
    for _, c in pairs(Chams.Cache) do
        for _, bha in ipairs(c.inner) do
            bha.Color3       = Chams.Color
            bha.Transparency = Chams.Trans
            bha.AlwaysOnTop  = Chams.OnTop
        end
        for _, bha in ipairs(c.outer) do
            bha.Color3       = Chams.Color
            bha.Transparency = Chams.Trans
        end
    end
end

local function RefreshAll()
    operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        BuildChams(player, entry)
    end)
end

-- hook addEntry so new players get chams immediately
local OriginalAddEntry = ReplicationInterface.addEntry
ReplicationInterface.addEntry = function(player)
    local result = OriginalAddEntry(player)
    if player ~= LocalPlayer then
        task.defer(function()
            local entry = ReplicationInterface.getEntry(player)
            if entry then BuildChams(player, entry) end
        end)
    end
    return result
end

-- per-frame: show/hide based on alive, rebuild if hash changed
RunService.PreRender:Connect(function()
    if not Chams.Enabled then
        -- make sure everything is hidden while disabled
        for player in pairs(Chams.Cache) do
            SetChamsVisible(player, false)
        end
        return
    end

    operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if Chams.EnemyOnly and not IsEnemy(player) then
            SetChamsVisible(player, false)
            return
        end

        local alive = entry._alive
        local cached = Chams.Cache[player]

        if alive then
            -- build if missing
            if not cached then
                BuildChams(player, entry)
                cached = Chams.Cache[player]
            end
            if cached then SetChamsVisible(player, true) end
        else
            if cached then SetChamsVisible(player, false) end
        end
    end)
end)

-- clean up on player leave
Players.PlayerRemoving:Connect(function(player)
    KillChams(player)
end)

-- ── aimbot ────────────────────────────────────────────────────────────────────
local Aimbot = {
    Enabled    = false,
    strength   = 0.15,
    FOV        = 150,
    TargetPart = "Head",
    TeamCheck  = true,
    HoldingRMB = false
}

local function GetClosestTarget()
    local closest      = nil
    local shortestDist = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if not entry._alive then return end
        if Aimbot.TeamCheck and not IsEnemy(player) then return end

        local tpo = entry:getThirdPersonObject()
        if not tpo then return end

        local hash = tpo:getCharacterHash()
        if not hash then return end

        local part = Aimbot.TargetPart == "Head" and hash.Head or hash.Torso
        if not part then return end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then return end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if dist < Aimbot.FOV and dist < shortestDist then
            shortestDist = dist
            closest      = part
        end
    end)

    return closest
end

-- fov circle
local fovCircle           = Drawing.new("Circle")
fovCircle.Thickness       = 1
fovCircle.Color           = Color3.fromRGB(255, 255, 255)
fovCircle.NumSides        = 64
fovCircle.Radius          = Aimbot.FOV
fovCircle.Filled          = false
fovCircle.Transparency    = 0.7
fovCircle.Visible         = false

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
        if state then
            RefreshAll()
        else
            for player in pairs(Chams.Cache) do
                KillChams(player)
            end
        end
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
