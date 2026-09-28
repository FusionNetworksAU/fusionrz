local ACE = 'group.admin'

---@param source Source
---@return boolean
local function canOpen(source)
    return IsPlayerAceAllowed(source --[[@as string]], ACE)
end

---@param source Source
---@return boolean opened
local function open(source)
    if not canOpen(source) then
        return false
    end

    TriggerClientEvent('devmenu:open', source)

    return true
end

lib.addCommand({ 'devmenu', 'dev' }, {
    help = 'Open the developer menu',
    restricted = ACE,
}, function(source)
    if not open(source --[[@as Source]]) then
        TriggerClientEvent('chat:addMessage', source, {
            args = { 'devmenu', 'You are not allowed to open the developer menu.' },
        })
    end
end)

exports('Open', open)
exports('CanOpen', canOpen)
