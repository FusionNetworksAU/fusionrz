CREATE TABLE IF NOT EXISTS `ranked_friends` (
    `user_a`     INT UNSIGNED NOT NULL,
    `user_b`     INT UNSIGNED NOT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_a`, `user_b`),
    KEY `ranked_friends_b` (`user_b`),
    CONSTRAINT `ranked_friends_a` FOREIGN KEY (`user_a`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `ranked_friends_b_fk` FOREIGN KEY (`user_b`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_friend_requests` (
    `sender_id`    INT UNSIGNED NOT NULL,
    `recipient_id` INT UNSIGNED NOT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`sender_id`, `recipient_id`),
    KEY `ranked_friend_requests_recipient` (`recipient_id`),
    CONSTRAINT `ranked_friend_requests_sender` FOREIGN KEY (`sender_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `ranked_friend_requests_recipient_fk` FOREIGN KEY (`recipient_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_blocks` (
    `user_id`    INT UNSIGNED NOT NULL,
    `blocked_id` INT UNSIGNED NOT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `blocked_id`),
    KEY `ranked_blocks_blocked` (`blocked_id`),
    CONSTRAINT `ranked_blocks_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `ranked_blocks_blocked_fk` FOREIGN KEY (`blocked_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_elo` (
    `user_id` INT UNSIGNED NOT NULL,
    `mode`    VARCHAR(32)  NOT NULL,
    `elo`     INT          NOT NULL DEFAULT 1000,
    `wins`    INT UNSIGNED NOT NULL DEFAULT 0,
    `losses`  INT UNSIGNED NOT NULL DEFAULT 0,
    `games`   INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`, `mode`),
    -- Leaderboards and matchmaking both read "everyone near this rating".
    KEY `ranked_elo_rating` (`mode`, `elo`),
    CONSTRAINT `ranked_elo_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_elo_adjustments` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`     INT UNSIGNED NOT NULL,
    `mode`        VARCHAR(32)  NOT NULL,
    `delta`       INT          NOT NULL,
    `elo_before`  INT          NOT NULL,
    `elo_after`   INT          NOT NULL,
    `won`         TINYINT(1)   NOT NULL DEFAULT 0,
    `acknowledged` TINYINT(1)  NOT NULL DEFAULT 0,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `ranked_elo_adjustments_user` (`user_id`, `acknowledged`),
    CONSTRAINT `ranked_elo_adjustments_user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_timeouts` (
    `user_id`    INT UNSIGNED NOT NULL,
    `expires_at` DATETIME     NOT NULL,
    `reason`     VARCHAR(128) DEFAULT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`),
    KEY `ranked_timeouts_expires` (`expires_at`),
    CONSTRAINT `ranked_timeouts_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ranked_recent_players` (
    `user_id`   INT UNSIGNED NOT NULL,
    `other_id`  INT UNSIGNED NOT NULL,
    `played_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `other_id`),
    KEY `ranked_recent_players_time` (`user_id`, `played_at`),
    CONSTRAINT `ranked_recent_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `ranked_recent_other` FOREIGN KEY (`other_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
