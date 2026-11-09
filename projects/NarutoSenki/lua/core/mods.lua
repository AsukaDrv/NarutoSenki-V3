--
-- core/mods.lua — API untuk membaca registry mod (hero/mode custom)
--
-- Registry diisi dari C++ ModRegistry::loadAll() yang menjalankan
-- mods/<nama>/init.lua. Mod memanggil nsRegisterHero{...} / nsRegisterMode{...}.
--

local Mods = {}

Mods.heroes = {}
Mods.modes = {}

function Mods.reload()
    Mods.heroes = {}
    Mods.modes = {}

    local heroRegistry = rawget(_G, '__ns_hero_registry')
    if type(heroRegistry) == 'table' then
        for _, hero in pairs(heroRegistry) do
            if type(hero) == 'table' and type(hero.name) == 'string' and hero.name ~= '' then
                hero.group = hero.group or 'both'
                hero.charId = hero.charId or 1000
                Mods.heroes[#Mods.heroes + 1] = hero
            end
        end
    end

    local modeRegistry = rawget(_G, '__ns_mode_registry')
    if type(modeRegistry) == 'table' then
        for _, mode in pairs(modeRegistry) do
            if type(mode) == 'table' and type(mode.name) == 'string' and mode.name ~= '' then
                mode.base = mode.base or 'Classic'
                mode.playerCount = mode.playerCount or 1
                mode.enemyCount = mode.enemyCount or 1
                Mods.modes[#Mods.modes + 1] = mode
            end
        end
    end

    log('[Mods] hero=%d mode=%d', #Mods.heroes, #Mods.modes)
    return Mods
end

--- Nama-nama hero custom (untuk SelectLayer)
function Mods.heroNames()
    local names = {}
    for _, hero in pairs(Mods.heroes) do
        names[#names + 1] = hero.name
    end
    return names
end

--- Hero custom by name
function Mods.findHero(name)
    for _, hero in pairs(Mods.heroes) do
        if hero.name == name then
            return hero
        end
    end
    return nil
end

--- Mode custom by name
function Mods.findMode(name)
    for _, mode in pairs(Mods.modes) do
        if mode.name == name then
            return mode
        end
    end
    return nil
end

--- Dipanggil dari C++ setelah semua mod selesai dimuat
function nsOnModsLoaded()
    Mods.reload()
end

return Mods
