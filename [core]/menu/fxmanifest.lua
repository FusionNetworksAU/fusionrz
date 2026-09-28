fx_version 'cerulean'
game 'gta5'

name 'devmenu'
description 'Developer Menu for FUSIONRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@ox_lib/init.lua',
    'server/*.lua',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'