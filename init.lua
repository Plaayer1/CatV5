-- Simple CatV5 loader with in-memory OFFLINE whitelist (guest-only)
-- Keeps developer mode OFF to avoid crashes and let BedWars load automatically.
-- Does NOT write whitelist.lua to disk (to avoid overwrite/race issues). Instead, it injects a stub in memory.

repeat task.wait() until game:IsLoaded()

-- Ensure non-dev path so main.lua auto-downloads the game script for the current PlaceId
shared.VapeDeveloper = false
getgenv().catvapedev = false

-- Minimal helpers
local function ensure_folder(path)
    pcall(function() if not isfolder(path) then makefolder(path) end end)
end
local function write_safe(path, data)
    pcall(function() writefile(path, data) end)
end

-- Seed required folders/files for main.lua
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
write_safe("catrewrite/profiles/commit.txt", "main")
write_safe("catreset", "True")

-- OFFLINE whitelist (guest-only) injected in-memory (no file writes)
local function apply_offline_whitelist()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    getgenv().catuser = getgenv().catuser or (lp and lp.Name) or "Guest"
    shared.CatRank = "guest"

    local W = {}

    -- Core API used by scripts in this repo
    function W.GetRank(_) return "guest" end
    function W.IsWhitelisted(_) return false end
    function W.GetUserData(uid) return { rank = "guest", name = tostring(uid) } end

    -- Extra compatibility no-ops (harmless if unused)
    function W.get(_) return 0, true, nil end
    function W.isingame() return false end
    function W.tag(_, text) return text and "" or {} end
    function W.update() return true end
    W.commands = {}

    -- Publish globally
    shared.CatWhitelist = W
    _G.whitelist = W
    whitelist = W

    -- If Vape libs exist after main loads, wire them too
    local vape = rawget(shared, "vape")
    if vape and vape.Libraries then
        vape.Libraries.whitelist = W
    end

    return W
end

-- Apply once before main (in case anything checks it early)
apply_offline_whitelist()

-- Fetch and run main.lua directly (stable path)
local ok, src = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua", true)
end)
if not ok or not src or src == "" then
    error("CatV5 init: Failed to fetch main.lua")
end

local f, err = loadstring(src, "main")
if not f then
    error("CatV5 init: loadstring error: "..tostring(err))
end

-- Run main.lua
local ret
local ran, runErr = pcall(function()
    ret = f(...)
end)

-- Re-apply after main (in case main replaced it)
apply_offline_whitelist()

-- Keep it enforced briefly to win any late init races
task.spawn(function()
    for _ = 1, 20 do -- ~10 seconds total
        apply_offline_whitelist()
        task.wait(0.5)
    end
end)

if not ran then
    error("CatV5 init: main.lua runtime error: "..tostring(runErr))
end

return ret
