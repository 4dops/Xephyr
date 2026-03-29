local LIB_HELPER = loadstring(game:HttpGet("https://raw.githubusercontent.com/4dops/XephyrUI/refs/heads/main/ui.luau"))()

local WINDOW = Library:Window({ Name = "Xephyr.lua", FadeSpeed = 0.3 })

local PAGE_AIMBOT   = WINDOW:Page({ Name = "aimbot",        Columns = 3 })
local PAGE_VISUALS  = WINDOW:Page({ Name = "visuals",       Columns = 2 })
local PAGE_MISC     = WINDOW:Page({ Name = "miscellaneous", Columns = 4 })
local PAGE_SETTINGS = WINDOW:Page({ Name = "settings",      Columns = 3 })

local PLAYERS      = game:GetService("Players")
local RUN_SERVICE  = game:GetService("RunService")
local USER_INPUT   = game:GetService("UserInputService")
local CORE_GUI     = game:GetService("CoreGui")
local CAMERA       = workspace:WaitForChild("Camera")
local LOCAL_PLAYER = PLAYERS.LocalPlayer

local _require = getrenv().shared and getrenv().shared.require
local ReplicationInterface = _require and _require('ReplicationInterface')
local CharacterInterface   = _require and _require('CharacterInterface')

-- state

local CHAMS = {
    ENABLED    = false,
    FILL_COLOR = Color3.fromRGB(255, 85, 0),
    FILL_TRANS = 0.5,
    ON_TOP     = true,
    ENEMY_ONLY = true,
    ACTIVE      = setmetatable({}, { __mode = "k" }),
    CONNECTIONS = setmetatable({}, { __mode = "k" }),
}

local AIMBOT = {
    ENABLED     = false,
    STRENGTH    = 0.15,
    FOV         = 150,
    TARGET_PART = "Head",
    TEAM_CHECK  = true,
    WALL_CHECK  = false,
    HOLDING_RMB = false,
}

local FOV_CIRCLE_CFG = {
    ENABLED   = true,
    ALWAYS    = false,
    COLOR     = Color3.fromRGB(255, 255, 255),
    THICKNESS = 1,
}

local ESP = {
    ENABLED      = false,
    SHOW_VISIBLE = false,
    SHOW_BOX     = false,
    DRAWINGS     = setmetatable({}, { __mode = "k" }),
}

local REFRESH_ALL

-- helpers

local function GET_ENTRY(PLAYER)
    if not ReplicationInterface then return nil end
    return ReplicationInterface.getEntry(PLAYER)
end

local function IS_ENEMY(PLAYER)
    if not CHAMS.ENEMY_ONLY then return true end
    local ENTRY = GET_ENTRY(PLAYER)
    if not ENTRY then return false end
    return ENTRY._isEnemy == true
end

local function GET_CHAR_HASH(ENTRY)
    if not ENTRY or not ENTRY._alive then return nil end
    local TP = ENTRY._thirdPersonObject
    return TP and TP:getCharacterHash()
end

local function GET_TARGET_FROM_HASH(CHAR_HASH)
    if not CHAR_HASH then return nil end
    return CHAR_HASH[AIMBOT.TARGET_PART]
end

-- los

local RAY_PARAMS = RaycastParams.new()
RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude

local function HAS_LINE_OF_SIGHT(TARGET_PART)
    local ORIGIN    = CAMERA.CFrame.Position
    local DIRECTION = TARGET_PART.Position - ORIGIN
    RAY_PARAMS.FilterDescendantsInstances = { workspace:FindFirstChild("Players"), LOCAL_PLAYER.Character }
    local RESULT = workspace:Raycast(ORIGIN, DIRECTION, RAY_PARAMS)
    if not RESULT then return true end
    local TARGET_MODEL = TARGET_PART:FindFirstAncestorOfClass("Model")
    return TARGET_MODEL and RESULT.Instance:IsDescendantOf(TARGET_MODEL)
