local core = exports.core

local function displaySignup()
    SendNUIMessage({ action = 'setSignupVisible', data = true })
    SetNuiFocus(true, true)
end

exports('displaySignup', displaySignup)

RegisterNUICallback('closeSignup', function(_, cb)
    cb(1)

    SendNUIMessage({ action = 'setSignupVisible', data = false })
    SetNuiFocus(false, false)
end)

RegisterNUICallback('submitSignup', function(payload, cb)
    if type(payload) ~= 'table' then
        return cb({ success = false, error = 'Invalid signup data' })
    end

    local data, err, snapshot = lib.callback.await('core:server:createUser', false, payload.username, payload.country)

    if not data then
        return cb({ success = false, error = err })
    end

    core:SyncPlayerDataFromServer(data)
    core:ApplyInventorySnapshot(snapshot)

    cb({ success = true })

    core:loadPlayer(data)
end)