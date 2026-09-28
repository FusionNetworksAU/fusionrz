exports('setCoinRewardsVisible', function(isVisible)
    SendNUIMessage({ action = 'setCoinRewardsVisible', data = isVisible })
end)

exports('setCoinRewardsData', function(data)
    SendNUIMessage({ action = 'setCoinRewardsData', data = data })
end)

exports('setCoinClaimVisible', function(isVisible)
    SendNUIMessage({ action = 'setCoinClaimVisible', data = isVisible })
end)

exports('setCoinClaimData', function(data)
    SendNUIMessage({ action = 'setCoinClaimData', data = data })
end)
