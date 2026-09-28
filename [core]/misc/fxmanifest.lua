fx_version 'cerulean'
game 'gta5'

name 'misc'
description 'Miscellaneous things for FNRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_script '@ox_lib/init.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '**/server.lua',
}

client_script '@menu/client/warmenu.lua'
client_script 'main.lua'
-- Shims for exports this base does not implement; see compat.lua.
client_script 'compat.lua'

files {
    '**/config.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
