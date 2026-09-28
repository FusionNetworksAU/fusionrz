local shop = exports.shop

exports('fetchTattooTexture', function(textureDict, textureName)
    SendNUIMessage({
        action = 'fetchTattooTexture',
        data = {
            textureDict = textureDict,
            textureName = textureName,
        }
    })
end)

RegisterNUICallback('setFetchTattooTextureResult', function(data, cb)
    shop:setFetchTattooTextureResult(data)
    cb(true)
end)