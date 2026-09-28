fx_version 'cerulean'
game 'gta5'

name 'ranked'
description 'Ranked backend for FusionRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

files {
    'config/client.lua',
    'config/shared.lua',
    'web/index.html',
    -- The lobby backdrop (config/client.lua podium.backdrop), loaded into a
    -- runtime texture on the client.
    'images/*.png',
    'images/*.jpg',
}

client_scripts {
    '@devmenu/client/warmenu.lua',
    '@ox_lib/init.lua',
}
client_script 'main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@ox_lib/init.lua',
    'server/*.lua',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
