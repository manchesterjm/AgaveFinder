-- NBS Settings client 1.1 - Copyright (c) 2026 Null Boundary Studios.
-- PERMISSION: any mod author may copy this one file, unchanged, into their own mod (free or paid) so the mod shows up
-- in the NBS Settings menu. Keep this header. Do not ship a changed copy under this name. (This permission covers this
-- file only; the rest of NBS Settings stays under its COPYRIGHT.txt.)
--
-- What it does: publishes your mod (name, version, settings file, help file, status, warnings) to the NBS Settings
-- menu through UE4SS shared variables, and answers the menu's "apply" requests by calling your onApply. Optionally
-- also to the Mod Settings menu (NckDotCom) - same settings file. No hooks, no key binds, no delayed actions: call
-- client:step() from your mod's own loop. Without NBS Settings installed it costs one shared-variable read per call.
--
-- Use (see MODDERS.md and example.ini next to this file):
--   local NBS = require('nbs_settings_client')
--   local settings = NBS.new({
--       id = 'MyMod',                 -- your mod.json id
--       name = 'My Mod',              -- your mod.json name
--       version = '1.0.0',
--       author = 'Your Name',
--       folder = 'MyMod',             -- your folder under Mods
--       ini = 'mymod.ini',            -- your settings file, relative to your mod folder (annotated: see example.ini)
--       help = 'help.txt',            -- optional: help text for the Help page ('# Title' lines start topics)
--       modsettings = true,           -- optional: also offer the file to Mod Settings (needs: ini in the mod root,
--                                     -- types boolean / integer / number / keybind only, values true/false)
--       onApply = function(menu)      -- optional: the menu changed your ini - re-read it and apply. Return true, or
--           reloadMySettings()        -- false, 'why' to show the player why it could not be applied. Without
--           return true               -- onApply every change is marked "restart the game".
--       end,
--   })
--   -- in your mod's loop (every pass is fine):
--   settings:step()
--   settings:status('on')                         -- 'on' | 'part' | 'off' | 'error', and a short detail
--   settings:status('off', 'game build not recognised')
--   settings:warn('Pad 2: no Welding Wire found')  -- shows on the Status & debug page (last 20 kept)
--
-- Optional extras:
--   actions = { { id = 'position', label = 'Change position...', description = '...' } },   -- buttons in the menu
--   onAction = function(id) ... end                -- a button was pressed (runs in your loop pass)
--   settings:fileChanged()                         -- you rewrote your own ini: the menu reloads it
--   NBS.menuOpen()                                 -- true while the NBS menu is open (show a live preview)
local M = { VERSION = '1.1' }
local NBS = 'NBS/Settings/v1/'
local MS = 'NckDotCom/ModSettings/v2/'
local KEEP_WARN = 20

