-- Simple CatV5 loader with offline-safe whitelist override
-- Keeps developer mode OFF; avoids network/whitelist crashes.

repeat task.wait() until game:IsLoaded()

-- Tiny helpers
local function ensure_folder(path)
    pcall(function() if not isfolder(path) then makefolder(path) end end)
end
local function write_safe(path, data)
    pcall(function() writefile(path, data) end)
end

-- Non-dev path so main.lua auto-downloads the game script for the current PlaceId
shared.VapeDeveloper = false
getgenv().catvapedev = false

-- Ensure folders + commit seed for main.lua downloader
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
ensure_folder("catrewrite/libraries")
write_safe("catrewrite/profiles/commit.txt", "main")
write_safe("catreset", "True")

-- Offline-safe whitelist stub: no network, no hard deps on shared.vape
do
    local stub = [[
-- OFFLINE/SAFE whitelist: everyone is "guest"
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
getgenv().catuser = getgenv().catuser or (lp and lp.Name) or "Guest"
shared.CatRank = "guest"

local W = {
    customtags = {},
    ignores = {},
    data = {
        WhitelistedUsers = {},
        BlacklistedUsers = {},
        Announcement = {expiretime = 0, targets = "all", text = ""}
    },
    localprio = 0,
    said = {}
}

-- Minimal API surface used across the codebase
function W:get(_) return 0, true, nil end -- level 0, attackable true, no tags
function W:isingame() return false end
function W:tag(_, text) return text and "" or {} end
function W:update() return true end
function W.GetRank(_) return "guest" end
function W.IsWhitelisted(_) return false end
function W.GetUserData(uid) return { rank = "guest", name = tostring(uid) } end
W.commands = {}

-- Publish globally; only touch vape if it exists
shared.CatWhitelist = W
_G.whitelist = W
whitelist = W
local ok, vape = pcall(function() return shared.vape end)
if ok and vape and vape.Libraries then
    vape.Libraries.whitelist = W
    vape.Libraries.CatWhitelisted = false
end

return W
]]
    write_safe("catrewrite/libraries/whitelist.lua", stub)
end

-- Fetch and run main.lua directly from your repo
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

return f(...)
