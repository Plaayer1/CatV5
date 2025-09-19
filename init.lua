-- Force developer mode so local files are preferred and not overwritten by remote fetches.
-- This ensures our offline whitelist stub (written below) is used by main.lua.
getgenv().catvapedev = (getgenv().catvapedev ~= nil) and getgenv().catvapedev or true

local license = ({...})[1] or {}
local developer = getgenv().catvapedev or license.Developer or false
local closet = getgenv().closet or license.Closet or false

if license.User then
    getgenv().catuser = license.User
end

local cloneref = cloneref or function(ref) return ref end
local CoreGui = cloneref(game:GetService('CoreGui'))
local Players = cloneref(game:GetService('Players'))
local function safe_gethui()
    local ok, res = pcall(function()
        return (gethui and gethui()) or Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass('PlayerGui') or CoreGui
    end)
    return ok and res or CoreGui
end

-- Minimal, non-crashy overlay
local overlayParent = safe_gethui()
local gui = Instance.new('ScreenGui')
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Name = 'cat_init_overlay'
gui.Parent = overlayParent

local downloader = Instance.new('TextLabel', gui)
downloader.Size = UDim2.new(1, 0, 0, 18)
downloader.Position = UDim2.new(0, 0, 0, 0)
downloader.BackgroundTransparency = 1
downloader.TextStrokeTransparency = 0
downloader.TextSize = (not closet and 18) or 1
downloader.Text = 'Initializing...'
downloader.TextColor3 = Color3.new(1, 1, 1)
downloader.Font = Enum.Font.Arial

local httpService = cloneref(game:GetService('HttpService'))

-- Point everything to your fork
local GITHUB_OWNER = "Plaayer1"
local GITHUB_REPO = "CatV5"

local function gh(url)
    return "https://api.github.com/repos/"..GITHUB_OWNER.."/"..GITHUB_REPO..url
end

local function isfile_safe(path)
    local ok, res = pcall(function() return readfile(path) end)
    return ok and res ~= nil and res ~= ''
end

local function readfile_safe(path, default)
    local ok, res = pcall(function() return readfile(path) end)
    return ok and res or default
end

local function writefile_safe(path, contents)
    pcall(function() writefile(path, contents) end)
end

local function makefolder_safe(path)
    pcall(function() if not isfolder(path) then makefolder(path) end end)
end

local function get_commit_txt()
    if isfile_safe('catrewrite/profiles/commit.txt') then
        return readfile_safe('catrewrite/profiles/commit.txt', 'main')
    end
    return 'main'
end

local function set_commit_txt(sha)
    makefolder_safe('catrewrite/profiles')
    writefile_safe('catrewrite/profiles/commit.txt', sha)
end

local function raw(path)
    local commit = get_commit_txt()
    return "https://raw.githubusercontent.com/"..GITHUB_OWNER.."/"..GITHUB_REPO.."/"..commit.."/"..path
end

