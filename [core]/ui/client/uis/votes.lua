local hopouts = exports.hopouts

exports('setVotesVisible', function(isVisible)
    SendNUIMessage({ action = 'setVotesVisible', data = isVisible })
end)

exports('setVotesData', function(data)
    SendNUIMessage({ action = 'setVotesData', data = data })
end)

exports('setVotesCountdown', function(countdown)
    SendNUIMessage({ action = 'setVotesCountdown', data = countdown })
end)

RegisterNUICallback('castVote', function(vote, cb)
    hopouts:handleVotePressed(vote)
    cb(true)
end)