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

-- Lock at login, wallpaper change and update notices (see bin/session-start).
hl.on("hyprland.start", function()
    hl.exec_cmd(lib .. "/bin/session-start")
end)
