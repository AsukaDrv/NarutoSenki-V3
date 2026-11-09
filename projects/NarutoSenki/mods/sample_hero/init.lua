--
-- Mod contoh: HERO custom (template)
--
-- Format nsRegisterHero:
--   name      (string, wajib) : nama folder sprite di Resources/Unit/Ninja/<name>
--   group     (string)        : 'both' | 'konoha' | 'akatsuki'  (default 'both')
--   charId    (int)           : id internal (auto >= 1000 bila diisi 0)
--   title     (string)        : tampilan nama di UI
--   author    (string)        : kredit
--
-- NOTE V3: untuk menampilkan hero custom di layar pemilihan, siapkan
-- sprite sheet <name>.pvr.ccz + <name>.plist + <name>.xml di
-- Resources/Unit/Ninja/<name>/ lalu tambahkan flag `enabled = true`
-- di bawah ini. Bila `enabled` false, mod hanya mendaftar metadata
-- (tidak masuk roster) supaya aman dari sprite hilang.
--

nsRegisterHero{
    name     = 'SampleNinja',
    group    = 'both',
    charId   = 0,
    title    = 'Sample Ninja',
    author   = 'NarutoSenki-V3',
    enabled  = false,
}
