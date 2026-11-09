#pragma once

/**
 * ModRegistry — loader mod Lua sederhana untuk Naruto Senki V3.
 *
 * Mod ditempatkan di folder `mods/<nama>/init.lua` dan didaftarkan
 * di `mods/list.txt` (satu nama folder per baris, `#` = komentar).
 *
 * Setiap mod boleh memanggil:
 *   nsRegisterHero{  name=..., group="both"/"konoha"/"akatsuki", ... }
 *   nsRegisterMode{  name=..., title=..., base="Classic"/"OneVsOne"/..., ... }
 *
 * Registry disimpan di global Lua `__ns_hero_registry` dan
 * `__ns_mode_registry` (tabel), sehingga 100% dibaca ulang dari Lua.
 */
namespace ModRegistry
{
	/** Panggil sekali setelah main.lua dieksekusi. */
	void loadAll();
}
