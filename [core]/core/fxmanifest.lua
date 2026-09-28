fx_version 'cerulean'
game 'gta5'

name 'core'
description 'Player Management for FNRZ'
version '1.0.0'

dependencies {
    '/onesync',
    'oxmysql'
}

client_script 'base/client/init.lua'

shared_script '@ox_lib/init.lua'
client_script 'main.lua'
server_scripts {
    'base/shared/main.lua',
    'base/shared/countries.lua',
    'base/shared/items.lua',
    'base/shared/weapons.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',

    'base/server/database.lua',
    'base/server/main.lua',
    'base/server/functions.lua',
    'base/server/logger.lua',
    'base/server/intervals.lua',
    'base/server/commands.lua',
    'base/server/dropreasons.lua',
    'base/server/buckets.lua',
    'base/server/subscriptions.lua',
    'base/server/teleports.lua',
    'base/server/items.lua',
    'base/server/protection/*.lua',
    'base/server/protection/hooked/*.lua',
    'base/server/inventory/*.lua',
    'base/server/player/*.lua',
    'base/server/events/*.lua',

    'base/server/tests.lua',
    'tests/*.lua',
}

files {
    -- Inlined into other resources with '@core/base/client/init.lua'. The
    -- `@` loader reads it out of this directory, so it has to be declared
    -- here as well as in client_script above -- same as ox_lib's init.lua.
    'base/client/init.lua',

    'modules/*.lua',
    'imports/*.lua',
    'locales/*.json',

    'data/*.lua',

    'config/shared.lua',
    'config/client.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
