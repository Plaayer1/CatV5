\-- Simple CatV5 loader with offline whitelist embedded
-- Goal:
-- 1) Force an offline "guest-only" whitelist (no network, no ranks)
-- 2) Ensure BedWars game script loads by providing a local game file
-- 3) Keep it simple and robust (no GitHub API calls)

repeat task.wait() until game:IsLoaded()

-- Simple safe I/O helpers
local function safe(p, f, ...)
    local ok, res = pcall(f, ...)
    return ok, res
end
local function ensure_folder(path)
    safe(path, function()
        if not isfolder(path) then makefolder(path) end
    end)
end
local function write_safe(path, data)
    safe(path, function() writefile(path, data) end)
end
local function read_safe(path, default)
    local ok, res = safe(path, function() return readfile(path) end)
    return ok and res or default
end
local function file_exists(path)
    local ok, res = safe(path, function() return readfile(path) end)
    return ok and res ~= nil and res ~= ""
end

-- Folders needed by main.lua
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
ensure_folder("catrewrite/games")
ensure_folder("catrewrite/libraries")

-- Seed commit to main so main.lua downloader works if needed
write_safe("catrewrite/profiles/commit.txt", "main")
write_safe("catreset", "True")

-- OFFLINE whitelist: everyone is "guest" (no network) and no ranks
do
    local stub = [[
-- OFFLINE whitelist: everyone is "guest" (no network)
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
getgenv().catuser = getgenv().catuser or (lp and lp.Name) or "Guest"
shared.CatRank = "guest"

local W = {
    customtags = {},
    data = {
        WhitelistedUsers = {},
        BlacklistedUsers = {},
        Announcement = {expiretime = 0, targets = "all", text = ""}
    },
    localprio = 0,
    said = {}
}

-- Match the basic interface universal.lua expects
function W:get(_) return 0, true, nil end       -- level 0, attackable true, no tags
function W:isingame() return false end
function W:tag(_, text, rich) return text and "" or {} end
function W:update() return true end
W.commands = {}

-- Publish everywhere
shared.CatWhitelist = W
_G.whitelist = W
whitelist = W

-- If vape is already around, wire it in
local vape = rawget(shared, "vape")
if vape and vape.Libraries then
    vape.Libraries.whitelist = W
end

return W
]]
    ensure_folder("catrewrite/libraries")
    write_safe("catrewrite/libraries/whitelist.lua", stub)
end

-- Provide a local BedWars game file so main.lua loads it in developer mode
do
    local placeId = tostring(game.PlaceId)
    local localGamePath = "catrewrite/games/"..placeId..".lua"
    if not file_exists(localGamePath) then
        local url = "https://raw.githubusercontent.com/Plaayer1/CatV5/main/games/"..placeId..".lua"
        local ok, src = pcall(function() return game:HttpGet(url, true) end)
        if ok and src and src ~= "" and src ~= "404: Not Found" then
            if localGamePath:find("%.lua$") then
                src = "--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n"..src
            end
            write_safe(localGamePath, src)
        end
        -- If this placeId is not BedWars (no file on repo), it's fine; universal will still load.
    end
end

-- IMPORTANT:
-- Turn ON developer mode so main.lua prefers local files.
-- This guarantees our offline whitelist (written above) is used and the local game file gets loaded.
shared.VapeDeveloper = true
getgenv().catvapedev = true

-- Fetch and run main.lua (from your repo main branch)
local ok, src = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua", true)
end)
if not ok or not src or src == "" then
    error("CatV5 init: Failed to fetch main.lua")
end

local chunk, err = loadstring(src, "main")
if not chunk then
    error("CatV5 init: loadstring error: "..tostring(err))
end

return chunk(...)
