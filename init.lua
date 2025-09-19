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
local gethui = gethui or function() return game:GetService('Players').LocalPlayer.PlayerGui end

local downloader = Instance.new('TextLabel', Instance.new('ScreenGui', gethui()))
downloader.Size = UDim2.new(1, 0, -0.08, 0)
downloader.BackgroundTransparency = 1
downloader.TextStrokeTransparency = 0
downloader.TextSize = (not closet and 20) or 0
downloader.Text = 'Downloading Nothing.'
downloader.TextColor3 = Color3.new(1, 1, 1)
downloader.Font = Enum.Font.Arial

local httpService = cloneref(game:GetService('HttpService'))

-- Point everything to your fork
local GITHUB_OWNER = "Plaayer1"
local GITHUB_REPO = "CatV5"

local function gh(url)
    return "https://api.github.com/repos/"..GITHUB_OWNER.."/"..GITHUB_REPO..url
end
local function raw(path)
    return "https://raw.githubusercontent.com/"..GITHUB_OWNER.."/"..GITHUB_REPO.."/"..readfile("catrewrite/profiles/commit.txt").."/"..path
end

local success, commitdata = pcall(function()
    local commitinfo = httpService:JSONDecode(game:HttpGet(gh("/commits")))[1]
    if commitinfo and type(commitinfo) == "table" then
        local fullinfo = httpService:JSONDecode(game:HttpGet(gh("/commits/".. commitinfo.sha)))
        fullinfo.hash = commitinfo.sha:sub(1, 7)
        return fullinfo
    end
end)

if not success or typeof(commitdata) ~= 'table' or commitdata.sha == nil then
	commitdata = {sha = 'main', files = {}}
end

writefile('catreset', 'True')

local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local function downloadFile(path, func)
	if not isfile(path) then
		local suc, res = pcall(function()
			local subbed = path:gsub('catrewrite/', ''):gsub(' ', '%%20')
			return game:HttpGet(raw(subbed), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('%.lua$') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

local function wipeFolder(path)
	if not isfolder(path) then return end
	for _, file in listfiles(path) do
		if file:find('loader') then continue end
		if isfile(file) and select(1, readfile(file):find('--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.')) == 1 then
			delfile(file)
		end
	end
end 

-- Ensure base folders exist
for _, folder in {
	'catrewrite',
	'catrewrite/communication',
	'catrewrite/games',
	'catrewrite/games/bedwars',
	'catrewrite/profiles',
	'catrewrite/assets',
	'catrewrite/libraries',
	'catrewrite/libraries/Enviroments',
	'catrewrite/guis'
} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

-- Seed commit and pull profiles/translations from your fork on first run
if not isfolder('catrewrite') or #listfiles('catrewrite') <= 6 or not isfolder('catrewrite/profiles') or not isfile('catrewrite/profiles/commit.txt') then
    makefolder('catrewrite/profiles')
    writefile('catrewrite/profiles/commit.txt', commitdata.sha)
    local req = httpService:JSONDecode(game:HttpGet(gh('/contents/profiles')))
    for _, v in req do
        if v.path ~= 'profiles/commit.txt' then
			downloader.Text = `Downloading catrewrite/{v.path}`
            downloadFile(`catrewrite/{v.path}`)
        end
    end
    task.spawn(function()
        local treq = httpService:JSONDecode(game:HttpGet(gh('/contents/translations')))
        for _, v in treq do
            downloadFile(`catrewrite/{v.path}`)
        end
    end)
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
	-- Always enforce the stub to keep things offline/guest
	writefile(whitelistPath, stub)
end

shared.VapeDeveloper = developer
getgenv().used_init = true
getgenv().catvapedev = developer
getgenv().closet = closet

if closet then
	task.spawn(function()
		repeat
			for _, v in getconnections(game:GetService('LogService').MessageOut) do
				v:Disable()
			end
			for _, v in getconnections(game:GetService('ScriptContext').Error) do
				v:Disable()
			end
			task.wait(0.5)
		until not shared.VapeDeveloper or not getgenv().closet
	end)
end

downloader.Text = 'Loading Cat Rewrite'

-- With developer mode enabled, local files are preserved; no wipe on version changes.
if not shared.VapeDeveloper then
	local commit = commitdata.sha or 'main'
	if commit == 'main' or (isfile('catrewrite/profiles/commit.txt') and readfile('catrewrite/profiles/commit.txt') or '') ~= commit then
		wipeFolder('catrewrite')
		wipeFolder('catrewrite/games')
		wipeFolder('catrewrite/guis')
		wipeFolder('catrewrite/libraries')
	end
    writefile('catrewrite/cheaters.json', '{}')
	writefile('catrewrite/profiles/commit.txt', commit)
end

-- Ensure BedWars game scripts are present locally so main.lua loads them (dev mode prefers local)
do
	local function ensureGameFile(placeId)
		local path = 'catrewrite/games/'..placeId..'.lua'
		if not isfile(path) then
			local ok, res = pcall(function()
				return game:HttpGet(raw('games/'..placeId..'.lua'), true)
			end)
			if ok and res and res ~= '404: Not Found' then
				if path:find('%.lua$') then
					res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
				end
				writefile(path, res)
			end
		end
	end
	-- BedWars: match and lobby place IDs
	ensureGameFile('6872274481') -- BedWars match
	ensureGameFile('6872265039') -- BedWars lobby
end

-- Load main
loadstring(downloadFile('catrewrite/main.lua'), 'main')()

downloader:Destroy()