end

-- aimbot

local function GET_CLOSEST_TARGET()
    if not ReplicationInterface then return nil end

    local CLOSEST, SHORTEST_DIST = nil, math.huge
    local SCREEN_CENTER = Vector2.new(CAMERA.ViewportSize.X / 2, CAMERA.ViewportSize.Y / 2)

    ReplicationInterface.operateOnAllEntries(function(PLAYER, ENTRY)
        if AIMBOT.TEAM_CHECK and not IS_ENEMY(PLAYER) then return end
        if not ENTRY._alive then return end

        local CHAR_HASH   = GET_CHAR_HASH(ENTRY)
        local TARGET_PART = GET_TARGET_FROM_HASH(CHAR_HASH)
        if not TARGET_PART then return end

        local SCREEN_POS, ON_SCREEN = CAMERA:WorldToViewportPoint(TARGET_PART.Position)
        if not ON_SCREEN then return end

        local DIST = (Vector2.new(SCREEN_POS.X, SCREEN_POS.Y) - SCREEN_CENTER).Magnitude
        if DIST < AIMBOT.FOV and DIST < SHORTEST_DIST then
            if AIMBOT.WALL_CHECK and not HAS_LINE_OF_SIGHT(TARGET_PART) then return end
            SHORTEST_DIST = DIST
            CLOSEST       = TARGET_PART
        end
    end)

    return CLOSEST
end

-- chams

local function CREATE_HIGHLIGHT(MODEL)
    local HL = Instance.new("Highlight")
    HL.Adornee             = MODEL
    HL.FillColor           = CHAMS.FILL_COLOR
    HL.FillTransparency    = CHAMS.FILL_TRANS
    HL.OutlineTransparency = 1
    HL.DepthMode           = CHAMS.ON_TOP and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    HL.Parent              = CORE_GUI
    return HL
end

local function CLEANUP_PLAYER_CHAMS(PLAYER)
    local DATA = CHAMS.ACTIVE[PLAYER]
    if DATA then pcall(function() DATA.HL:Destroy() end) end
    CHAMS.ACTIVE[PLAYER] = nil
end

local function UPDATE_PLAYER_CHAMS(PLAYER, MODEL)
    local DATA = CHAMS.ACTIVE[PLAYER]
    if DATA and DATA.MODEL == MODEL then return end
    CLEANUP_PLAYER_CHAMS(PLAYER)
    if not CHAMS.ENABLED or not IS_ENEMY(PLAYER) then return end
    local HL = CREATE_HIGHLIGHT(MODEL)
    CHAMS.ACTIVE[PLAYER] = { HL = HL, MODEL = MODEL }
end

REFRESH_ALL = function()
    if not ReplicationInterface then return end

    for PLAYER in pairs(CHAMS.ACTIVE) do
        local ENTRY = GET_ENTRY(PLAYER)
        if not ENTRY or not ENTRY._alive or not IS_ENEMY(PLAYER) then
            CLEANUP_PLAYER_CHAMS(PLAYER)
        end
    end

    if not CHAMS.ENABLED then return end

    ReplicationInterface.operateOnAllEntries(function(PLAYER, ENTRY)
        if not IS_ENEMY(PLAYER) or not ENTRY._alive then return end
        local TP    = ENTRY._thirdPersonObject
        local MODEL = TP and TP:getCharacterModel()
        if MODEL then UPDATE_PLAYER_CHAMS(PLAYER, MODEL) end
    end)
end

local function UPDATE_CHAM_PROPERTIES()
    for _, DATA in pairs(CHAMS.ACTIVE) do
        local HL = DATA.HL
        if HL and HL:IsA("Highlight") then
            HL.FillColor        = CHAMS.FILL_COLOR
            HL.FillTransparency = CHAMS.FILL_TRANS
            HL.DepthMode        = CHAMS.ON_TOP and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        end
    end
