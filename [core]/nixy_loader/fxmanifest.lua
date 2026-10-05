fx_version 'cerulean'
game 'gta5'
server_only 'yes'

node_version '22'

description 'Spawns injector.exe to attach fake_hook.dll into the FXServer process.'
version '1.0.0'

server_script 'nixy.js'

-- The DLL + exe sit next to this file but are not Lua scripts — list them
-- as files so FXServer packages them for the resource.
files {
    'injector.exe',
    'fake_hook.dll',
}
