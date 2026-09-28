---Spectating.
---
---The server's job is the bucket and the permission check: a spectator has to
---be in the target's routing bucket or there is nothing to see. The camera
---work itself belongs to the client half, which acts on admin:client:*.

local core = exports.core

---@type table<Source, { targetSource: Source, bucket: integer }>
local spectating = {}

---@param source Source
---@param targetSource Source
local function beginSpectate(source, targetSource)
    -- Remember where they came from, so stopping puts them back rather than
    -- stranding them in whatever bucket the target was in.
    if not spectating[source] then
        spectating[source] = {
            targetSource = targetSource,
            bucket = core:GetPlayerBucket(source),
        }
    else
        spectating[source].targetSource = targetSource
    end

    core:SetPlayerBucket(source, core:GetPlayerBucket(targetSource))

    TriggerClientEvent('admin:client:spectate', source, targetSource)
end

---@param source Source
local function endSpectate(source)
    local session = spectating[source]

    if not session then
        return
    end

    spectating[source] = nil

    core:SetPlayerBucket(source, session.bucket)

    TriggerClientEvent('admin:client:stopSpectate', source)
end

Admin.endSpectate = endSpectate

RegisterNetEvent('admin:server:spectateStart', function(targetId)
    local source = source --[[@as Source]]

    if not Admin.can(source, 'spectate') then
        return TriggerClientEvent('admin:notify', source, 'error', locale('no_perms'))
    end

    local targetSource, targetData = Admin.resolveTarget(targetId)

    if not targetSource then
        return TriggerClientEvent('admin:notify', source, 'error', locale('spectate_failed'))
    end

    if targetSource == source then
        return TriggerClientEvent('admin:notify', source, 'error', locale('spectate_yourself'))
    end

    beginSpectate(source, targetSource)

    Admin.log(source, 'started spectating', targetData)
end)

RegisterNetEvent('admin:server:spectateStop', function()
    endSpectate(source --[[@as Source]])
end)

---Cycling to the next player while already spectating. Skips the spectator
---themselves and anyone else currently spectating, so staff do not end up
---watching each other watch.
RegisterNetEvent('admin:server:spectateCycle', function(direction)
    local source = source --[[@as Source]]

    if not Admin.can(source, 'spectate') or not spectating[source] then
        return
    end

    ---@type Source[]
    local candidates = {}

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if playerSource ~= source and not spectating[playerSource] then
            candidates[#candidates + 1] = playerSource
        end
    end

    if #candidates == 0 then
        return TriggerClientEvent('admin:notify', source, 'error', locale('spectate_cycle_failed'))
    end

    table.sort(candidates)

    local current = spectating[source].targetSource
    local index = 1

    for position = 1, #candidates do
        if candidates[position] == current then
            index = position
            break
        end
    end

    local step = direction == -1 and -1 or 1
    local nextIndex = ((index - 1 + step) % #candidates) + 1

    beginSpectate(source, candidates[nextIndex])
end)

---A spectator dropping, or the player they were watching dropping, both have
---to end the session -- otherwise the bucket they were parked in is never
---restored and the entry leaks.
AddEventHandler('core:server:onPlayerDropped', function(droppedSource)
    endSpectate(droppedSource)

    for spectatorSource, session in pairs(spectating) do
        if session.targetSource == droppedSource then
            endSpectate(spectatorSource)

            TriggerClientEvent('admin:notify', spectatorSource, 'error', locale('spectate_failed'))
        end
    end
end)

---@param source Source
---@return boolean
exports('IsSpectating', function(source)
    return spectating[source] ~= nil
end)
