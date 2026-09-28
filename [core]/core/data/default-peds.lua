---@type table<'male' | 'female', ClothingOutfit>
return {
    male = {
        model = 'mp_m_freemode_01',
        headBlend = {
            shapeMix = 0.0,
            skinFirst = 0,
            shapeFirst = 0,
            skinSecond = 0,
            shapeSecond = 0,
            skinMix = 0.0,
            thirdMix = 0.0,
            shapeThird = 0,
            skinThird = 0
        },
        headOverlays = {
            beard = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            complexion = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            bodyBlemishes = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            blush = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            lipstick = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            blemishes = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            eyebrows = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            makeUp = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            sunDamage = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            moleAndFreckles = { color = 0, style = 0, secondColor = 0, opacity = 0 },
            chestHair = { color = 0, style = 0, secondColor = 0, opacity = 1 },
            ageing = { color = 0, style = 0, secondColor = 0, opacity = 1 }
        },
        components = {
            'empty_mask',
            'empty_jacket',
            'empty_undershirt',
            'empty_hands',
            'empty_pants',
            'empty_shoes',
        },
        props = {
            'empty_hat',
            'empty_eyes',
            'empty_ears',
            'empty_watch',
            'empty_bracelet',
        }
    },
    female = {
        model = 'mp_f_freemode_01',
        headBlend = {
            shapeMix = 0.3,
            skinFirst = 0,
            shapeFirst = 31,
            skinSecond = 0,
            shapeSecond = 0,
            skinMix = 0,
            thirdMix = 0,
            shapeThird = 0,
            skinThird = 0
        },
        hair = {
            color = 0,
            style = 15,
            texture = 0,
            highlight = 0
        },
        headOverlays = {
            chestHair = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            bodyBlemishes = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            beard = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            lipstick = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            complexion = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            blemishes = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            moleAndFreckles = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            makeUp = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            ageing = { secondColor = 0, opacity = 1, color = 0, style = 0 },
            eyebrows = { secondColor = 0, opacity = 1, color = 0, style = 0 },
            blush = { secondColor = 0, opacity = 0, color = 0, style = 0 },
            sunDamage = { secondColor = 0, opacity = 0, color = 0, style = 0 }
        },
        components = {
            'empty_mask',
            'empty_jacket',
            'empty_undershirt',
            'empty_hands',
            'empty_pants',
            'empty_shoes',
        },
        props = {
            'empty_hat',
            'empty_eyes',
            'empty_ears',
            'empty_watch',
            'empty_bracelet',
        }
    }
}