local function json(v)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[%c\\"]', function(c)
            if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n' end
            return string.format('\\u%04x', c:byte())
        end) .. '"'
    elseif t == 'boolean' then return v and 'true' or 'false'
    elseif t == 'number' then return tostring(v)
    elseif t == 'table' then
        if #v > 0 then
            local items = {}
            for _, x in ipairs(v) do items[#items + 1] = json(x) end
            return '[' .. table.concat(items, ',') .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = json(tostring(k)) .. ':' .. json(v[k]) end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    return 'null'
end

local function modref()
    return {
        get = function(k) return ModRef:GetSharedVariable(k) end,
        set = function(k, v) ModRef:SetSharedVariable(k, v) end,
    }
end

local function listOnce(sv, key, id)
    local list = sv.get(key) or ''
    for o in list:gmatch('[^;]+') do if o == id then return end end
    sv.set(key, list .. id .. ';')
end

local function bump(sv, key) sv.set(key, (tonumber(sv.get(key)) or 0) + 1) end

function M.new(o)
    assert(type(o) == 'table' and type(o.id) == 'string' and o.id:match('^[%w_-]+$'), 'nbs_settings_client: id')
    local c = { o = o, sv = o.shared or modref(), published = false, last = {}, warnings = {}, warnCount = 0 }

    local function publish()
        local sv = c.sv
        sv.set(NBS .. o.id .. '/info', json({ id = o.id, name = o.name or o.id, version = o.version or '',
            author = o.author or '', folder = o.folder or o.id, ini = o.ini or '', help = o.help or '',
            apply = o.onApply ~= nil, actions = o.actions }))
        listOnce(sv, NBS .. 'mods', o.id)
        c.last.nbs = tonumber(sv.get(NBS .. o.id .. '/request')) or 0
        c.last.action = tonumber(sv.get(NBS .. o.id .. '/action-n')) or 0
        if o.modsettings and o.ini and not o.ini:find('[/\\]') then
            sv.set(MS .. o.id .. '/descriptor', json({ id = o.id, name = o.name or o.id, folder = o.folder or o.id,
                file = o.ini, callback = o.onApply ~= nil }))
            listOnce(sv, MS .. 'owners', o.id)
            bump(sv, MS .. 'owners-revision')
            c.last.ms = tonumber(sv.get(MS .. o.id .. '/request')) or 0
        end
        if c.state then sv.set(NBS .. o.id .. '/status', json({ state = c.state, detail = c.detail or '' })) end
        bump(sv, NBS .. 'rev')
        c.published = true
    end

    local function answer(prefix, which)
        local sv = c.sv
        local r = tonumber(sv.get(prefix .. o.id .. '/request')) or 0
        if r == c.last[which] then return end
        c.last[which] = r
        local ok, why = true, nil
        if o.onApply then
            local called, a, b = pcall(o.onApply, sv.get(prefix .. o.id .. '/request-menu'))
            if not called then ok, why = false, tostring(a) elseif a == false then ok, why = false, b end
        end
        sv.set(prefix .. o.id .. '/reply', ok and json({ state = 'complete', value = { saved = true } })
            or json({ state = 'failed', error = { message = tostring(why or 'could not apply the settings') } }))
        sv.set(prefix .. o.id .. '/ack', r)
    end

    -- call every pass of your loop
    function c:step()
        if not self.published then publish() return end
        answer(NBS, 'nbs')
        if self.last.ms then answer(MS, 'ms') end
        local a = tonumber(self.sv.get(NBS .. o.id .. '/action-n')) or 0
        if a ~= self.last.action then
            self.last.action = a
            if o.onAction then pcall(o.onAction, self.sv.get(NBS .. o.id .. '/action')) end
        end
    end

    -- you rewrote your own settings file: the menu reloads it
    function c:fileChanged()
        bump(self.sv, NBS .. o.id .. '/ini-rev')
        bump(self.sv, NBS .. 'rev')
    end

    -- 'on' | 'part' | 'off' | 'error', detail text
    function c:status(state, detail)
        if self.state == state and self.detail == (detail or '') then return end
        self.state, self.detail = state, detail or ''
        if self.published then
            self.sv.set(NBS .. o.id .. '/status', json({ state = state, detail = self.detail }))
            bump(self.sv, NBS .. 'rev')
        end
    end

    -- one warning line for the Status & debug page
    function c:warn(text)
        local line = os.date('%H:%M:%S') .. '  ' .. tostring(text):gsub('[\r\n]+', ' ')
        self.warnings[#self.warnings + 1] = line
        if #self.warnings > KEEP_WARN then table.remove(self.warnings, 1) end
        self.warnCount = self.warnCount + 1
        self.sv.set(NBS .. o.id .. '/warn', table.concat(self.warnings, '\n'))
        self.sv.set(NBS .. o.id .. '/warn-n', self.warnCount)
    end

    return c
end

-- true while the NBS menu is open (for a live preview of your settings)
function M.menuOpen(shared)
    local sv = shared or modref()
    return tonumber(sv.get(NBS .. 'open')) == 1
end

return M