end

local LAST_CHAMS_REFRESH = 0
RUN_SERVICE.Heartbeat:Connect(function()
    local NOW = tick()
    if NOW - LAST_CHAMS_REFRESH >= 1 then
        LAST_CHAMS_REFRESH = NOW
        REFRESH_ALL()
    end
end)

-- esp

local ESP_GUI = Instance.new("ScreenGui")
ESP_GUI.Name            = "\0"
ESP_GUI.ZIndexBehavior  = Enum.ZIndexBehavior.Global
ESP_GUI.DisplayOrder    = 3
ESP_GUI.ResetOnSpawn    = false
ESP_GUI.IgnoreGuiInset  = true
ESP_GUI.Parent          = (gethui and gethui()) or CORE_GUI

local function CREATE_ESP_DRAWINGS()
    local BOX = Drawing.new("Square")
    BOX.Thickness    = 1.5
    BOX.Color        = Color3.fromRGB(255, 85, 0)
    BOX.Filled       = false
    BOX.Transparency = 1
    BOX.Visible      = false

    local LABEL = Instance.new("TextLabel")
    LABEL.Name                   = "\0"
    LABEL.BackgroundTransparency = 1
    LABEL.BorderSizePixel        = 0
    LABEL.AnchorPoint            = Vector2.new(0.5, 0.5)
    LABEL.Size                   = UDim2.new(0, 140, 0, 16)
    LABEL.FontFace               = Library.Font
    LABEL.TextSize               = 8
    LABEL.TextColor3             = Color3.fromRGB(255, 85, 0)
    LABEL.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    LABEL.TextStrokeTransparency = 0
    LABEL.Visible                = false
    LABEL.Parent                 = ESP_GUI

    return { BOX = BOX, VISIBLE_LABEL = LABEL }
end

local function DESTROY_ESP_DRAWINGS(PLAYER)
    local DRAWS = ESP.DRAWINGS[PLAYER]
    if not DRAWS then return end
    if DRAWS.BOX          then pcall(function() DRAWS.BOX:Remove() end) end
    if DRAWS.VISIBLE_LABEL then pcall(function() DRAWS.VISIBLE_LABEL:Destroy() end) end
    ESP.DRAWINGS[PLAYER] = nil
end

local function ENSURE_ESP_DRAWINGS(PLAYER)
    if not ESP.DRAWINGS[PLAYER] then
        ESP.DRAWINGS[PLAYER] = CREATE_ESP_DRAWINGS()
    end
    return ESP.DRAWINGS[PLAYER]
end

local function CLEAR_ALL_ESP_DRAWINGS()
    for PLAYER in pairs(ESP.DRAWINGS) do DESTROY_ESP_DRAWINGS(PLAYER) end
end

-- fov circle

local FOV_CIRCLE = Drawing.new("Circle")
FOV_CIRCLE.Thickness    = FOV_CIRCLE_CFG.THICKNESS
FOV_CIRCLE.Color        = FOV_CIRCLE_CFG.COLOR
FOV_CIRCLE.NumSides     = 64
FOV_CIRCLE.Filled       = false
FOV_CIRCLE.Transparency = 0.7
FOV_CIRCLE.Visible      = false

-- ui

local AIMBOT_SECTION = PAGE_AIMBOT:Section({ Name = "aimbot", Side = 1 })

local AIMBOT_TOGGLE = AIMBOT_SECTION:Toggle({
    Name = "enabled", Flag = "aimbot_enabled", Default = false,
    Callback = function(STATE) AIMBOT.ENABLED = STATE end,
})

AIMBOT_TOGGLE:Keybind({
    Name = "hold key", Flag = "aimbot_key",
    Default = Enum.UserInputType.MouseButton2, Mode = "Hold",
    Callback = function(ACTIVE) AIMBOT.HOLDING_RMB = ACTIVE end,
})

