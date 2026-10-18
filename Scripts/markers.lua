-- Agave Finder markers - the distance to every agave plant near you that has seeds, over the plant (Josh 2026-10-18:
-- "replace the labels with a distance. Kind of like we did for the crashed ships and testing stations and spice
-- blooms"). Written the World Beacons way: "24 m", "1.15 km", from the player to the marker, updated every pass.
--
-- How it draws: each plant gets one screen-space WidgetComponent of ours (tagged "AgaveMarker") holding a small
-- UserWidget = one TextBlock - the HealthBars method, which the engine projects every frame (no per-frame
-- Lua). Screen-space widgets draw over terrain, so a marker shows through hills and rock. The components sit on the
-- player character with an ABSOLUTE world location at the plant, so a marker stays put however far the character
-- goes - and keeps showing after the plant's spawner has unloaded.
--
-- Where the plants are: a spawner is only in memory while you are near it, so every plant position the mod sees is
-- written to agave_positions.txt in the mod folder (one line per plant, keyed by the spawner's world position, which
-- is the same in every world). The release ships the 75 plants Josh found around the Hagga Basin; new ones are added
-- as they are seen.
--
-- Seeds ("No seeds, no bar, seeds, bar"): a marker shows only while its plant has seeds. The game keeps each plant's
-- harvests left (0 = no seeds) in private memory Lua cannot see, so the mod's native part (dlls/main.dll) gives Lua
-- AgaveSeedsLeft(componentAddress, plantCount). Every pass reads it for each loaded spawner; a plant only regrows with
-- a player within 10 m, so the last reading of a spawner that has since unloaded stays true. A plant never read yet
-- shows its marker. Without the native part, or on a game build whose memory differs, every plant in range shows
-- (logged once).
--
-- Game thread only. valid() before every method on a fetched object.

local M = {}

local TAG = "AgaveMarker"
local WIDGET_COMPONENT = "/Script/UMG.WidgetComponent"
local PLAYER_CHARACTER = "/Script/DuneSandbox.DunePlayerCharacter"
local FAILURES_TO_LOG = 10
local POSITIONS_FILE = "agave_positions.txt"
local SEEDS_READER = "AgaveSeedsLeft"      -- the global the native part registers
local CM_PER_M = 100
local DEFAULT_TOP_CM = 250           -- used when the plant mesh's bounds cannot be read
local ABOVE_TOP_CM = 30              -- Josh: about a foot above the top of the plant
local NEW_MARKERS_PER_PASS = 12
local LABEL_WIDTH, LABEL_HEIGHT = 100, 28  -- wide enough for "1.15 km" at LABEL_SIZE
local LABEL_SIZE = 16
local LABEL_COLOUR = { 0.10, 0.95, 0.20, 1.0 }
local SHADOW_COLOUR = { 0, 0, 0, 0.9 }
local VIS_HIT_TEST_INVISIBLE = 3
local HALIGN_CENTER, VALIGN_CENTER, JUSTIFY_CENTER = 2, 2, 1
local WIDGET_SPACE_SCREEN = 1
local IDENTITY = { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
    Scale3D = { X = 1, Y = 1, Z = 1 } }

local ctx                            -- log, valid, try, harvestables, spawnerClass, modRoot, markerRange
local known, order = {}, {}          -- plant key -> { x, y, z }; keys in the order first seen
local made = {}                      -- plant key -> our WidgetComponent
local seedsLeft = {}                 -- plant key -> harvests left at its last reading (0 = no seeds)
local seedReader = "unknown"         -- "unknown" until the first read, then "native" or "missing" / "layout"
local hiddenNow = {}                 -- plant key -> true while its marker is hidden
local textOf, wordsNow = {}, {}      -- plant key -> its marker's TextBlock; the distance it shows
local host                           -- the player character the components sit on
local failures = 0

local function class(path) return ctx.try(function() return StaticFindObject(path) end) end

-- Structs are built by the engine's own Make* functions: UE4SS drops the first field of a struct passed as a new
-- Lua table (catalog: "UE4SS struct quirk").
local function color(r, g, b, a) return class("/Script/Engine.Default__KismetMathLibrary"):MakeColor(r, g, b, a) end
local function vec2(x, y) return class("/Script/Engine.Default__KismetMathLibrary"):MakeVector2D(x, y) end

-- A spawner's place in the world, which names it across sessions (its object name changes every load).
local function spawnerKey(spawner)
    local at = ctx.try(function() return spawner:K2_GetActorLocation() end)
    if not at then return nil end
    if at.X == 0 and at.Y == 0 and at.Z == 0 then return nil end      -- a copy the game is throwing away
    return string.format("%.0f,%.0f,%.0f", at.X, at.Y, at.Z)
end

-- Height of the top of the plant mesh above the instance's origin, in cm (scaled).
local function topOf(comp, scale)
    local bounds = ctx.try(function() return comp.StaticMesh:GetBounds() end)
    local top = bounds and ctx.try(function() return bounds.Origin.Z + bounds.BoxExtent.Z end)
    if type(top) ~= "number" or top <= 0 then top = DEFAULT_TOP_CM end
    return top * (scale or 1)
end

local function loadPositions()
    local f = io.open(ctx.modRoot .. "/" .. POSITIONS_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local key, x, y, z = line:match("^(%S+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)")
        if key and not known[key] then
            known[key] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            order[#order + 1] = key
        end
    end
    f:close()
end

local function savePosition(key, spot)
    local f = io.open(ctx.modRoot .. "/" .. POSITIONS_FILE, "a")
    if f then f:write(string.format("%s %.0f %.0f %.0f\n", key, spot.x, spot.y, spot.z)); f:close() end
end

-- Logs the seed reader's state the first time it is known, and whenever it stops working.
local function noteReader(state, detail)
    if seedReader == state then return end
    seedReader = state
    if state == "native" then ctx.log("seeds: reading each plant's harvests left (native part)")
    elseif state == "missing" then ctx.log("seeds: native part not loaded (dlls/main.dll) - every plant in range shows")
    else ctx.log("seeds: memory not as expected (" .. detail .. ") - those plants show; game update?") end
end

-- Reads one component's harvests left into seedsLeft.
local function readSeeds(skey, c, comp, count)
    local reader = _G[SEEDS_READER]
    if type(reader) ~= "function" then noteReader("missing"); return end
    local address = ctx.try(function() return comp:GetAddress() end)
    if type(address) ~= "number" or count < 1 then return end
    local result = table.pack(pcall(reader, address, count))
    if not result[1] or result.n - 1 ~= count then
        noteReader("layout", string.format("%s comp %d gave %d of %d", skey, c, result.n - 1, count))
        return
    end
    noteReader("native")
    for i = 0, count - 1 do seedsLeft[skey .. "/" .. c .. "/" .. i] = result[i + 2] end
end

-- Records the marker spot (top of the plant + ABOVE_TOP_CM) of every plant on every loaded spawner not seen before,
-- and reads each loaded plant's seeds.
local function recordSpawners()
    local added = 0
    for _, s in ipairs(FindAllOf(ctx.spawnerClass) or {}) do
        local skey = ctx.valid(s) and spawnerKey(s)
        for c, comp in ipairs(skey and ctx.harvestables(s) or {}) do
            local count = ctx.try(function() return comp:GetInstanceCount() end) or 0
            readSeeds(skey, c, comp, count)
            for i = 0, count - 1 do
                local key = skey .. "/" .. c .. "/" .. i
                local tf = {}
                if not known[key] and pcall(function() comp:GetInstanceTransform(i, tf, true) end) and tf.Translation then
                    local scale = ctx.try(function() return tf.Scale3D.Z end)
                    local spot = { x = tf.Translation.X, y = tf.Translation.Y,
                        z = tf.Translation.Z + topOf(comp, scale) + ABOVE_TOP_CM }
                    known[key] = spot
                    order[#order + 1] = key
                    savePosition(key, spot)
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then ctx.log(string.format("markers: %d new plant positions saved (%d known)", added, #order)) end
end

-- The marker's UserWidget: one TextBlock (the distance, filled in by applyVisibility). Returns widget, text.
local function buildWidget(pc)
    local widget = class("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, class("/Script/UMG.UserWidget"), pc)
    if not ctx.valid(widget) then error("UserWidget not created") end
    local tree = widget.WidgetTree
    if not ctx.valid(tree) then
        tree = StaticConstructObject(class("/Script/UMG.WidgetTree"), widget, 0, 0)
        widget.WidgetTree = tree
    end
    local overlay = StaticConstructObject(class("/Script/UMG.Overlay"), tree, 0, 0)
    tree.RootWidget = overlay
    local text = StaticConstructObject(class("/Script/UMG.TextBlock"), tree, 0, 0)
    if not ctx.valid(text) then error("TextBlock not created") end
    local textSlot = overlay:AddChildToOverlay(text)
    textSlot:SetHorizontalAlignment(HALIGN_CENTER)
    textSlot:SetVerticalAlignment(VALIGN_CENTER)
    pcall(function() text:SetJustification(JUSTIFY_CENTER) end)
    pcall(function() text:SetShadowOffset(vec2(1.5, 1.5)) end)
    pcall(function() text:SetShadowColorAndOpacity(color(table.unpack(SHADOW_COLOUR))) end)
    pcall(function()                     -- the WorldBeacons method: edit the TextBlock's own colour / font structs
        local slate = text.ColorAndOpacity
        slate.SpecifiedColor = color(table.unpack(LABEL_COLOUR))
        text:SetColorAndOpacity(slate)
    end)
    pcall(function()
        local font = text.Font
        font.Size = LABEL_SIZE
        text:SetFont(font)
    end)
    widget:SetVisibility(VIS_HIT_TEST_INVISIBLE)
    return widget, text
end

local function addMarker(pc, key)
    local spot = known[key]
    local comp = host:AddComponentByClass(class(WIDGET_COMPONENT), false, IDENTITY, false)
    if not ctx.valid(comp) then error("WidgetComponent not added") end
    pcall(function() comp:SetCollisionEnabled(0) end)
    comp:SetAbsolute(true, true, true)
    comp:SetWidgetSpace(WIDGET_SPACE_SCREEN)
    comp:SetDrawSize(vec2(LABEL_WIDTH, LABEL_HEIGHT))
    comp:K2_SetWorldLocation({ X = spot.x, Y = spot.y, Z = spot.z }, false, {}, false)
    pcall(function() local tags = comp.ComponentTags; tags[tags:GetArrayNum() + 1] = FName(TAG) end)
    local widget, text = buildWidget(pc)
    comp:SetWidget(widget)
    textOf[key], wordsNow[key] = text, nil
    pcall(function() comp:MarkRenderStateDirty() end)
    return comp
end

-- The player character to hang markers on. Kept while it lives (a vehicle seat does not move them); a new one
-- (after a death) gets a fresh set, since the old components went with the old character.
local function currentHost(pc)
    if ctx.valid(host) then return host end
    local pawn = ctx.try(function() return pc.Pawn end)
    local cls = class(PLAYER_CHARACTER)
    if ctx.valid(pawn) and cls and ctx.try(function() return pawn:IsA(cls) end) then
        if host ~= nil then ctx.log("markers: new player character - markers made again") end
        host, made, hiddenNow, textOf, wordsNow = pawn, {}, {}, {}, {}
        return host
    end
end

function M.removeAll()
    local removed = 0
    for _, comp in pairs(made) do
        if ctx.valid(comp) and pcall(function() comp:K2_DestroyComponent(comp) end) then removed = removed + 1 end
    end
    made, hiddenNow, textOf, wordsNow = {}, {}, {}, {}
    if removed > 0 then ctx.log("markers removed: " .. removed) end
end

-- Where the player stands, or nil.
local function playerAt()
    local pc = FindFirstOf("PlayerController")
    return ctx.valid(pc) and ctx.try(function() return pc.Pawn:K2_GetActorLocation() end) or nil
end

-- Metres from a ground position to a plant's marker spot, across the ground (the spot itself sits above the plant).
local function metresBetween(at, spot)
    return math.sqrt((at.X - spot.x) ^ 2 + (at.Y - spot.y) ^ 2) / CM_PER_M
end

-- A distance the World Beacons way: "24 m" under a kilometre, "1.15 km" from there.
local function distanceWords(metres)
    if metres >= 1000 then return string.format("%.2f km", metres / 1000) end
    return string.format("%.0f m", metres)
end

-- Straight-line metres from the player to a plant's marker spot.
local function metresTo(at, spot)
    return math.sqrt((at.X - spot.x) ^ 2 + (at.Y - spot.y) ^ 2 + (at.Z - spot.z) ^ 2) / CM_PER_M
end

-- Puts the distance on a shown marker, only when the words change.
local function showDistance(key, at)
    local words = distanceWords(metresTo(at, known[key]))
    local text = textOf[key]
    if words ~= wordsNow[key] and ctx.valid(text) and pcall(function() text:SetText(FText(words)) end) then
        wordsNow[key] = words
    end
end

-- Shows a marker only when its plant is within the marker range and not known to be without seeds, with its distance.
local function applyVisibility()
    local at, range = playerAt(), ctx.markerRange()
    for key, comp in pairs(made) do
        local hide = not at or metresBetween(at, known[key]) > range or seedsLeft[key] == 0
        if not hide then showDistance(key, at) end
        if hide ~= (hiddenNow[key] == true) and ctx.valid(comp) and pcall(function() comp:SetHiddenInGame(hide, false) end) then
            hiddenNow[key] = hide or nil
        end
    end
end

-- One pass: save new plant positions, give up to NEW_MARKERS_PER_PASS plants without one a marker, then show only
-- the markers in range on plants with seeds.
function M.pass()
    recordSpawners()
    local pc = FindFirstOf("PlayerController")
    if not (ctx.valid(pc) and currentHost(pc)) then return end
    local added = 0
    for _, key in ipairs(order) do
        if added >= NEW_MARKERS_PER_PASS then break end
        if not ctx.valid(made[key]) then
            local ok, comp = pcall(addMarker, pc, key)
            if ok then made[key] = comp; added = added + 1
            else
                failures = failures + 1
                if failures <= FAILURES_TO_LOG then ctx.log("marker failed " .. key .. ": " .. tostring(comp)) end
                break
            end
        end
    end
    if added > 0 then
        local count = 0
        for _ in pairs(made) do count = count + 1 end
        ctx.log(string.format("markers: %d added (%d shown of %d known)", added, count, #order))
    end
    applyVisibility()
end

function M.start(context)
    ctx = context
    loadPositions()
    ctx.log(string.format("markers: %d plant positions loaded from %s", #order, POSITIONS_FILE))
end

return M
