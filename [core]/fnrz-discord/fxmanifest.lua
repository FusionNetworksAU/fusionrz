fx_version 'cerulean'
game 'gta5'

name 'discord'
description 'Discord rich presence for FUSIONRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_script {
    '@ox_lib/init.lua'
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua'
}

files {
    'config/client.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