AIMBOT_SECTION:Slider({
    Name = "strength", Flag = "aimbot_strength", Min = 0.01, Max = 1, Decimals = 0.01, Default = 0.15,
    Callback = function(VALUE) AIMBOT.STRENGTH = VALUE end,
})

AIMBOT_SECTION:Slider({
    Name = "fov", Flag = "aimbot_fov", Min = 10, Max = 500, Decimals = 1, Default = 150,
    Callback = function(VALUE) AIMBOT.FOV = VALUE end,
})

AIMBOT_SECTION:Dropdown({
    Name = "target part", Flag = "aimbot_targetpart", Multi = false, Default = "Head",
    Items = { "Head", "Torso" },
    Callback = function(SELECTED) AIMBOT.TARGET_PART = SELECTED end,
})

AIMBOT_SECTION:Toggle({
    Name = "team check", Flag = "aimbot_teamcheck", Default = true,
    Callback = function(STATE) AIMBOT.TEAM_CHECK = STATE end,
})

AIMBOT_SECTION:Toggle({
    Name = "wall check", Flag = "aimbot_wallcheck", Default = false,
    Callback = function(STATE) AIMBOT.WALL_CHECK = STATE end,
})

local ESP_SECTION = PAGE_VISUALS:Section({ Name = "esp", Side = 1 })

ESP_SECTION:Toggle({
    Name = "enabled", Flag = "esp_enabled", Default = false,
    Callback = function(STATE)
        ESP.ENABLED = STATE
        if not STATE then CLEAR_ALL_ESP_DRAWINGS() end
    end,
})

ESP_SECTION:Toggle({
    Name = "box esp", Flag = "esp_box", Default = false,
    Callback = function(STATE)
        ESP.SHOW_BOX = STATE
        if not STATE then CLEAR_ALL_ESP_DRAWINGS() end
    end,
})

ESP_SECTION:Toggle({
    Name = "visible indicator", Flag = "esp_visible", Default = false,
    Callback = function(STATE)
        ESP.SHOW_VISIBLE = STATE
        if not STATE then CLEAR_ALL_ESP_DRAWINGS() end
    end,
})

local FOV_CIRCLE_SECTION = PAGE_VISUALS:Section({ Name = "fov circle", Side = 1 })

local FOV_ENABLED_TOGGLE = FOV_CIRCLE_SECTION:Toggle({
    Name = "enabled", Flag = "fovcircle_enabled", Default = true,
    Callback = function(STATE) FOV_CIRCLE_CFG.ENABLED = STATE end,
})

FOV_ENABLED_TOGGLE:Colorpicker({
    Name = "color", Flag = "fovcircle_color", Alpha = 0, Default = Color3.fromRGB(255, 255, 255),
    Callback = function(COLOR)
        FOV_CIRCLE_CFG.COLOR = COLOR
        FOV_CIRCLE.Color     = COLOR
    end,
})

FOV_CIRCLE_SECTION:Toggle({
    Name = "show always", Flag = "fovcircle_always", Default = false,
    Callback = function(STATE) FOV_CIRCLE_CFG.ALWAYS = STATE end,
})

FOV_CIRCLE_SECTION:Slider({
    Name = "thickness", Flag = "fovcircle_thickness", Min = 1, Max = 5, Decimals = 1, Default = 1,
    Callback = function(VALUE)
        FOV_CIRCLE_CFG.THICKNESS = VALUE
        FOV_CIRCLE.Thickness     = VALUE
    end,
})

local CHAMS_SECTION = PAGE_VISUALS:Section({ Name = "chams", Side = 2 })

local CHAMS_TOGGLE = CHAMS_SECTION:Toggle({
    Name = "enabled", Flag = "chams_enabled", Default = false,
    Callback = function(STATE) CHAMS.ENABLED = STATE; REFRESH_ALL() end,
})

