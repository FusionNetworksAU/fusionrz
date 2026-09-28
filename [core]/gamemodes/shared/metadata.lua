---@return table
local function newPlayerMetadata()
    return {
        weaponSkins = {},
    }
end

---@param initial? table
---@return table
local function newClientMetadata(initial)
    local metadata = {
        lastUsedBlunt = 0,
        numJointsUsed = 0,
        lastUsedArmor = 0,
        numArmorsUsed = 0,
        numMedKitsUsed = 0,
        healthToGive = 0,
        lastGaveHealth = 0,
        lastEquippedWeapon = 0,
        hasSprintModifier = false,
        forceFirstPersonNextFrame = false,
        rifleClipAmmo = -1,
        primaryClipAmmo = -1,
    }

    if initial then
        for key, value in pairs(initial) do
            metadata[key] = value
        end
    end

    if metadata.rifleName then
        metadata.primaryName = metadata.rifleName
    end

    if metadata.meleeName and not metadata.meleeNameHash then
        metadata.meleeNameHash = joaat(metadata.meleeName)
    end

    return metadata
end

---@param metadata table
---@return table?
local function rifleClientMetadata(metadata)
    if not metadata.rifleName or not metadata.meleeName then
        return nil
    end

    local data = {
        rifleName = metadata.rifleName,
        primaryName = metadata.rifleName,
        meleeName = metadata.meleeName,
    }

    if metadata.pistolName then
        data.pistolName = metadata.pistolName
    end

    return data
end

return {
    newPlayer = newPlayerMetadata,
    newClient = newClientMetadata,
    rifleClient = rifleClientMetadata,
}
