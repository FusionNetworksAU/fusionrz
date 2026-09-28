lib.locale()

Admin = {}

local core = exports.core

---@type { ace: string, name: string, label: string, colour: string }[]
Admin.roles = {
    { ace = 'group.owner',   name = 'owner',   label = 'Owner',     colour = '#e0c216' },
    { ace = 'group.admin',   name = 'admin',   label = 'Admin',     colour = '#cc1653' },
    { ace = 'group.mod',     name = 'mod',     label = 'Moderator', colour = '#34e5eb' },
    { ace = 'group.support', name = 'support', label = 'Support',   colour = '#49D27E' },
}

Admin.staffAce = 'group.admin'

-- group.admin is a PRINCIPAL (server.cfg adds players to it), not an ace, so
-- IsPlayerAceAllowed(src, 'group.admin') is false until an ace of that name
-- exists. Declaring each group as an ace of itself is what lets everything
-- in this resource say "group.admin" and have it mean "member of
-- group.admin". Runtime only: ox_lib issues add_ace through ExecuteCommand,
-- so permissions.cfg is untouched and a restart starts clean.
for index = 1, #Admin.roles do
    local ace = Admin.roles[index].ace

    if not IsPrincipalAceAllowed(ace, ace) then
        lib.addAce(ace, ace)
    end
end

---@type table<string, string>
Admin.actionAces = {}

Admin.disconnectedHistory = 100
Admin.staffChatHistory = 50
Admin.maxReportsPerPlayer = 3
Admin.maxReportLength = 1000
Admin.maxMessageLength = 500

---@param source Source
---@return boolean
function Admin.isStaff(source)
    return IsPlayerAceAllowed(source --[[@as string]], Admin.staffAce)
end

---@param source Source
---@param action string
---@return boolean
function Admin.can(source, action)
    if not Admin.isStaff(source) then
        return false
    end

    local ace = Admin.actionAces[action]

    return ace == nil or IsPlayerAceAllowed(source --[[@as string]], ace)
end

---@param source Source
---@return { ace: string, name: string, label: string, colour: string }?
function Admin.getRole(source)
    for index = 1, #Admin.roles do
        local role = Admin.roles[index]

        if IsPlayerAceAllowed(source --[[@as string]], role.ace) then
            return role
        end
    end

    return nil
end

---@param source Source
---@return string
function Admin.getRoleLabel(source)
    local role = Admin.getRole(source)

    return role and role.label or 'Member'
end

---@param source Source
---@return { color: string, text: string }?
function Admin.getTag(source)
    local role = Admin.getRole(source)

    return role and { color = role.colour, text = role.label } or nil
end

---The group chips on the player info panel.
---@param source Source
---@return { name: string, label: string, type: string, color: string }[]
function Admin.getGroups(source)
    local groups = {}

    for index = 1, #Admin.roles do
        local role = Admin.roles[index]

        if IsPlayerAceAllowed(source --[[@as string]], role.ace) then
            groups[#groups + 1] = {
                name = role.name,
                label = role.label,
                type = 'staff',
                color = role.colour,
            }
        end
    end

    return groups
end

---@param source Source
---@param action string
---@return boolean allowed
---@return string? error
function Admin.gate(source, action)
    if Admin.can(source, action) then
        return true
    end

    core:Log('protection', ('%s (src %s) tried admin action "%s" without permission'):format(
        Admin.getUsername(source), source, action
    ))

    return false, locale('no_perms')
end

---@param source Source
---@return string
function Admin.getUsername(source)
    local data = core:GetPlayerData(source)

    return data and data.username or GetPlayerName(source --[[@as string]]) or 'Unknown'
end

---@param source Source
---@return integer?
function Admin.getUserId(source)
    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---@param source Source
---@return string?
function Admin.getAvatar(source)
    local data = core:GetPlayerData(source)

    return data and data.avatar or nil
end

---@param expiresAt integer?
---@return string
function Admin.formatExpiry(expiresAt)
    if not expiresAt then
        return 'Never'
    end

    return os.date('%Y-%m-%d %H:%M:%S', expiresAt) --[[@as string]]
end
