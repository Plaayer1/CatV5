-- CatV5 init (Luau-safe) with in-memory whitelist override and safe reinject

repeat task.wait() until game:IsLoaded()

-- 0) Safe re-inject: guard any existing Uninject to avoid hard crash at main.lua:2
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

-- 1) Minimal Luau FS shim (only if your executor doesn't provide these)
do
    local env = (getgenv and getgenv()) or _G
    env.__catfs = env.__catfs or { files = {}, folders = {} }
    local FS = env.__catfs

    local function ensure(name, func)
        if type(env[name]) ~= "function" then env[name] = func end
    end

    ensure("isfolder", function(path) return FS.folders[path] == true end)
    ensure("makefolder", function(path) FS.folders[path] = true end)
    ensure("delfile", function(path) FS.files[path] = nil end)
    ensure("isfile", function(path) return FS.files[path] ~= nil and FS.files[path] ~= "" end)
    ensure("writefile", function(path, data) FS.files[path] = tostring(data or "") end)
    ensure("readfile", function(path)
        local v = FS.files[path]
        if v == nil then error("readfile: no such file " .. tostring(path)) end
        return v
    end)
    if type(env.setfpscap) ~= "function" then env.setfpscap = function() end end
    if type(env.queue_on_teleport) ~= "function" then env.queue_on_teleport = function() end end
    if type(env.cloneref) ~= "function" then env.cloneref = function(o) return o end end
end

-- 2) Prepare main.lua expectations
local function ensure_folder(path)
    if not isfolder(path) then makefolder(path) end
end
ensure_folder("catrewrite")
ensure_folder("catrewrite/profiles")
ensure_folder("catrewrite/libraries")
if not isfile("catrewrite/profiles/commit.txt") then
    writefile("catrewrite/profiles/commit.txt", "main")
end
writefile("catreset", "True")

-- 3) Enable DEV so main.lua will prefer local whitelist over remote
shared.VapeDeveloper = true
getgenv().catvapedev = true

-- 4) In-memory whitelist override (no file/network). We intercept readfile/isfile for this exact path.
local WL_PATH = "catrewrite/libraries/whitelist.lua"
local WL_STUB = [[
-- OFFLINE/SAFE whitelist: everyone is "guest", no network, no chat hooks
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
function W:get(_) return 0, true, nil end  -- level 0, can-attack, no tag
function W:isingame() return false end
function W:tag(_, text) return text and "" or {} end
function W:update() return true end
function W.GetRank(_) return "guest" end
function W.IsWhitelisted(_) return false end
function W.GetUserData(uid) return { rank = "guest", name = tostring(uid) } end
W.commands = {}

-- Publish and mirror into vape if present
shared.CatWhitelist = W
_G.whitelist = W
whitelist = W
local ok, vape = pcall(function() return rawget(shared, "vape") end)
if ok and vape then
    vape.Libraries = vape.Libraries or {}
    vape.Libraries.whitelist = W
    vape.Libraries.CatWhitelisted = true
end

-- IMPORTANT: Flip DEV OFF so game scripts download normally after this module finishes loading
shared.VapeDeveloper = false
getgenv().catvapedev = false

return W
]]

-- Wrap original isfile/readfile so only the whitelist path is served from memory
do
    local _isfile, _readfile = isfile, readfile
    isfile = function(path)
        if tostring(path) == WL_PATH then return true end
        return _isfile(path)
    end
    readfile = function(path)
        if tostring(path) == WL_PATH then return WL_STUB end
        return _readfile(path)
    end
end

-- 5) Fetch main.lua and patch its local loadstring wrapper to avoid recursion on some executors
local ok, src = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua", true)
end)
if not ok or not src or src == "" then
    warn("CatV5 init: Failed to fetch main.lua: " .. tostring(src))
    return
end

-- Patch only the wrapper line: local res, err = loadstring(
do
    src = src:gsub(
        "local%s+res,%s*err%s*=%s*loadstring%(",
        "local __cat_orig_load = (getgenv and getgenv().loadstring) or (_G and _G.loadstring) or loadstring\n    local res, err = __cat_orig_load(",
        1
    )
end

local chunk, err = loadstring(src, "main")
if not chunk then
    warn("CatV5 init: loadstring error: " .. tostring(err))
    return
end

return chunk(...)
