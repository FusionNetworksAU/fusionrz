---Staff chat.
---
---In memory only: it is a live channel, not a record. The audit trail people
---actually go back to is the command log in core. Scrollback is pushed on
---load so a staff member joining mid-conversation has context.

---@type table[]
local history = {}

---The NUI renders { message, username, avatar, timestamp, tag }, where tag is
---{ color, text }.
---@param message string
---@return boolean success
lib.callback.register('admin:server:sendStaffChatMessage', function(source, message)
    if not Admin.isStaff(source) or type(message) ~= 'string' then
        return false
    end

    local text = message:gsub('^%s+', ''):gsub('%s+$', '')

    if text == '' or #text > Admin.maxMessageLength then
        return false
    end

    local entry = {
        message = text,
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        timestamp = os.time(),
        tag = Admin.getTag(source),
    }

    history[#history + 1] = entry

    while #history > Admin.staffChatHistory do
        table.remove(history, 1)
    end

    Admin.broadcastToStaff('admin:addStaffChatMessage', entry)

    return true
end)

---@param source Source
function Admin.pushStaffChatHistory(source)
    if not Admin.isStaff(source) then
        return
    end

    TriggerClientEvent('admin:setStaffChatMessages', source, history)
end

AddEventHandler('core:server:onPlayerLoaded', function(source)
    -- The client waits on uisReady before rendering these, so pushing on load
    -- is safe and saves a round trip when the menu is first opened.
    Admin.pushStaffChatHistory(source)
end)
