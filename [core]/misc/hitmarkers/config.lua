---Hit feedback sounds.
---
---`attack` plays when you land a hit, `victim` when you take one. The mode
---names are the exact strings the settings NUI sends back
---(DISABLED / BODY_ONLY / HEAD_ONLY / ALL for sounds, and
---DISABLED / SINGLE_COLOR / MULTI_COLOR for the marker), so anything stored
---here round-trips through the UI untouched.
return {
    soundModes = {
        DISABLED = true,
        BODY_ONLY = true,
        HEAD_ONLY = true,
        ALL = true,
    },

    damageTypes = {
        DISABLED = true,
        SINGLE_COLOR = true,
        MULTI_COLOR = true,
    },

    defaults = {
        attackHitSoundMode = 'ALL',
        attackHitVolume = 1.0,
        victimHitSoundMode = 'ALL',
        victimHitVolume = 1.0,
        markerDamageType = 'MULTI_COLOR',
    },

    ---Frontend sounds, one per hit kind: `name` is the sound, `set` is the
    ---soundset it lives in, in PlaySoundFrontend's argument order.
    sounds = {
        body = { name = 'CHECKPOINT_NORMAL', set = 'HUD_MINI_GAME_SOUNDSET' },
        head = { name = 'CHECKPOINT_PERFECT', set = 'HUD_MINI_GAME_SOUNDSET' },
        taken = { name = 'CLICK_BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    },
}
