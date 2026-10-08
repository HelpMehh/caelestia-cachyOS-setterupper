-- caelestia-setup: Hyprland additions shared by every machine.
--
-- Loaded by the first line of ~/.config/caelestia/hypr-user.lua. Nothing in
-- here names a particular monitor, user or path: anything specific to one
-- computer lives in ~/.config/caelestia/machines/<hostname>.lua, which
-- `caelestia-setup monitors` writes, and anything personal goes in
-- hypr-user.lua after the line that loads this file.

local home = os.getenv("HOME") or ""
local cfg  = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/caelestia"
local lib  = "/usr/local/lib/caelestia-setup"

local function exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function hostname()
    local f = io.open("/etc/hostname", "r")
    if not f then return nil end
    local name = f:read("*l")
    f:close()
    if name and name:match("^[%w%-_.]+$") then return name end
    return nil
end

-- Wallpapers kept with the config (so they are backed up with it). Both the
-- shell's wallpaper picker and `caelestia wallpaper -r` honour this variable.
if exists(cfg .. "/wallpapers") then
    hl.env("CAELESTIA_WALLPAPERS_DIR", cfg .. "/wallpapers")
end

-- This computer's monitor layout, if one has been saved. Without it,
-- Caelestia's default applies: every monitor at its preferred mode, placed
-- automatically.
local host = hostname()
if host and exists(cfg .. "/machines/" .. host .. ".lua") then
    dofile(cfg .. "/machines/" .. host .. ".lua")
end

-- Sunshine: keys held on the streaming device shouldn't auto-repeat while
-- the stream stutters.
hl.device({
    name = "libvirtualhid-keyboard",
    repeat_delay = 1000,
})

-- Sunshine: a config reload (every wallpaper change causes one) wipes the
-- monitor rules sunshine-vd-start set, which would turn the real monitors
-- back on mid-stream. Re-apply its state file while the virtual display
-- exists.
do
    local state = (os.getenv("XDG_RUNTIME_DIR") or "") .. "/sunshine_vd.lua"
    if exists(state) then
        local ok, vd = pcall(hl.get_monitor, "sunshine_vd")
        if not ok or vd then
            pcall(dofile, state)
        end
    end
end

-- Grids for Caelestia's special workspaces (Super+D and the like).
--
-- Hyprland's usual layout splits whichever window has focus when a new one
-- appears, and a workspace's apps start together and finish loading in a
-- different order each time -- so the arrangement changes every time. A
-- workspace listed under "grids" in extras.json gets a fixed grid instead:
--
--   "grids": { "communication": ["gmail", "instagram", "whatsapp", "discord"] }
--
-- The names are the apps of that workspace in cli.json's "toggles" (their
-- "match" rules find the windows); a name not found there is looked for in
-- the window's class. Windows fill the grid in that order, left to right and
-- top to bottom; other windows follow in the order they opened. The grid is
-- as square as possible, and a shorter last row is stretched to fill.
-- Changes apply on `hyprctl reload`.
do
    local ok_json, json = pcall(require, "utils.json")

    local function read_json(path)
        if not ok_json then return nil end
        local f = io.open(path, "r")
        if not f then return nil end
        local text = f:read("a")
        f:close()
        local ok, value = pcall(json.decode, text)
        if ok and type(value) == "table" then return value end
        return nil
    end

    -- Like Caelestia's toggles: every key of a rule must be found (as plain
    -- text, ignoring case) in the window's property of that name; camelCase
    -- keys also try snake_case. Nested rules (a workspace, say) are skipped.
    local function property(window, key)
        local ok, value = pcall(function() return window[key] end)
        if ok and value ~= nil then return value end
        ok, value = pcall(function() return window[(key:gsub("(%u)", "_%1")):lower()] end)
        if ok then return value end
        return nil
    end

    local function rule_matches(window, rule)
        local compared = 0
        for key, want in pairs(rule) do
            if type(key) == "string" and type(want) ~= "table" then
                local have = property(window, key)
                if have == nil or not tostring(have):lower():find(tostring(want):lower(), 1, true) then return false end
                compared = compared + 1
            end
        end
        return compared > 0
    end

    local function rank(window, order)
        if window then
            for i, rules in ipairs(order) do
                for _, rule in ipairs(rules) do
                    if type(rule) == "table" and rule_matches(window, rule) then return i end
                end
            end
        end
        return #order + 1
    end

    local function grid(order)
        return {
            recalculate = function(ctx)
                local entries = {}
                for _, target in ipairs(ctx.targets) do
                    entries[#entries + 1] = { target = target, rank = rank(target.window, order), index = target.index }
                end
                table.sort(entries, function(a, b)
                    if a.rank ~= b.rank then return a.rank < b.rank end
                    return a.index < b.index
                end)

                local n = #entries
                local cols = math.ceil(math.sqrt(n))
                local rows = math.ceil(n / cols)
                local area = ctx.area
                for i, entry in ipairs(entries) do
                    local row = math.floor((i - 1) / cols)
                    local col = (i - 1) % cols
                    local in_row = (row == rows - 1) and (n - row * cols) or cols
                    local w, h = area.w / in_row, area.h / rows
                    entry.target:place({ x = area.x + col * w, y = area.y + row * h, w = w, h = h })
                end
            end,
        }
    end

    local extras = read_json(cfg .. "/extras.json")
    local grids = extras and type(extras.grids) == "table" and extras.grids or {}
    local toggles = (read_json(cfg .. "/cli.json") or {}).toggles
    if type(toggles) ~= "table" then toggles = {} end

    for workspace, apps in pairs(grids) do
        if type(workspace) == "string" and workspace:match("^[%w_-]+$") then
            local order = {}
            for _, app in ipairs(type(apps) == "table" and apps or {}) do
                if type(app) == "string" then
                    local conf = type(toggles[workspace]) == "table" and toggles[workspace][app] or nil
                    if type(conf) == "table" and type(conf.match) == "table" then
                        order[#order + 1] = conf.match
                    else
                        order[#order + 1] = { { class = app } }
                    end
                end
            end
            local name = "caelestia-setup-grid-" .. workspace
            local ok = pcall(hl.layout.register, name, grid(order))
            if ok then
                hl.workspace_rule({ workspace = "special:" .. workspace, layout = "lua:" .. name })
            end
        end
    end
end

-- Lock at login, wallpaper change and update notices (see bin/session-start).
hl.on("hyprland.start", function()
    hl.exec_cmd(lib .. "/bin/session-start")
end)
