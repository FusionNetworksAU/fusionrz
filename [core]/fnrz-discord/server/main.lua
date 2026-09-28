local config = require 'config.server'
local core = exports.core
local utils = require '@core.modules.utils'

local API = 'https://discord.com/api/v10'

---@class DiscordMember
---@field id string
---@field username string?
---@field nickname string?
---@field avatar string? full CDN url
---@field roles string[]
---@field fetchedAt integer

---@type table<string, DiscordMember>
local cache = {}

---@type table<Source, string[]> principals this resource granted, to take back on drop
local granted = {}

local function isConfigured()
    return config.botToken ~= '' and config.guildId ~= ''
end

---@param discordId string
---@return DiscordMember?
local function fetchMember(discordId)
    local cached = cache[discordId]

    if cached and (os.time() - cached.fetchedAt) < config.cacheSeconds then
        return cached
    end

    local response = utils.fetch(('%s/guilds/%s/members/%s'):format(API, config.guildId, discordId), {
        method = 'GET',
        headers = {
            ['Authorization'] = ('Bot %s'):format(config.botToken),
            ['Content-Type'] = 'application/json',
        },
    })

    if response.status == 404 then
        cache[discordId] = { id = discordId, roles = {}, fetchedAt = os.time() }

        return cache[discordId]
    end

    if response.status ~= 200 or not response.body then
        lib.print.error(('[discord] member lookup failed for %s: HTTP %s'):format(discordId, response.status))

        return nil
    end

    local ok, body = pcall(json.decode, response.body)

    if not ok or type(body) ~= 'table' then
        return nil
    end

    local user = body.user or {}
    local avatar

    if body.avatar then
        avatar = ('https://cdn.discordapp.com/guilds/%s/users/%s/avatars/%s.png?size=128')
            :format(config.guildId, discordId, body.avatar)
    elseif user.avatar then
        avatar = ('https://cdn.discordapp.com/avatars/%s/%s.png?size=128'):format(discordId, user.avatar)
    end

    ---@type DiscordMember
    local member = {
        id = discordId,
        username = user.username,
        nickname = body.nick,
        avatar = avatar,
        roles = body.roles or {},
        fetchedAt = os.time(),
    }

    cache[discordId] = member

    return member
end

---@param source Source
---@return string? discordId
local function getDiscordId(source)
    local identifiers = utils.getIdentifiers(source)

    return identifiers.discord
end

---@param source Source
---@param member DiscordMember
local function applyRoles(source, member)
    local wanted = {}

    for index = 1, #member.roles do
        local principal = config.roleToPrincipal[member.roles[index]]

        if principal then
            wanted[principal] = true
        end
    end

    local held = granted[source] or {}

    for index = 1, #held do
        if not wanted[held[index]] then
            lib.removePrincipal(('player.%s'):format(source), held[index])
        end
    end

    local nowHeld = {}

    for principal in pairs(wanted) do
        nowHeld[#nowHeld + 1] = principal

        lib.addPrincipal(('player.%s'):format(source), principal)
    end

    granted[source] = nowHeld
end

---@param source Source
---@param member DiscordMember
local function applyLabels(source, member)
    for index = 1, #member.roles do
        local label = config.roleLabels[member.roles[index]]

        if label then
            Player(source).state:set('discordLabel', label, true)

            return
        end
    end
end

---@param source Source
---@return DiscordMember?
local function resolvePlayer(source)
    if not isConfigured() then
        return nil
    end

    local discordId = getDiscordId(source)

    if not discordId then
        if config.requireGuildMembership then
            core:KickPlayer(source, 'Link Discord to FiveM and reconnect.')
        end

        return nil
    end

    local member = fetchMember(discordId)

    if not member then
        return nil
    end

    if config.requireGuildMembership and #member.roles == 0 and not member.username then
        core:KickPlayer(source, ('Join our Discord to play: %s'):format(core:GetConfig().urls.discord))

        return nil
    end

    if member.avatar then
        core:SetAvatar(source, member.avatar)
    end

    applyRoles(source, member)
    applyLabels(source, member)

    TriggerEvent('discord:server:onMemberResolved', source, member)

    return member
end

AddEventHandler('core:server:onPlayerLoaded', function(source)
    CreateThread(function()
        resolvePlayer(source)
    end)
end)

AddEventHandler('core:server:onPlayerDropped', function(source)
    local held = granted[source]

    if held then
        for index = 1, #held do
            lib.removePrincipal(('player.%s'):format(source), held[index])
        end

        granted[source] = nil
    end
end)

---@param source Source
---@param activity string? nil means freeroam
exports('SetActivity', function(source, activity)
    if activity ~= nil and type(activity) ~= 'string' then
        return false
    end

    Player(source).state:set('activity', activity, true)

    return true
end)

---@param source Source
---@return DiscordMember?
exports('GetMember', function(source)
    local discordId = getDiscordId(source)

    return discordId and cache[discordId] or nil
end)

---@param source Source
---@return string[]
exports('GetRoles', function(source)
    local discordId = getDiscordId(source)
    local member = discordId and cache[discordId]

    return member and member.roles or {}
end)

---@param source Source
---@param roleId string
---@return boolean
exports('HasRole', function(source, roleId)
    local discordId = getDiscordId(source)
    local member = discordId and cache[discordId]

    if not member then
        return false
    end

    for index = 1, #member.roles do
        if member.roles[index] == roleId then
            return true
        end
    end

    return false
end)

---@param source Source
---@return boolean
local function refreshMember(source)
    local discordId = getDiscordId(source)

    if not discordId then
        return false
    end

    cache[discordId] = nil

    return resolvePlayer(source) ~= nil
end

exports('RefreshMember', refreshMember)

lib.addCommand('discordrefresh', {
    help = 'Re-read Discord roles for a player',
    params = {
        { name = 'target', type = 'playerId', help = 'server id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local target = args.target or source

    local ok = refreshMember(target)

    TriggerClientEvent('chat:addMessage', source, {
        args = { 'discord', ok and 'Roles refreshed.' or 'Could not refresh (no Discord id, or not configured).' },
    })
end)

CreateThread(function()
    if isConfigured() then
        return
    end

    lib.print.warn('[discord] no bot token or guild id set; avatars and role sync are off. Set `discord:token` and `discord:guild` in server.cfg.')
end)
