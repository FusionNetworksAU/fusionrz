---Gate for the particle test area.
---
---bloodfx spawns peds and plays effects on them so damage and impact FX can
---be eyeballed against a live ped rather than a screenshot. It is a developer
---tool, so the client asks before it opens the menu and the answer is made
---here -- a client-side ace check is a suggestion, not a permission.

local ACE = 'group.admin'

---@return boolean
lib.callback.register('misc:server:canUseBloodFx', function(source)
    return IsPlayerAceAllowed(source --[[@as string]], ACE)
end)

---The test peds are local to whoever opened the menu, so the only thing the
---server does is move them there.
lib.callback.register('misc:server:bloodFxTeleport', function(source)
    if not IsPlayerAceAllowed(source --[[@as string]], ACE) then
        return false
    end

    local config = require 'bloodfx.config'

    return exports.core:TeleportPlayer(source, config.spawnPosition)
end)
