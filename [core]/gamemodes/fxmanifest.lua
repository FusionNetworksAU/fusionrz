fx_version 'cerulean'
game 'gta5'

name 'gamemodes'
description 'Various gamemodes for FusionRZ'
version '1.0.0'

client_script '@core/base/client/init.lua'

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/car_fights.lua',
    'client/main.lua',
    -- Gated behind the `gamemodes_debug` convar; see server/dev.lua.
    'client/dev.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/modes/ffa.lua',
    'server/modes/hopout_style.lua',
    'server/modes/gungame.lua',
    'server/modes/init.lua',
    'server/car_fights.lua',
    'server/freeroam_hopouts.lua',
    'server/main.lua',
    -- Last, so it can use everything the files above define.
    'server/dev.lua',
}

files {
    'config/client.lua',
    'shared/metadata.lua',
    'shared/modes.lua',
    'shared/location_pools.lua',
    -- location_pools requires these at runtime, so they have to ship too.
    'data/locations.lua',
    'data/car_fights_locations.lua',
    'data/jungle_redzone_locations.lua',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
