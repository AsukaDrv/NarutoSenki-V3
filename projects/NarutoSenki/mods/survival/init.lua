--
-- Mod: SURVIVAL — mode bertahan hidup 1 vs 3 berbasis Classic 3v3
--
-- Format nsRegisterMode:
--   name         (string, wajib) : id unik mode
--   title        (string)        : tampilan di UI
--   base         (string)        : mode C++ dasar: OneVsOne|Classic|FourVsFour|
--                                  HardCore_4Vs4|Boss|Clone|Deathmatch|RandomDeathmatch
--   playerCount  (int)           : jumlah pemain tim sendiri (1-4)
--   enemyCount   (int)           : jumlah musuh (1-4)
--   map          (int)           : id map awal (0 = default)
--   description  (string)        : penjelasan singkat
--

nsRegisterMode{
    name        = 'survival',
    title       = 'Survival',
    base        = 'Classic',
    playerCount = 1,
    enemyCount  = 3,
    map         = 0,
    description = 'Bertahan hidup: 1 lawan 3 musuh. Tidak ada reborn — '
                  .. 'mati sekali, tamat.',
    enableReborn = false,
    hardCore     = true,
}
