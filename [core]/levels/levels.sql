-- Schema for resources/[core]/levels/server/main.lua.
--
-- Keyed on users.userId, the same id every other FNRZ table uses. Kept out
-- of core's user_profiles metadata blob because level and prestige are read
-- for OTHER players (career pages, the admin panel), and a metadata blob is
-- only cheap to read for the player it belongs to.

CREATE TABLE IF NOT EXISTS `user_levels` (
    `user_id`  INT UNSIGNED NOT NULL,
    `level`    SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    `xp`       INT UNSIGNED NOT NULL DEFAULT 0,
    `prestige` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`),
    -- Leaderboards sort on this pair, highest prestige then highest level.
    KEY `user_levels_rank` (`prestige`, `level`),
    CONSTRAINT `user_levels_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