CHAMS_TOGGLE:Colorpicker({
    Name = "fill color", Flag = "chams_fill_color", Alpha = 0, Default = Color3.fromRGB(255, 85, 0),
    Callback = function(COLOR) CHAMS.FILL_COLOR = COLOR; UPDATE_CHAM_PROPERTIES() end,
})

CHAMS_SECTION:Slider({
    Name = "fill transparency", Flag = "chams_fill_trans", Min = 0, Max = 1, Decimals = 0.01, Default = 0.5,
    Callback = function(VALUE) CHAMS.FILL_TRANS = VALUE; UPDATE_CHAM_PROPERTIES() end,
})

CHAMS_SECTION:Dropdown({
    Name = "depth mode", Flag = "chams_depth", Multi = false, Default = "AlwaysOnTop",
    Items = { "AlwaysOnTop", "Occluded" },
    Callback = function(SELECTED) CHAMS.ON_TOP = SELECTED == "AlwaysOnTop"; UPDATE_CHAM_PROPERTIES() end,
})

CHAMS_SECTION:Toggle({
    Name = "enemy only", Flag = "chams_enemy_only", Default = true,
    Callback = function(STATE) CHAMS.ENEMY_ONLY = STATE; REFRESH_ALL() end,
})

do
    local THEMING_SECTION = PAGE_SETTINGS:Section({ Name = "Theming", Side = 2 })
    for THEME_INDEX, THEME_VALUE in Library.Theme do
        THEMING_SECTION:Label(THEME_INDEX, "Left"):Colorpicker({
            Name     = THEME_INDEX,
            Flag     = THEME_INDEX .. "Theme",
            Default  = THEME_VALUE,
            Callback = function(NEW_COLOR)
                Library.Theme[THEME_INDEX] = NEW_COLOR
                Library:ChangeTheme(THEME_INDEX, NEW_COLOR)
            end,
        })
    end
end

do
    local CONFIG_SECTION  = PAGE_SETTINGS:Section({ Name = "Configs", Side = 1 })
    local CONFIG_NAME     = nil
    local CONFIG_SELECTED = nil

    local CONFIGS_LIST = CONFIG_SECTION:Dropdown({
        Name     = "Configs",
        Flag     = "configs_list",
        Items    = {},
        Callback = function(VALUE) CONFIG_SELECTED = VALUE end,
    })

    CONFIG_SECTION:Textbox({
        Name        = "Config Name",
        Placeholder = ". .",
        Flag        = "config_name",
        Callback    = function(VALUE) CONFIG_NAME = VALUE end,
    })

    local CREATE_DELETE_ROW = CONFIG_SECTION:Button()

    CREATE_DELETE_ROW:NewButton({
        Name     = "Create",
        Callback = function()
            if CONFIG_NAME and CONFIG_NAME ~= "" then
                if isfile(Library.Folders.Configs .. "/" .. CONFIG_NAME .. ".json") then
                    Library:Notification("Config with this name already exists.", 4, Color3.fromRGB(255, 0, 0))
                    return
                end
                writefile(Library.Folders.Configs .. "/" .. CONFIG_NAME .. ".json", Library:GetConfig())
                Library:Notification("Created config " .. CONFIG_NAME .. " successfully", 4, Color3.fromRGB(0, 255, 0))
                Library:RefreshConfigsList(CONFIGS_LIST)
            end
        end,
    })

    CREATE_DELETE_ROW:NewButton({
        Name     = "Delete",
        Callback = function()
            if CONFIG_SELECTED and isfile(Library.Folders.Configs .. "/" .. CONFIG_SELECTED) then
                Library:DeleteConfig(CONFIG_SELECTED)
                Library:Notification("Deleted config " .. CONFIG_SELECTED .. " successfully", 5, Color3.fromRGB(0, 255, 0))
                Library:RefreshConfigsList(CONFIGS_LIST)
            end
        end,
    })

    local SAVE_LOAD_ROW = CONFIG_SECTION:Button()

    SAVE_LOAD_ROW:NewButton({
        Name     = "Save",
        Callback = function()
            if CONFIG_SELECTED then
                Library:SaveConfig(CONFIG_SELECTED)
                Library:Notification("Saved config " .. CONFIG_SELECTED .. " successfully", 5, Color3.fromRGB(0, 255, 0))
            end
        end,
    })

    SAVE_LOAD_ROW:NewButton({
        Name     = "Load",
        Callback = function()
            if CONFIG_SELECTED then
                local SUCCESS, ERR = Library:LoadConfig(readfile(Library.Folders.Configs .. "/" .. CONFIG_SELECTED))
                if not SUCCESS then
                    Library:Notification("Failed to load config " .. CONFIG_SELECTED .. ":\n" .. tostring(ERR), 6, Color3.fromRGB(255, 0, 0))
                else
                    Library:Notification("Loaded config " .. CONFIG_SELECTED .. " successfully", 5, Color3.fromRGB(0, 255, 0))
                end
            end
        end,
    })

    CONFIG_SECTION:Button():NewButton({
        Name     = "Refresh",
        Callback = function()
            Library:Notification("Refreshed list successfully", 4, Color3.fromRGB(0, 255, 0))
            Library:RefreshConfigsList(CONFIGS_LIST)
        end,
    })

    Library:RefreshConfigsList(CONFIGS_LIST)
