---@type CorePlayersModule
local m = {}

---@type table<Source, integer>
local playersByServerId = {}

---@type integer[]
local playerIndexes = {}

---@type table<string, true>
local enabledIds = {}

local isEnabled = false

---@type EventHandlerCookie?
local joiningHandler = nil
---@type EventHandlerCookie?
local droppedHandler = nil

-- Intentionally not calling lib.print.debug directly here as that has overhead.
-- We want this code path to be **really fast** with minimal anything else.
local DEBUG_MODE = false

---@param serverId Source
---@param playerIndex integer
local function addPlayer(serverId, playerIndex)
    if playersByServerId[serverId] then
        return
    end

    playersByServerId[serverId] = playerIndex
    playerIndexes[#playerIndexes + 1] = playerIndex

    if DEBUG_MODE then
        lib.print.debug(('[Players Module] Adding serverId %s playerIndex %s.'):format(serverId, playerIndex))
    end
end

---@param serverId Source
local function removePlayer(serverId)
    local playerIndex = playersByServerId[serverId]
    if not playerIndex then
        return
    end

    playersByServerId[serverId] = nil

    local lastPosition = #playerIndexes

    for position = 1, lastPosition do
        if playerIndexes[position] == playerIndex then
            playerIndexes[position] = playerIndexes[lastPosition]
            playerIndexes[lastPosition] = nil
            break
        end
    end

    if DEBUG_MODE then
        lib.print.debug(('[Players Module] Removing serverId %s.'):format(serverId))
    end
end

local function seedFromActivePlayers()
    local activePlayers = GetActivePlayers()

    for _, playerIndex in pairs(activePlayers) do
        addPlayer(GetPlayerServerId(playerIndex), playerIndex)
    end

    if DEBUG_MODE then
        lib.print.debug(('[Players Module] Seeded %s existing players.'):format(#activePlayers))
    end
end

---@param id string
function m.enable(id)
    if DEBUG_MODE then
        lib.print.debug(('[Players Module] Enable request from %s.'):format(id))
    end

    enabledIds[id] = true

    if isEnabled then
        return
    end

    if DEBUG_MODE then
        lib.print.debug('[Players Module] Enable request passed successfully.')
    end

    isEnabled = true

    joiningHandler = RegisterNetEvent('onPlayerJoining', function(serverId, _, playerIndex)
        addPlayer(serverId, playerIndex)
    end)

    droppedHandler = RegisterNetEvent('onPlayerDropped', removePlayer)

    seedFromActivePlayers()
end

---@param id string
function m.disable(id)
    if DEBUG_MODE then
        lib.print.debug(('[Players Module] Disable request from %s.'):format(id))
    end

    enabledIds[id] = nil

    if not isEnabled or next(enabledIds) then
        return
    end

    if DEBUG_MODE then
        lib.print.debug('[Players Module] Disable request passed successfully.')
    end

    isEnabled = false

    if joiningHandler then
        RemoveEventHandler(joiningHandler)
        joiningHandler = nil
    end

    if droppedHandler then
        RemoveEventHandler(droppedHandler)
        droppedHandler = nil
    end

    table.wipe(playersByServerId)
    table.wipe(playerIndexes)
end

---@return boolean
function m.isEnabled()
    return isEnabled
end

---@return table<Source, integer>
function m.getPlayers()
    return playersByServerId
end

---@return integer[]
function m.getPlayerIndexes()
    return playerIndexes
end

---@return integer
function m.getPlayerCount()
    return #playerIndexes
end

---@param serverId Source
---@return integer?
function m.getPlayerIndex(serverId)
    return playersByServerId[serverId]
end

return m
