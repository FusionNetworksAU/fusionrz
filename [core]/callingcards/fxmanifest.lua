fx_version 'cerulean'
game 'gta5'

name 'callingcards'
description 'Calling cards for FusionRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/seasonal.lua',
}

client_scripts {
    'client/main.lua'
}

files {
    'data/categories.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'