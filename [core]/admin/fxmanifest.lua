fx_version 'cerulean'
game 'gta5'

name 'admin'
description 'Admin menu for FNRZ'
version '1.0.0'

dependencies {
    'core',
    'ox_lib',
    'oxmysql',
}

client_script '@core/base/client/init.lua'

shared_script '@ox_lib/init.lua'
client_script 'main.lua'
-- Shims for exports this base does not implement; see compat.lua.
client_script 'compat.lua'
server_script 'shared/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/bans.lua',
    'server/players.lua',
    'server/spectate.lua',
    'server/player-options.lua',
    'server/self-options.lua',
    'server/staff-chat.lua',
    'server/reports.lua',
    'server/commands.lua',
}

files {
    'client/modules/*.lua',
    'config/client.lua',

    'locales/en.json'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
