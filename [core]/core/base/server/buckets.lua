local LOBBY_BUCKET = 0
local FIRST_LEASED_BUCKET = 100

---@class BucketLease
---@field id integer
---@field owner string
---@field label string?
---@field createdAt integer
---@field members table<Source, true>

---@type table<integer, BucketLease>
local leases = {}

---@type integer[]
local freeIds = {}

local nextBucketId = FIRST_LEASED_BUCKET

Core.LOBBY_BUCKET = LOBBY_BUCKET

---@return integer
local function takeId()
    local recycled = table.remove(freeIds)

    if recycled then
        return recycled
    end

    local id = nextBucketId
    nextBucketId += 1

    return id
end

---@param owner string resource or system that holds the lease
---@param label string?
---@param lockdown 'strict' | 'relaxed' | 'inactive'? defaults to relaxed
---@return BucketLease
function Core.createBucket(owner, label, lockdown)
    local id = takeId()

    ---@type BucketLease
    local lease = {
        id = id,
        owner = owner,
        label = label,
        createdAt = os.time(),
        members = {},
    }

    leases[id] = lease

    SetRoutingBucketEntityLockdownMode(id, lockdown or 'relaxed')
    SetRoutingBucketPopulationEnabled(id, false)

    return lease
end

---@param bucketId integer
---@param moveTo integer? 
function Core.destroyBucket(bucketId, moveTo)
    local lease = leases[bucketId]

    if not lease then
        return
    end

    for memberSource in pairs(lease.members) do
        Core.setPlayerBucket(memberSource, moveTo or LOBBY_BUCKET)
    end

    leases[bucketId] = nil
    freeIds[#freeIds + 1] = bucketId
end

---@param source Source
---@param bucketId integer
---@return boolean
function Core.setPlayerBucket(source, bucketId)
    if not GetPlayerName(source --[[@as string]]) then
        return false
    end

    local current = GetPlayerRoutingBucket(source --[[@as string]])
    local currentLease = leases[current]

    if currentLease then
        currentLease.members[source] = nil
    end

    SetPlayerRoutingBucket(source --[[@as string]], bucketId)

    local lease = leases[bucketId]

    if lease then
        lease.members[source] = true
    end

    TriggerClientEvent('core:client:onBucketChanged', source, bucketId)
    TriggerEvent('core:server:onBucketChanged', source, bucketId, current)

    return true
end

---@param source Source
---@return integer
function Core.getPlayerBucket(source)
    return GetPlayerRoutingBucket(source --[[@as string]])
end

---@param bucketId integer
---@return Source[]
function Core.getBucketMembers(bucketId)
    local lease = leases[bucketId]

    if not lease then
        return {}
    end

    ---@type Source[]
    local members = {}

    for memberSource in pairs(lease.members) do
        members[#members + 1] = memberSource
    end

    return members
end

---@param player CorePlayer
function Core.assignLobbyBucket(player)
    Core.setPlayerBucket(player.source, LOBBY_BUCKET)
end

---@param player CorePlayer
function Core.releaseBucket(player)
    local bucketId = GetPlayerRoutingBucket(player.source --[[@as string]])
    local lease = leases[bucketId]

    if lease then
        lease.members[player.source] = nil
    end
end

AddEventHandler('onResourceStop', function(resource)
    for bucketId, lease in pairs(leases) do
        if lease.owner == resource then
            Core.destroyBucket(bucketId)
        end
    end
end)

exports('CreateBucket', Core.createBucket)
exports('DestroyBucket', Core.destroyBucket)
exports('SetPlayerBucket', Core.setPlayerBucket)
exports('GetPlayerBucket', Core.getPlayerBucket)
exports('GetBucketMembers', Core.getBucketMembers)