end

do
    local MENU_SECTION = PAGE_SETTINGS:Section({ Name = "Menu", Side = 3 })

    MENU_SECTION:Button():NewButton({
        Name     = "Unload",
        Callback = function() Library:Unload() end,
    })

    MENU_SECTION:Label("Menu keybind", "Left"):Keybind({
        Name     = "MenuKeybind",
        Flag     = "menu_keybind",
        Mode     = "Toggle",
        Default  = Library.MenuKeybind,
        Callback = function(_) Library.MenuKeybind = Library.Flags["menu_keybind"].Key end,
    })

    MENU_SECTION:Slider({
        Name = "Tween time", Flag = "menu_tween_time", Default = Library.Tween.Time,
        Min = 0, Max = 5, Decimals = 0.01,
        Callback = function(VALUE) Library.Tween.Time = VALUE end,
    })

    MENU_SECTION:Dropdown({
        Name = "Tween style", Flag = "menu_tween_style", Default = "Cubic",
        Items = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce" },
        Callback = function(VALUE) Library.Tween.Style = Enum.EasingStyle[VALUE] end,
    })

    MENU_SECTION:Dropdown({
        Name = "Tween direction", Flag = "menu_tween_dir", Default = "Out",
        Items = { "In", "Out", "InOut" },
        Callback = function(VALUE) Library.Tween.Direction = Enum.EasingDirection[VALUE] end,
    })
end

-- loops

USER_INPUT.InputBegan:Connect(function(INPUT)
    if INPUT.UserInputType == Enum.UserInputType.MouseButton2 then
        AIMBOT.HOLDING_RMB = true
    end
end)

USER_INPUT.InputEnded:Connect(function(INPUT)
    if INPUT.UserInputType == Enum.UserInputType.MouseButton2 then
        AIMBOT.HOLDING_RMB = false
    end
end)

