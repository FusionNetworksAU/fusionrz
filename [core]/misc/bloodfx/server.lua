local ACE = 'group.admin'

---@return boolean
lib.callback.register('misc:server:canUseBloodFx', function(source)
    return IsPlayerAceAllowed(source --[[@as string]], ACE)
end)
lib.callback.register('misc:server:bloodFxTeleport', function(source)
    if not IsPlayerAceAllowed(source --[[@as string]], ACE) then
        return false
    end

    local config = require 'bloodfx.config'

    return exports.core:TeleportPlayer(source, config.spawnPosition)
end)
