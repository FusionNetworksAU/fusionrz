Config = {}

Config.Match = {
    maxRounds = 5,
    roundsToWin = 3,
    roundTime = 90,
    queueTimeout = 300,
    bucketBase = 20000, -- Reserve this range for ramps matches; OneSync is required.
    countdown = 3,
    intermission = 3,
    finishRadius = 12.0
}

Config.Arenas = {
    [1] = {
        name = '2v2 Ramps',
        bucket = 9101,
        spawns = {
            vec4(-2808.4443, -895.3480, 246.6325, 268.0655),
            vec4(-2808.4988, -900.5418, 246.6325, 275.7566),
            vec4(-2780.3081, -900.7750, 246.6327, 88.4768),
            vec4(-2780.3086, -895.0550, 246.6327, 92.9844)
        },
        finish = vec3(-1038.50, 215.20, 64.65),
        reset = vec4(-1149.50, 187.40, 64.67, 160.0),
        spectator = vec4(-2794.0833, -870.5488, 246.6327, 179.8238)
    },
}

Config.Commands = {
    duel = 'ramp1v1',
    teams = 'ramp2v2',
    leave = 'rampleave',
    spectate = 'rampspectate'
}
