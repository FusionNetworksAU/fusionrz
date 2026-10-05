NamePool = {
    'kz', 'vex', 'nyx', 'rip', 'ash', 'jet', 'rue', 'kai', 'zyn', 'ovr',
    'ShadowMarauder', 'nocturne_77', 'Fenris.', 'HollowPointHyde', 'VandalRose',
    'kerosene_kid', 'OctaveDrift', 'MercuryVale', 'Vultaire', 'Ritalin_Rook',
    'Alejandro_Reyes', 'Yuki.Takeda', 'Giulia_Marchetti', 'Dmitri_Volkov',
    'Amara.Okafor', 'Soren_Haugen', 'Priya_Nair', 'Rafael.Costa',
    'MeiLin_Zhou', 'Finnegan_O\'Byrne',
    'orangemilk', 'wet.cardboard', 'notmydad', 'ping_check', 'driveby_dale',
    'hollowhost', 'lagwitch', 'curb_stomp', 'hotwirehank', 'glovebox_ghost',
    'Reaper_2187', 'callsign_oscar', 'DEFCON_4', 'unit_14a', 'bravo.six_9',
    'nova_0451', 'rvn.exe', 'static_19', 'phantom_tx', 'ghostline_02',
    'dilf_patrol', 'tacocop', 'the.gas_station', 'wet_bandit', 'wifi_warlord',
    'microwave_king', 'bologna_knight', 'rooftop_rhonda', 'cornerstore_cowboy',
    'minivan_mystic', 'parkinglot_poet', 'biblically.accurate',
    'xx_vortex_xx', 'ImNotToxicUR', 'skillissue.jpg', 'crouchspam4life',
    'nineliveshades', 'quicksilver_qt', 'reload_queen', 'moontide.',
    'Barnaby_Fletcher', 'Isolde_Vance', 'Thaddeus_Krane', 'Esperanza_Blight',
    'Ignatius_Hollow', 'Wren_Carrow', 'Marigold_Steele', 'Caius_Draper',
}

local HEX = '0123456789abcdef'
local function randHex(n)
    local out = ''
    for _ = 1, n do out = out .. HEX:sub(math.random(1, 16), math.random(1, 16)) end
    return out
end
local function randDigits(n)
    local out = ''
    for _ = 1, n do out = out .. tostring(math.random(0, 9)) end
    return out
end

function PickName() return NamePool[math.random(1, #NamePool)] end
function GenLicense() return 'license:' .. randHex(40) end
function GenSteam()   return 'steam:1100001' .. randHex(8) end
function GenDiscord() return 'discord:' .. randDigits(18) end
function GenIp()
    return 'ip:' .. math.random(10, 254) .. '.' .. math.random(0, 255)
        .. '.' .. math.random(0, 255) .. '.' .. math.random(1, 254)
end
