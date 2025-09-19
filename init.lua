-- CatV5 init with offline whitelist and safe BedWars loading
-- Strategy:
-- 1) Start in DEV mode so main.lua will NOT overwrite our local whitelist.lua
-- 2) Drop a safe offline whitelist.lua that sets everyone to "guest" and then flips DEV mode OFF
-- 3) Run main.lua (it will now fetch the game script remotely because DEV is OFF after whitelist loads)

repeat task.wait() until game:IsLoaded()

-- Helpers
local function ensure_folder(path)
    pcall(function() if not isfolder(path) then makefolder(path) end end)
end
local function write_safe(path, data)
    pcall(function() writefile(path, data) end)
end

-- 1) Begin with DEV ON so our local whitelist is honored by downloadFile
shared.VapeDeveloper = true
getgenv().catvapedev = true

-- Seed folders/files main.lua expects
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
ensure_folder("catrewrite/libraries")
write_safe("catrewrite/profiles/commit.txt", "main")
write_safe("catreset", "True")

-- 2) Safe offline whitelist stub (no network, no hard deps)
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

-- Minimal API
function W:get(_) return 0, true, nil end  -- level 0, attackable, no tags
function W:isingame() return false end
function W:tag(_, text) return text and "" or {} end
function W:update() return true end
function W.GetRank(_) return "guest" end
function W.IsWhitelisted(_) return false end
function W.GetUserData(uid) return { rank = "guest", name = tostring(uid) } end
W.commands = {}

-- Publish globals safely
shared.CatWhitelist = W
_G.whitelist = W
whitelist = W

-- Only touch vape if it exists
local ok, vape = pcall(function() return rawget(shared, "vape") end)
if ok and vape and vape.Libraries then
    vape.Libraries.whitelist = W
    vape.Libraries.CatWhitelisted = false
end

-- IMPORTANT: flip DEV OFF so main.lua will fetch the game script next
shared.VapeDeveloper = false
getgenv().catvapedev = false

return W
]]
    write_safe("catrewrite/libraries/whitelist.lua", stub)
end

-- 3) Fetch and run main.lua from your repo
local ok, src = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua", true)
end)
if not ok or not src or src == "" then
    return warn("CatV5 init: Failed to fetch main.lua")
end

local f, err = loadstring(src, "main")
if not f then
    return warn("CatV5 init: loadstring error: " .. tostring(err))
end

return f(...)