local function httpget(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then return nil end
    if res == '404: Not Found' then return nil end
    return res
end

local function gh_json(url)
    local txt = httpget(url)
    if not txt then return nil end
    local ok, obj = pcall(function() return httpService:JSONDecode(txt) end)
    return ok and obj or nil
end

-- Discover latest commit, but be resilient to API/rate-limit failures
downloader.Text = 'Checking updates...'
local commitdata = gh_json(gh("/commits"))
local sha = 'main'
if commitdata and commitdata[1] and commitdata[1].sha then
    sha = commitdata[1].sha
else
    -- fallback to existing or main
    sha = get_commit_txt()
end
set_commit_txt(sha)

writefile_safe('catreset', 'True')

local function downloadFile(path, reader)
    if not isfile_safe(path) then
        local remotePath = path:gsub('^catrewrite/', '')
        remotePath = remotePath:gsub(' ', '%%20')
        local url = raw(remotePath)
        local res = httpget(url)
        if not res then
            -- keep going without crashing
            return nil
        end
        if path:find('%.lua$') then
            res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
        end
        writefile_safe(path, res)
    end
    return (reader or readfile_safe)(path)
end

local function wipeFolder(path)
    if not isfolder(path) then return end
    local ok, files = pcall(function() return listfiles(path) end)
    if not ok or not files then return end
    for _, file in ipairs(files) do
        if tostring(file):find('loader') then
            -- keep loader files
        else
            local okRead, contents = pcall(function() return readfile(file) end)
            if okRead and contents and contents:sub(1, 99):find('This watermark is used to delete the file') then
                writefile_safe(file, '')
            end
        end
    end
end

-- Ensure base folders exist
for _, folder in ipairs({
    'catrewrite',
    'catrewrite/communication',
    'catrewrite/games',
    'catrewrite/games/bedwars',
    'catrewrite/profiles',
    'catrewrite/assets',
    'catrewrite/libraries',
    'catrewrite/libraries/Enviroments',
    'catrewrite/guis'
}) do
    makefolder_safe(folder)
end

-- First-run profile/translations fetch (safe)
do
    local needsSeed = (not isfile_safe('catrewrite/profiles/commit.txt'))
    if needsSeed then
        set_commit_txt(sha)
        local profiles = gh_json(gh('/contents/profiles')) or {}
        for _, v in ipairs(profiles) do
            if v.path ~= 'profiles/commit.txt' then
                downloader.Text = 'Downloading catrewrite/'..tostring(v.path)
                downloadFile('catrewrite/'..tostring(v.path))
            end
        end
        task.spawn(function()
            local translations = gh_json(gh('/contents/translations')) or {}
            for _, v in ipairs(translations) do
                downloadFile('catrewrite/'..tostring(v.path))
            end
        end)
    end
end

-- Offline whitelist stub (guest-only) injected before main.lua loads.
-- Because developer mode is true, main.lua will prefer this local file and won't overwrite it.
do
    local whitelistPath = "catrewrite/libraries/whitelist.lua"
    local stub = [[
-- Offline whitelist (no network, no Discord/API).
-- Everyone is treated as "guest" and not whitelisted.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
getgenv().catuser = (lp and lp.Name) or "Guest"
shared.CatRank = "guest"
local M = {}
function M.GetRank(_) return "guest" end
function M.IsWhitelisted(_) return false end
function M.GetUserData(uid) return { rank = "guest", name = tostring(uid) } end
shared.CatWhitelist = M
_G.whitelist = M
whitelist = M
return M
]]
    writefile_safe(whitelistPath, stub)
end

shared.VapeDeveloper = developer
getgenv().used_init = true
getgenv().catvapedev = developer
getgenv().closet = closet

if closet then
    task.spawn(function()
        repeat
            for _, v in getconnections(game:GetService('LogService').MessageOut) do pcall(function() v:Disable() end) end
            for _, v in getconnections(game:GetService('ScriptContext').Error) do pcall(function() v:Disable() end) end
            task.wait(0.5)
        until not shared.VapeDeveloper or not getgenv().closet
    end)
end

downloader.Text = 'Preparing assets...'

-- With developer mode enabled, local files are preserved; no wipe on version changes.
if not shared.VapeDeveloper then
    local commit = sha or 'main'
    if commit == 'main' or readfile_safe('catrewrite/profiles/commit.txt', '') ~= commit then
        wipeFolder('catrewrite')
        wipeFolder('catrewrite/games')
        wipeFolder('catrewrite/guis')
        wipeFolder('catrewrite/libraries')
    end
    writefile_safe('catrewrite/cheaters.json', '{}')
    set_commit_txt(commit)
end

-- Ensure the current game's script exists locally so main.lua will load it in developer mode.
do
    local function ensureGameFile(placeId)
        local path = 'catrewrite/games/'..placeId..'.lua'
        if not isfile_safe(path) then
            local res = httpget(raw('games/'..placeId..'.lua'))
            if res then
                res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
                writefile_safe(path, res)
            end
        end
    end

    -- Always fetch the active PlaceId first
    ensureGameFile(tostring(game.PlaceId))

    -- Known BedWars place ids (lobby/variants) as fallbacks
    for _, pid in ipairs({
        '6872274481', -- BedWars match
        '6872265039', -- BedWars lobby
        '8444591321',
        '8542275097',
        '8560631822',
        '11156779721',
        '11630038968',
        '12011959048',
        '13246639586',
        '14191889582',
        '14662411059',
        '17750024818',
        '79695841807485',
        '95004353881831'
    }) do
        if tostring(game.PlaceId) ~= pid then
            ensureGameFile(pid)
        end
    end
end

downloader.Text = 'Loading Cat Rewrite...'

-- Load main
local mainLoaded = downloadFile('catrewrite/main.lua', function(p)
    return readfile_safe(p)
end)
if mainLoaded and mainLoaded ~= '' then
    local ok, err = pcall(function()
        loadstring(mainLoaded, 'main')()
    end)
    if not ok then
        downloader.Text = 'Main load error: '..tostring(err)
    end
else
    downloader.Text = 'Failed to load main.lua'
end

task.delay(2, function()
    if gui and gui.Parent then
        gui:Destroy()
    end
end)
