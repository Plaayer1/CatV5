-- CatV5 init with Luau FS shim, safe re-inject, main.lua patch, and offline whitelist

repeat task.wait() until game:IsLoaded()

-- 0) Make re-inject safe: wrap any existing Uninject in pcall so main.lua line 2 can't hard-crash.
do
    local v = rawget(shared, "vape")
    if v and type(v.Uninject) == "function" then
        local old = v.Uninject
        v.Uninject = function(self, ...)
            local ok, err = pcall(old, self, ...)
            if not ok then
                warn("Safe Uninject caught error:", err)
            end
        end
    end
end

-- 1) Luau-compatible virtual filesystem shim for environments without file APIs
do
    local env = (getgenv and getgenv()) or _G
    env.__catfs = env.__catfs or { files = {}, folders = {} }
    local FS = env.__catfs

    local function ensure(name, func)
        if type(env[name]) ~= "function" then
            env[name] = func
        end
    end

    ensure("isfolder", function(path)
        return FS.folders[path] == true
    end)
    ensure("makefolder", function(path)
        FS.folders[path] = true
    end)
    ensure("delfile", function(path)
        FS.files[path] = nil
    end)
    ensure("isfile", function(path)
        return FS.files[path] ~= nil and FS.files[path] ~= ""
    end)
    ensure("writefile", function(path, data)
        FS.files[path] = tostring(data or "")
    end)
    ensure("readfile", function(path)
        local v = FS.files[path]
        if v == nil then error("readfile: no such file " .. tostring(path)) end
        return v
    end)
    -- Nice-to-have stubs
    if type(env.setfpscap) ~= "function" then env.setfpscap = function() end end
    if type(env.queue_on_teleport) ~= "function" then env.queue_on_teleport = function() end end
    if type(env.cloneref) ~= "function" then env.cloneref = function(o) return o end end
end

-- 2) Helpers that work with either real FS or shim
local function ensure_folder(path)
    if not isfolder(path) then
        makefolder(path)
    end
end
local function write_safe(path, data)
    local ok, err = pcall(function() writefile(path, data) end)
    if not ok then warn("write_safe failed for " .. tostring(path) .. ": " .. tostring(err)) end
end
local function delete_safe(path)
    pcall(function() delfile(path) end)
end

-- 3) Start with DEV ON so main.lua uses our local whitelist.lua
shared.VapeDeveloper = true
getgenv().catvapedev = true

-- 4) Seed folders/files main.lua expects
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
ensure_folder("catrewrite/libraries")
write_safe("catrewrite/profiles/commit.txt", "main")
write_safe("catreset", "True")

-- 5) Offline-safe whitelist stub (no network, no early vape refs). Flip DEV OFF inside.
do
    local path = "catrewrite/libraries/whitelist.lua"
    delete_safe(path)
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

-- Minimal API used elsewhere
function W:get(_) return 0, true, nil end  -- level 0, attackable, no tags
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
local ok, vape = pcall(function() return rawget(shared, "vape") end)
if ok and vape and vape.Libraries then
    vape.Libraries.whitelist = W
    vape.Libraries.CatWhitelisted = false
end

-- Flip DEV OFF now so game script downloads normally after whitelist loads
shared.VapeDeveloper = false
getgenv().catvapedev = false

return W
]]
    write_safe(path, stub)
end

-- 6) Fetch main.lua
local ok, src = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua", true)
end)
if not ok or not src or src == "" then
    warn("CatV5 init: Failed to fetch main.lua: " .. tostring(src))
    return
end

-- 7) Patch main.lua for Luau/executor compatibility:
--    - Fix recursive local loadstring wrapper by redirecting to original executor loadstring
do
    -- Redirect the call inside the wrapper from "loadstring(" to a safe original
    -- Only patch the first occurrence, which is the wrapper's line: "local res, err = loadstring(...)".
    local patched, count = src:gsub(
        "local%s+res,%s*err%s*=%s*loadstring%(",
        "local __cat_orig_load = (getgenv and getgenv().loadstring) or (_G and _G.loadstring) or loadstring\n    local res, err = __cat_orig_load(",
        1
    )
    if count > 0 then src = patched end
end

-- 8) Compile and run main.lua
local chunk, err = loadstring(src, "main")
if not chunk then
    warn("CatV5 init: loadstring error: " .. tostring(err))
    return
end

return chunk(...)
