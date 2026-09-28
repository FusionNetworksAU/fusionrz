fx_version 'cerulean'
game 'gta5'

name 'appearance'
description 'Clothing appearance for FNRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_script '@ox_lib/init.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_script 'main.lua'

files {
    'config/client.lua',
    'config/shared.lua',

    'game/constants.lua',

    'data/tattoos.lua',
    'data/peds.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'

