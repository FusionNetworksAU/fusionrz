---Compatibility shim.
---
---`gamemodes` disables noclip while a player is in a round and re-enables it
---on the way out. admin has no client-side noclip implementation in this base,
---so the export does not exist and the call throws out of the enter path.
---
---This holds the flag and exposes it, so a real noclip can read it rather than
---having to re-plumb the caller. Delete when noclip lands.

local noClipDisabled = false

---@param value boolean
exports('setNoClipDisabled', function(value)
    noClipDisabled = value == true

    TriggerEvent('admin:client:noClipDisabledChanged', noClipDisabled)
end)

---@return boolean
exports('isNoClipDisabled', function()
    return noClipDisabled
end)
