fx_version 'cerulean'
game 'gta5'

name 'gamechat'
description 'In-game text chat for FusionRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_scripts {
    '@ox_lib/init.lua'
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'