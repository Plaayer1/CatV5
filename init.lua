-- Simple, stable loader for CatV5
-- Goal: force BedWars game script to load (developer mode OFF), avoid crashes, no GitHub API calls.

repeat task.wait() until game:IsLoaded()

-- Turn OFF developer mode so main.lua auto-downloads the game script for the current PlaceId
shared.VapeDeveloper = false
getgenv().catvapedev = false

-- Ensure commit file exists and points to 'main' (required by main.lua's downloader)
pcall(function()
    if not isfolder('catrewrite') then makefolder('catrewrite') end
    if not isfolder('catrewrite/profiles') then makefolder('catrewrite/profiles') end
    writefile('catrewrite/profiles/commit.txt', 'main')
    writefile('catreset', 'True')
end)

-- Fetch and run main.lua directly from your repo's main branch
local ok, src = pcall(function()
    return game:HttpGet('https://raw.githubusercontent.com/Plaayer1/CatV5/main/main.lua', true)
end)

if not ok or not src or src == '' then
    error('CatV5: Failed to fetch main.lua')
end

local f, err = loadstring(src, 'main')
if not f then
    error('CatV5: loadstring error: '..tostring(err))
end

return f(...)
