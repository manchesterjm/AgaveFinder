-- Agave Finder - the distance to every Oodham agave (Saguaro) plant near you that has seeds, shown over the plant
-- and drawn through terrain. A plant without seeds shows nothing; its marker comes back when the plant regrows.
--
-- Grew out of Agave Respawn Fix (0.1.0-0.6.11, 2026-10-18), which tried to revive plants that stop regrowing. That part
-- was dropped (Josh: "I don't think it's worth it just to get three working when there's over 60 that actually are");
-- what stayed is the markers. History: Dune_Mod_Changelog.md "Agave Respawn Fix".
--
-- Parts: Scripts/markers.lua (positions, seeds, markers), dlls/main.dll (reads each plant's seeds; source + build
-- script in native/). Settings: mod.ini (Markers, MarkerRangeMeters), also in NBS Settings (F10) and Settings > Mods
-- when those menus are installed. Log: <mod folder>/agave_finder.log, started fresh each launch.
-- Game thread only (ExecuteInGameThreadWithDelay, never LoopAsync).

local SEP = string.char(92)
local MOD_ROOT = debug.getinfo(1, "S").source:gsub("^@", ""):gsub(SEP, "/"):match("^(.*)/Scripts/[^/]+%.lua$") or "."
local INI_PATH = MOD_ROOT .. "/mod.ini"
local LOG_PATH = MOD_ROOT .. "/agave_finder.log"
local VERSION = "1.1.0"
local markers = require("markers")

local SPAWNER_CLASS = "BP_Saguaro_Spawner_C"
local MARKER_PASS_S = 1
local WAIT_FOR_PLAYER_S = 2      -- also how often the menus are answered at the main menu (they wait 5 s)
local MS_PER_S = 1000
local MIN_MARKER_RANGE_M, MAX_MARKER_RANGE_M = 50, 2000
local ERRORS_TO_LOG = 20

local logFile = io.open(LOG_PATH, "w")
if logFile then logFile:close() end
local function log(msg)
    local f = io.open(LOG_PATH, "a")
    if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
end
local function valid(o) local ok, r = pcall(function() return o and o:IsValid() end); return ok and r == true end
local function try(f) local ok, v = pcall(f); if ok then return v end end

local cfg = { Markers = true, MarkerRangeMeters = 100 }
local function markerRange(n) return math.max(MIN_MARKER_RANGE_M, math.min(MAX_MARKER_RANGE_M, n)) end
local function readIni()
    local f = io.open(INI_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "Markers" then cfg.Markers = (v:lower() == "true" or v == "1") end
        if k == "MarkerRangeMeters" then
            local n = tonumber(v)
            if n then cfg.MarkerRangeMeters = markerRange(n) end
        end
    end
    f:close()
end

-- A UPROPERTY TArray element is the object itself; a function-returned one is wrapped and needs :get().
local function element(list, i)
    local e = try(function() return list[i] end)
    if valid(e) then return e end
    return try(function() return e:get() end)
end

local function playerAt()
    local pc = FindFirstOf("PlayerController")
    if valid(pc) and valid(pc.Pawn) then return try(function() return pc.Pawn:K2_GetActorLocation() end) end
end

-- The plant meshes (harvestable components) of one agave spawner.
local function harvestables(spawner)
    local comps = try(function() return spawner.m_HarvestableComponents end)
    local out = {}
    for c = 1, (try(function() return #comps end) or 0) do
        local comp = element(comps, c)
        if valid(comp) then out[#out + 1] = comp end
    end
    return out
end

readIni()
log(string.format("=== Agave Finder %s start: Markers=%s MarkerRangeMeters=%d ===", VERSION, tostring(cfg.Markers),
    cfg.MarkerRangeMeters))

-- A menu saved mod.ini: read it again; the marker loop switches markers on or off on its next pass.
local function applySettings()
    readIni()
    log(string.format("settings: Markers=%s MarkerRangeMeters=%d", tostring(cfg.Markers), cfg.MarkerRangeMeters))
    return true
end

-- Settings menus (optional): the NBS Settings client puts mod.ini in NBS Settings (F10) and in Mod Settings
-- (Settings > Mods), and calls applySettings when either one saves. With neither menu installed it does nothing.
local okClient, NBS = pcall(require, "nbs_settings_client")
local settings = okClient and NBS.new({
    id = "AgaveFinder", name = "Agave Finder", version = VERSION, author = "Josh",
    folder = MOD_ROOT:match("([^/]+)$") or "AgaveFinder", ini = "mod.ini", modsettings = true,
    onApply = applySettings,
}) or nil
log(settings and "settings menus: NBS Settings + Mod Settings" or ("settings menus unavailable: " .. tostring(NBS)))

local errors = 0
local function guarded(f)
    local ok, err = pcall(f)
    if not ok then errors = errors + 1; if errors <= ERRORS_TO_LOG then log("error: " .. tostring(err)) end end
end

-- Every pass of either loop: answer the menus and show on/off on NBS Settings' STATUS page.
local function serveMenus()
    if not settings then return end
    settings:status(cfg.Markers and "on" or "off", cfg.Markers and "" or "markers are switched off")
    settings:step()
end

-- One marker pass a second; turning markers off removes them.
local markersShown = false
local function markerLoop()
    guarded(serveMenus)
    if cfg.Markers then
        markersShown = true
        guarded(markers.pass)
    elseif markersShown then
        markersShown = false
        guarded(markers.removeAll)
    end
    ExecuteInGameThreadWithDelay(MARKER_PASS_S * MS_PER_S, markerLoop)
end

markers.start({ log = log, valid = valid, try = try, harvestables = harvestables, spawnerClass = SPAWNER_CLASS,
    modRoot = MOD_ROOT, markerRange = function() return cfg.MarkerRangeMeters end })

-- The mod loads at the main menu; markers start once the player character exists.
local function waitForPlayer()
    guarded(serveMenus)
    if playerAt() then
        log("player in world - markers on")
        markerLoop()
    else
        ExecuteInGameThreadWithDelay(WAIT_FOR_PLAYER_S * MS_PER_S, waitForPlayer)
    end
end
ExecuteInGameThreadWithDelay(WAIT_FOR_PLAYER_S * MS_PER_S, waitForPlayer)
