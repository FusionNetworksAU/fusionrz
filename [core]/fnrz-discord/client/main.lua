local config = require 'config.client'

local playerState = LocalPlayer.state
local core = exports.core

---@param activity? string
---@return string
local function getActivityLabel(activity)
    if not activity then
        return 'Shooting in Freeroam'
    end

    if activity:find('Lobby', 1, true) or activity:find('Queue', 1, true) then
        return ('In %s'):format(activity)
    end

    local displayNames = {
        HOPOUTS = 'Hopouts',
        TDM = 'TDM',
        FACECHECKS = 'Facechecks',
        JUMPOUTS = 'Jump Outs',
        WARS = 'Wars',
    }

    return ('Playing %s'):format(displayNames[activity] or activity)
end

---@param activity? string
local function setPresenceText(activity)
    SetRichPresence(getActivityLabel(activity))
end

local function playerLoaded()
    local data = core:GetPlayerData()

    setPresenceText(playerState.activity)
    SetDiscordRichPresenceAssetSmallText(('%s | ID: %s'):format(data.username, data.userId))
end

AddStateBagChangeHandler('activity', ('player:%s'):format(cache.serverId), function(_, _, activity)
    setPresenceText(activity)
end)

AddEventHandler('core:onPlayerLoaded', playerLoaded)

---@param resource string
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= cache.resource then return end

    if not playerState.isLoaded then return end

    playerLoaded()
end)

CreateThread(function()
    SetDiscordAppId(config.appId)

    SetDiscordRichPresenceAsset(config.largeImage)
    SetDiscordRichPresenceAssetSmall(config.smallImage)
    SetDiscordRichPresenceAssetText(config.text)

    -- Skipped when the url is absent: the native takes the url as argument
    -- index 2 and throws "Argument at index 2 was null" on a nil, so an
    -- optional button has to be omitted rather than registered empty.
    local buttons = {
        { label = 'Discord', url = config.discordUrl },
        { label = 'League', url = config.leagueUrl },
    }

    local slot = 0

    for index = 1, #buttons do
        local button = buttons[index]

        if type(button.url) == 'string' and button.url ~= '' then
            SetDiscordRichPresenceAction(slot, button.label, button.url)

            slot += 1
        end
    end

    setPresenceText(playerState.activity)
end)
