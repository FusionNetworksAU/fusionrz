---@class UserRecord
---@field userId integer
---@field license string
---@field username string
---@field country string?
---@field avatar string?
---@field coins integer
---@field metadata table
---@field playtime integer
---@field createdAt string?
---@field lastSeen string?

---@class HardwareReport
---@field fingerprint string
---@field [string] any

local utils = Core.utils

---@type table<Source, CorePlayer>
local playersBySource = {}

---@type table<integer, Source>
local sourcesByUserId = {}

---@type table<string, Source>
local sourcesByLicense = {}

Core.playersBySource = playersBySource
Core.sourcesByUserId = sourcesByUserId
Core.sourcesByLicense = sourcesByLicense

---Connections that cleared the deferral gate but have not loaded a player yet.
---Keyed by license so a second connection attempt with the same license is
---rejected in playerConnecting rather than half-loading and fighting the first.
---@type table<string, integer> license -> os.time of the reservation
local pendingLicenses = {}

local RESERVATION_TIMEOUT = 60

Core.isRestarting = false

---@param license string
---@return boolean
local function isLicenseInUse(license)
    if sourcesByLicense[license] then
        return true
    end

    local reservedAt = pendingLicenses[license]

    if not reservedAt then
        return false
    end

    if os.time() - reservedAt > RESERVATION_TIMEOUT then
        pendingLicenses[license] = nil
        return false
    end

    return true
end

---@param license string
function Core.reserveLicense(license)
    pendingLicenses[license] = os.time()
end

---@param license string
function Core.releaseLicense(license)
    pendingLicenses[license] = nil
end

---@param source Source
---@return CorePlayer?
function Core.getPlayer(source)
    return playersBySource[source]
end

---@param userId integer
---@return CorePlayer?
function Core.getPlayerByUserId(userId)
    local source = sourcesByUserId[userId]

    return source and playersBySource[source] or nil
end

---@param license string
---@return CorePlayer?
function Core.getPlayerByLicense(license)
    local source = sourcesByLicense[license]

    return source and playersBySource[source] or nil
end

---@return table<Source, CorePlayer>
function Core.getPlayers()
    return playersBySource
end

---@return integer
function Core.getPlayerCount()
    return utils.getTableSize(playersBySource)
end

---@param player CorePlayer
function Core.registerPlayer(player)
    playersBySource[player.source] = player
    sourcesByUserId[player.userId] = player.source
    sourcesByLicense[player.license] = player.source

    pendingLicenses[player.license] = nil
end

---@param source Source
---@return CorePlayer?
function Core.unregisterPlayer(source)
    local player = playersBySource[source]

    if not player then
        return nil
    end

    playersBySource[source] = nil
    sourcesByUserId[player.userId] = nil
    sourcesByLicense[player.license] = nil

    return player
end

-- ------------------------------------------------------------ connection ----

---@param source Source
---@param deferrals table
local function handleConnecting(source, deferrals)
    deferrals.defer()

    local identifiers = utils.getIdentifiers(source)
    local tokens = utils.getTokens(source)

    identifiers.license = Core.toPrefixedLicense(identifiers.license)

    Wait(0)
    deferrals.update(locale('loading'))

    if Core.isRestarting then
        return deferrals.done(locale('restart'))
    end

    if not identifiers.license then
        return deferrals.done(locale('license_not_found'))
    end

    if not identifiers.steam and GetConvarInt('core:requireSteam', 0) == 1 then
        return deferrals.done(locale('steam_not_found'))
    end

    if #tokens == 0 then
        return deferrals.done(locale('missing_ids_or_tokens'))
    end

    if isLicenseInUse(identifiers.license) then
        return deferrals.done(locale('duplicate_license', identifiers.license))
    end

    deferrals.update(locale('checking_banlist'))

    local ok, ban = pcall(Core.db.getActiveBan, identifiers.license, tokens)

    if not ok then
        lib.print.error(('[core] banlist lookup failed for %s: %s'):format(identifiers.license, ban))

        return deferrals.done(locale('connection_error'))
    end

    if ban then
        return deferrals.done(Core.formatBanMessage(ban))
    end

    deferrals.update(locale('proceeding_to_queue'))

    Core.reserveLicense(identifiers.license)

    deferrals.done()
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local source = source --[[@as Source]]

    handleConnecting(source, deferrals)
end)

---The client asks for its player once its NUI is alive. Joining is not the
---same as being ready to receive PlayerData, so the load is driven from the
---client rather than from playerJoining.
lib.callback.register('core:server:requestPlayer', function(source)
    local identifiers = utils.getIdentifiers(source)

    identifiers.license = Core.toPrefixedLicense(identifiers.license)

    if not identifiers.license then
        DropPlayer(source --[[@as string]], locale('license_not_found'))

        return nil
    end

    local existing = playersBySource[source]

    if existing then
        return existing:getClientData()
    end

    local ok, user = pcall(Core.db.getUserByLicense, identifiers.license)

    if not ok then
        lib.print.error(('[core] user lookup failed for %s: %s'):format(identifiers.license, user))

        DropPlayer(source --[[@as string]], locale('connection_error'))

        return nil
    end

    if not user then
        -- No account yet: the client opens the signup UI and comes back
        -- through core:server:createUser.
        return false
    end

    local player = Core.loadPlayer(source, user --[[@as UserRecord]], identifiers, utils.getTokens(source))

    return player and player:getClientData() or nil
end)

AddEventHandler('playerDropped', function(reason)
    local source = source --[[@as Source]]

    local identifiers = utils.getIdentifiers(source)

    identifiers.license = Core.toPrefixedLicense(identifiers.license)

    if identifiers.license then
        Core.releaseLicense(identifiers.license)
    end

    local player = playersBySource[source]

    if not player then
        return
    end

    Core.dropPlayer(player, reason)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, player in pairs(playersBySource) do
        player:save()
    end
end)

CreateThread(function()
    -- Every base/server file has been loaded by the time this thread first
    -- runs, which is the point of Core.onReady: the db layer in player/db.lua
    -- is declared after most of its callers.
    Core.markReady()
end)
