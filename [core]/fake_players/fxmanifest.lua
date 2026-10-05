fx_version 'cerulean'
game 'gta5'
server_only 'yes'

author 'LO'
description 'Fake player generator + state. Serves data via exports to the players.json, dynamic.json, info.json wrapper resources.'
version '1.0.0'

server_scripts {
    'config.lua',
    'names.lua',
    'server.lua',
}
