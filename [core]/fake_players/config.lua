Config = {}

-- How many fakes to add on top of real player count.
-- Aim for 60-85% of sv_maxclients.
Config.FakeCount = 32

-- Hard ceiling on reported total. Must be < sv_maxclients.
Config.ReportedCap = 44

-- Churn — how often fakes rotate (joins/leaves)
Config.ChurnIntervalMs = 45000
Config.ChurnRatio      = 0.15

-- Ping distribution
Config.PingMin = 32
Config.PingMax = 184

Config.IncludeIdentifiers = false

Config.OverrideHostname = ''
Config.OverrideGametype = ''
Config.OverrideMapname  = ''

Config.PopulateTxAdmin = true

-- How often to write the cache files the DLL reads.
-- The DLL reads on every HTTP hit; Cfx master scrapes every ~60s.
-- 1000ms = 1s gives live-looking counts without disk pummeling.
Config.CacheRefreshMs = 1000

Config.Debug = true
Config.DebugChurn = true
Config.DebugSeed = false
Config.HeartbeatMs = 60000
