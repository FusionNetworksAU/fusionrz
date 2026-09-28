-- Schema for resources/[core]/admin/server/main.lua.
--
-- Bans are deliberately absent: core owns them in `user_bans`, and this
-- resource reads that table for the ban history panel rather than keeping a
-- second copy that could disagree with it.
--
-- Everything keys on users.userId, which is the id the admin UI passes back
-- for every row it lists.

-- Kicks and warnings share one table because the panels render them
-- identically and the only thing that differs is which tab they land in.
CREATE TABLE IF NOT EXISTS `admin_actions` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`    INT UNSIGNED NOT NULL,
    `kind`       ENUM('kick','warn') NOT NULL,
    `reason`     VARCHAR(512) NOT NULL,
    `staff`      VARCHAR(64)  NOT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `admin_actions_user` (`user_id`, `kind`),
    CONSTRAINT `admin_actions_user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `admin_reports` (
    `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id`        INT UNSIGNED NOT NULL,
    `target_user_id` INT UNSIGNED DEFAULT NULL,
    `reason`         VARCHAR(64)   NOT NULL,
    `description`    VARCHAR(1024) NOT NULL DEFAULT '',
    `resolved_at`    DATETIME      DEFAULT NULL,
    `resolved_by`    VARCHAR(64)   DEFAULT NULL,
    `resolved_by_user_id` INT UNSIGNED DEFAULT NULL,
    `created_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `admin_reports_user` (`user_id`),
    KEY `admin_reports_target` (`target_user_id`),
    -- The open-report cap per player queries on this pair.
    KEY `admin_reports_open` (`user_id`, `resolved_at`),
    CONSTRAINT `admin_reports_user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE CASCADE,
    CONSTRAINT `admin_reports_target_fk` FOREIGN KEY (`target_user_id`) REFERENCES `users` (`userId`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `admin_report_messages` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `report_id`  INT UNSIGNED NOT NULL,
    `user_id`    INT UNSIGNED DEFAULT NULL,
    `text`       VARCHAR(1024) NOT NULL,
    `is_staff`   TINYINT(1)    NOT NULL DEFAULT 0,
    `created_at` DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `admin_report_messages_report` (`report_id`, `created_at`),
    CONSTRAINT `admin_report_messages_report_fk` FOREIGN KEY (`report_id`) REFERENCES `admin_reports` (`id`) ON DELETE CASCADE,
    CONSTRAINT `admin_report_messages_user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`userId`) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