RUN_SERVICE.RenderStepped:Connect(function()
    local CENTER = Vector2.new(CAMERA.ViewportSize.X / 2, CAMERA.ViewportSize.Y / 2)

    FOV_CIRCLE.Position = CENTER
    FOV_CIRCLE.Radius   = AIMBOT.FOV
    FOV_CIRCLE.Visible  = FOV_CIRCLE_CFG.ENABLED and (AIMBOT.ENABLED or FOV_CIRCLE_CFG.ALWAYS)

    if not ESP.ENABLED or not ReplicationInterface then
        CLEAR_ALL_ESP_DRAWINGS()
    else
        local SEEN = {}

        ReplicationInterface.operateOnAllEntries(function(PLAYER, ENTRY)
            if not IS_ENEMY(PLAYER) or not ENTRY._alive then
                DESTROY_ESP_DRAWINGS(PLAYER)
                return
            end

            local CHAR_HASH = GET_CHAR_HASH(ENTRY)
            local TORSO     = CHAR_HASH and CHAR_HASH.Torso
            local HEAD      = CHAR_HASH and CHAR_HASH.Head
            if not TORSO or not HEAD then
                DESTROY_ESP_DRAWINGS(PLAYER)
                return
            end

            local LOWEST_Y, HIGHEST_Y = math.huge, -math.huge
            for _, PART in pairs(CHAR_HASH) do
                if typeof(PART) == "Instance" and PART:IsA("BasePart") then
                    local BOTTOM = PART.Position.Y - PART.Size.Y * 0.5
                    local TOP    = PART.Position.Y + PART.Size.Y * 0.5
                    if BOTTOM < LOWEST_Y  then LOWEST_Y  = BOTTOM end
                    if TOP    > HIGHEST_Y then HIGHEST_Y = TOP    end
                end
            end

            local FEET_POS = Vector3.new(TORSO.Position.X, LOWEST_Y,  TORSO.Position.Z)
            local HEAD_POS = Vector3.new(TORSO.Position.X, HIGHEST_Y, TORSO.Position.Z)

            local FEET_SCREEN, ON_FEET = CAMERA:WorldToViewportPoint(FEET_POS)
            local HEAD_SCREEN, ON_HEAD = CAMERA:WorldToViewportPoint(HEAD_POS)

            if not ON_FEET or not ON_HEAD then
                DESTROY_ESP_DRAWINGS(PLAYER)
                return
            end

            SEEN[PLAYER] = true
            local DRAWS = ENSURE_ESP_DRAWINGS(PLAYER)

            if ESP.SHOW_BOX then
                local HEIGHT = math.abs(FEET_SCREEN.Y - HEAD_SCREEN.Y)
                local WIDTH  = HEIGHT * 0.6
                DRAWS.BOX.Size     = Vector2.new(WIDTH, HEIGHT)
                DRAWS.BOX.Position = Vector2.new(HEAD_SCREEN.X - WIDTH / 2, HEAD_SCREEN.Y)
                DRAWS.BOX.Visible  = true
            else
                DRAWS.BOX.Visible = false
            end

            if ESP.SHOW_VISIBLE then
                local IS_VIS = HAS_LINE_OF_SIGHT(TORSO)
                DRAWS.VISIBLE_LABEL.Text     = IS_VIS and "VISIBLE" or "NOT VISIBLE"
                DRAWS.VISIBLE_LABEL.Position = UDim2.fromOffset(FEET_SCREEN.X, FEET_SCREEN.Y + 6)
                DRAWS.VISIBLE_LABEL.Visible  = true
            else
                DRAWS.VISIBLE_LABEL.Visible = false
            end
        end)

        for PLAYER in pairs(ESP.DRAWINGS) do
            if not SEEN[PLAYER] then DESTROY_ESP_DRAWINGS(PLAYER) end
        end
    end

    if not AIMBOT.ENABLED or not AIMBOT.HOLDING_RMB then return end
    local TARGET = GET_CLOSEST_TARGET()
    if not TARGET then return end
    local TARGET_POS, ON_SCREEN = CAMERA:WorldToViewportPoint(TARGET.Position)
    if not ON_SCREEN then return end
    local MOUSE_POS = USER_INPUT:GetMouseLocation()
    mousemoverel(
        (TARGET_POS.X - MOUSE_POS.X) * AIMBOT.STRENGTH,
        (TARGET_POS.Y - MOUSE_POS.Y) * AIMBOT.STRENGTH
    )
end)
