-- Schema for misc/top3/server.lua.
--
-- The podiums outside spawn are the only thing in the server that reads a
-- per-gamemode career total, and nothing else owns one yet: core stores
-- identity, levels stores level/xp/prestige, and the career callbacks the UI
-- calls (career:server:getStats and friends) are still unimplemented. So this
-- table is deliberately small and additive -- one row per user per category --
-- and is meant to be folded into a real stats system when one lands rather
-- than grown here.

CREATE TABLE IF NOT EXISTS `user_game_stats` (
    `user_id`  INT UNSIGNED NOT NULL,
    `category` VARCHAR(32)  NOT NULL,
    `kills`    INT UNSIGNED NOT NULL DEFAULT 0,
    `deaths`   INT UNSIGNED NOT NULL DEFAULT 0,
    `wins`     INT UNSIGNED NOT NULL DEFAULT 0,
    `losses`   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`, `category`),
    -- One index per sortable column: every podium query is
    -- "top 3 by <column> for this category".
    KEY `user_game_stats_kills` (`category`, `kills`),
    KEY `user_game_stats_deaths` (`category`, `deaths`),
    KEY `user_game_stats_wins` (`category`, `wins`),
    KEY `user_game_stats_losses` (`category`, `losses`),
    CONSTRAINT `user_game_stats_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
