---Headshot kill particles, as the settings screen lists them.
---
---Order is the setting's value: the UI stores the index as a string ("0" is
---Off), so rows may be appended but never reordered, or every player's saved
---choice shifts one down the list.
return {
    {
        label = 'Off',
    },
    {
        label = 'Confetti',
        dictionaryName = 'scr_xs_celebration',
        clipName = 'scr_xs_confetti_burst',
        scale = 1.2,
    },
    {
        label = 'Fireworks',
        dictionaryName = 'scr_indep_fireworks',
        clipName = 'scr_indep_firework_shotburst',
        scale = 0.6,
    },
    {
        label = 'Money',
        dictionaryName = 'core',
        clipName = 'ent_brk_banknotes',
        scale = 2.0,
    },
    {
        label = 'Sparks',
        dictionaryName = 'core',
        clipName = 'ent_dst_electrical',
        scale = 1.0,
    },
    {
        label = 'Smoke',
        dictionaryName = 'des_train_crash',
        clipName = 'ent_ray_train_smoke',
        scale = 1.0,
    },
}
