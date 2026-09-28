fx_version 'cerulean'
game 'gta5'

name 'hopouts'
description 'Hopouts for FNRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_script '@ox_lib/init.lua'

client_script '@devmenu/client/warmenu.lua'
client_script 'main.lua'
-- Shims for exports this base does not implement; see compat.lua.
client_script 'compat.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
    'server/states/*.lua',
    'server/debug/*.lua',
}

files {
    'config/client.lua',
    'config/shared.lua',
    'data/maps.lua',
    'web/index.html',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
