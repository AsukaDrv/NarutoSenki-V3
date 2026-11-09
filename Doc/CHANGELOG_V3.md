# CHANGELOG — Naruto Senki V3 (Modernized)

## v3.0.0 — "Mabar Edition"

Versi modernisasi besar dengan fokus: **stabilitas**, **Android terbaru**, dan **mabar lokal**.

### 📱 Android Modern (targetSdk 35)
- **AGP 8.7.3 + Gradle 8.9** (dari AGP 3.3.3 / Gradle 5.6.4 yang sudah tidak bisa di-build dengan Android Studio modern).
- **targetSdk/compileSdk 35**, minSdk 24 (Android 7.0+), `namespace` gradle modern (tanpa `package` di manifest).
- **NDK r27 (clang)** dengan **16 KB page-size** (`-Wl,-z,max-page-size=16384`) — wajib untuk Android 15+ dan perangkat 16KB-pages (mis. beberapa perangkat 2024+).
- **useLegacyPackaging = false** (natives di-load langsung dari APK, hemat storage).
- Java toolchain modern, lint longgar tapi tidak menggagalkan build.

### 🎮 Mabar Lokal (Fitur Baru Utama)
Semua jalur mabar melewati satu kanal event (open/message/close/error) yang sama dengan WebSocket online, sehingga kode game C++/Lua tidak perlu diubah.

| Transport | Cara | Keterangan |
|---|---|---|
| **WiFi LAN** | `TcpLink` (TCP port 9111) + `LanDiscovery` (UDP beacon port 9112, broadcast + multicast 239.255.0.1) | Host & client harus di WiFi yang sama; client otomatis menemukan room. |
| **Hotspot** | `HotspotManager` (LocalOnlyHotspot, Android 8+) | Satu HP jadi access point; SSID/pass ditampilkan di layar; client sambung WiFi lalu scan. |
| **Bluetooth** | `BluetoothLink` (RFCOMM, UUID kustom) | Scan device → connect → mabar. Permission BLUETOOTH_CONNECT/SCAN (Android 12+) dikelola otomatis. |
| **Online** | WebSocket OkHttp 4.12 | Jalur lama tetap berfungsi (upgrade OkHttp 3.12 → 4.12). |

- UI baru **LocalLobbyLayer** (100% Lua): pilih WiFi LAN / Hotspot / Bluetooth / Online.
- Flow pemilihan hero mabar: `select_update` / `select_lock` / `mabar_start` dikirim peer-to-peer; host memulai match untuk kedua sisi (`wsSetMatchConfig`).
- Permission runtime otomatis via `linkRequestPermissions` (NEARBY_WIFI_DEVICES neverForLocation di Android 13+, BLUETOOTH_SCAN/CONNECT di Android 12+).

### 🧩 Sistem Mod (Lua Data-Driven)
- **ModRegistry C++** memuat mod dari `mods/list.txt` → `mods/<nama>/init.lua` setelah `main.lua`.
- API mod: `nsRegisterHero{...}` dan `nsRegisterMode{...}` (registry disimpan di Lua global, 100% data-driven).
- Mod bawaan sebagai contoh/template: `sample_hero` (template hero custom), `survival` (1 vs 3 survival), `ranked` (duel 1v1).
- API Lua baru: `lanHost`, `lanJoin`, `lanStop`, `lanScan`, `lanScanStop`, `hotspotStart`, `hotspotStop`, `btHost`, `btConnect`, `btScan`, `btScanStop`, `linkSend`, `linkStop`, `linkIsActive`, `linkRequestPermissions`.

### 🛠️ Stabilitas & Perbaikan Build
- **Bug fix**: `extensions/Android.mk` tidak memasukkan `CCColliderDetector.cpp`, `CCDataReaderHelper.cpp`, `CocoLoader.cpp`, `DictionaryHelper.cpp`, `CCData.cpp` → linker gagal. Semua ditambahkan.
- **Bug fix**: `GameLoginHttp.cpp` tidak ada di `Android.mk` aplikasi → undefined symbol.
- **Bug fix**: ambiguitas `format()` antara `std::format` (C++20 libc++ baru) dan `fmt::format` di `Cocos2dxHelper.hpp` (clang NDK r27).
- **Bug fix**: target ndk-build tidak cocok dengan AGP 8 (`LOCAL_MODULE` disamakan dengan `LOCAL_MODULE_FILENAME`).
- **Stabilitas**: tombol Back Android sekarang `moveTaskToBack` (sebelumnya `killProcess` — save data bisa hilang).
- **ModRegistry**: `executeScriptFile` return 0 = sukses (semantik CCLuaStack 2.2.6 dipastikan dari sumber engine).

### 📦 Artefak
- `narutosenki-release.apk` (arm64-v8a + armeabi-v7a, signed release.jks)
- `narutosenki-release.aab` (untuk Play Store)
