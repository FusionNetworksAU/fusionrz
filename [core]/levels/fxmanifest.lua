fx_version 'cerulean'
game 'gta5'

name 'levels'
description 'Career level, XP and prestige for FNRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_scripts {
    '@ox_lib/init.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

files {
    'config/*.lua',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
