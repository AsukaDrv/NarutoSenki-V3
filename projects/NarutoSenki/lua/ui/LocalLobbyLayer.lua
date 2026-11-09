--
-- LocalLobbyLayer — Mabar lokal: WiFi LAN / Hotspot / Bluetooth / Online
--
-- Semua transport mengirim event (open/message/close/error/lan_rooms/
-- bt_devices/hotspot_started/hotspot_error/permissions/peer) ke
-- onWebSocketEvent() di StartMenu.lua, yang di-route ke layer ini.
--

require('utils.save')

local MABAR_PORT = 9111
local LOBBY_MUSIC = 'Audio/Menu/menu.wav'

local function jsonEscapeForWire(s)
    s = tostring(s or '')
    s = string.gsub(s, '\\', '\\\\')
    s = string.gsub(s, '"', '\\"')
    return s
end

local function extractJsonStringField(payload, fieldName)
    local pattern = '"' .. fieldName .. '"%s*:%s*"([^"]+)"'
    return string.match(payload or '', pattern)
end

local function extractJsonNumberField(payload, fieldName)
    local pattern = '"' .. fieldName .. '"%s*:%s*(-?%d+)'
    local value = string.match(payload or '', pattern)
    if value then return tonumber(value) end
    return nil
end

LocalLobbyLayer = class('LocalLobbyLayer', function() return display.newLayer() end)

function LocalLobbyLayer:create() return LocalLobbyLayer.new() end

function LocalLobbyLayer:ctor()
    self.transport = nil            -- 'lan' | 'hotspot' | 'bluetooth' | nil
    self.isHost = false
    self.isConnected = false
    self.rooms = {}                 -- hasil scan LAN
    self.devices = {}               -- hasil scan bluetooth
    self._deviceIndex = 1
    self._roomIndex = 1
    self._startingAsHost = false
    self:init()
    _G.__localLobbyLayer = self
end

function LocalLobbyLayer:init()
    tools.addSprites('Select.plist')
    tools.addSprites('UI.plist')

    if save.isBGM() then audio.playMusic(LOBBY_MUSIC, true) end

    local bg = display.newSprite('blue_bg.png', 0, 0)
    bg:setAnchorPoint(0, 0)
    bg:fullScreen()
    self:addChild(bg, -5)

    local barTop = display.newSprite('menu_bar3.png')
    barTop:setAnchorPoint(0, 0)
    barTop:setPosition(0, display.height - barTop:getContentSize().height)
    self:addChild(barTop, 2)

    local barBottom = display.newSprite('menu_bar2.png')
    barBottom:setAnchorPoint(0, 0)
    barBottom:fullScreen()
    self:addChild(barBottom, 2)

    -- Judul
    local title = ui.newTTFLabelWithShadow({
        text = 'MABAR LOKAL',
        size = 20,
        x = display.cx,
        y = display.height - 26,
        align = ui.TEXT_ALIGN_CENTER
    })
    self:addChild(title, 5)

    -- Status (baris 1) & info (baris 2)
    self.statusLabel = ui.newTTFLabelWithShadow({
        text = 'Pilih mode mabar:',
        size = 14,
        x = display.cx,
        y = display.cy + 30,
        align = ui.TEXT_ALIGN_CENTER
    })
    self:addChild(self.statusLabel, 5)

    self.infoLabel = ui.newTTFLabelWithShadow({
        text = '',
        size = 12,
        x = display.cx,
        y = display.cy + 8,
        align = ui.TEXT_ALIGN_CENTER
    })
    self:addChild(self.infoLabel, 5)

    self:setStatus('Pilih mode mabar:')
    self:setInfo('WiFi LAN: satu jaringan | Hotspot: satu HP jadi AP | Bluetooth: dekat')

    -- Pilihan transport (kiri)
    local btnDefs = {
        {label = 'WiFi LAN',  y = display.cy + 44, cb = function() self:onPickLan() end},
        {label = 'Hotspot',   y = display.cy + 12, cb = function() self:onPickHotspot() end},
        {label = 'Bluetooth', y = display.cy - 20, cb = function() self:onPickBluetooth() end},
        {label = 'Online',    y = display.cy - 52, cb = function() self:onPickOnline() end},
    }
    for _, def in pairs(btnDefs) do
        local btn = ui.newTTFLabelMenuItem({
            label = def.label,
            size = 18,
            listener = def.cb
        })
        local menu = ui.newMenu({btn})
        menu:setPosition(96, def.y)
        self:addChild(menu, 5)
    end

    -- Tombol kanan: Return (atas), Host (tengah), Scan/Join (bawah)
    local rightX = display.width - 60
    local returnBtn = ui.newImageMenuItem({
        image = 'UI/return_btn.png',
        listener = function() self:onReturn() end
    })
    local returnMenu = ui.newMenu({returnBtn})
    returnMenu:setPosition(rightX, 108)
    self:addChild(returnMenu, 6)

    self.hostBtn = ui.newTTFLabelMenuItem({
        label = 'HOST',
        size = 20,
        listener = function() self:onHostPressed() end
    })
    self.hostMenu = ui.newMenu({self.hostBtn})
    self.hostMenu:setPosition(rightX, 66)
    self:addChild(self.hostMenu, 6)

    self.joinBtn = ui.newTTFLabelMenuItem({
        label = 'SCAN',
        size = 16,
        listener = function() self:onScanPressed() end
    })
    self.joinMenu = ui.newMenu({self.joinBtn})
    self.joinMenu:setPosition(rightX, 30)
    self:addChild(self.joinMenu, 6)

    self:setActionButtonsVisible(false)
end

-- ------------------------------------------------------------------
-- UI helpers
-- ------------------------------------------------------------------
function LocalLobbyLayer:setStatus(text)
    if self.statusLabel and self.statusLabel.label then
        self.statusLabel.label:setString(tostring(text))
    end
    if self.statusLabel and self.statusLabel.shadow1 then
        self.statusLabel.shadow1:setString(tostring(text))
    end
end

function LocalLobbyLayer:setInfo(text)
    local value = tostring(text or '')
    if #value > 70 then value = string.sub(value, 1, 67) .. '...' end
    if self.infoLabel and self.infoLabel.label then
        self.infoLabel.label:setString(value)
    end
    if self.infoLabel and self.infoLabel.shadow1 then
        self.infoLabel.shadow1:setString(value)
    end
end

function LocalLobbyLayer:setActionButtonsVisible(visible)
    if self.hostMenu then self.hostMenu:setVisible(visible) end
    if self.joinMenu then self.joinMenu:setVisible(visible) end
end

-- ------------------------------------------------------------------
-- Transport picking
-- ------------------------------------------------------------------
function LocalLobbyLayer:onPickLan()
    self.transport = 'lan'
    self:setStatus('WiFi LAN dipilih')
    self:setInfo('Host & client harus di WiFi yang sama. HOST = buat room, SCAN = cari room.')
    self:setActionButtonsVisible(true)
    linkRequestPermissions()
end

function LocalLobbyLayer:onPickHotspot()
    self.transport = 'hotspot'
    self:setStatus('Hotspot dipilih')
    self:setInfo('Host: buat hotspot. Client: sambungkan WiFi ke hotspot host, lalu SCAN.')
    self:setActionButtonsVisible(true)
    linkRequestPermissions()
end

function LocalLobbyLayer:onPickBluetooth()
    self.transport = 'bluetooth'
    self:setStatus('Bluetooth dipilih')
    self:setInfo('HOST menunggu koneksi. Client: SCAN lalu CONNECT (lihat log tombol).')
    self:setActionButtonsVisible(true)
    linkRequestPermissions()
end

function LocalLobbyLayer:onPickOnline()
    linkStop()
    _G.__localLobbyLayer = nil
    enterNetworkLobby()
end

function LocalLobbyLayer:onReturn()
    audio.playSound('Audio/Menu/cancel.wav')
    linkStop()
    _G.__localLobbyLayer = nil
    backToStartMenu()
end

-- ------------------------------------------------------------------
-- Host / Scan actions
-- ------------------------------------------------------------------
function LocalLobbyLayer:onHostPressed()
    if not self.transport then return end

    if self.transport == 'bluetooth' then
        self.isHost = true
        self:setStatus('Bluetooth: menunggu client...')
        self:setInfo('Kirim permintaan pairing bila diminta.')
        btHost()
        return
    end

    if self.transport == 'hotspot' then
        self.isHost = true
        self._startingAsHost = true
        self:setStatus('Menyalakan hotspot...')
        self:setInfo('Tunggu sampai SSID muncul.')
        local ok = hotspotStart('NS3')
        if not ok then
            self:setStatus('Hotspot gagal dinyalakan')
            self._startingAsHost = false
        end
        return
    end

    -- lan
    self.isHost = true
    local roomName = 'Room-' .. tostring(math.random(100, 999))
    local ok = lanHost(roomName, MABAR_PORT)
    if ok then
        self:setStatus('Host: ' .. roomName)
        self:setInfo('Client pilih mode yang sama lalu tekan SCAN.')
    else
        self:setStatus('Gagal host room')
        self.isHost = false
    end
end

function LocalLobbyLayer:onScanPressed()
    if not self.transport then return end

    if self.transport == 'bluetooth' then
        self:setStatus('Scan bluetooth...')
        self:setInfo('Tekan SCAN lagi untuk connect ke device pertama.')
        btScanStop()
        btScan()
        self._deviceIndex = 1
        return
    end

    -- lan / hotspot: sama-sama pakai UDP beacon (port 9112)
    if self.transport == 'hotspot' and not self.isHost then
        self:setInfo('Pastikan WiFi sudah tersambung ke hotspot host!')
    end
    self:setStatus('Mencari room...')
    lanScanStop()
    lanScan()
end

-- ------------------------------------------------------------------
-- Event routing (dipanggil dari StartMenu.onWebSocketEvent)
-- ------------------------------------------------------------------
function LocalLobbyLayer:handleWebSocketEvent(eventName, payload)
    if eventName == 'lan_rooms' then
        self:handleRoomsFound(payload)
        return
    end
    if eventName == 'bt_devices' then
        self:handleBtDevices(payload)
        return
    end
    if eventName == 'hotspot_started' then
        local ssid = extractJsonStringField(payload, 'ssid') or '?'
        local pass = extractJsonStringField(payload, 'pass') or '?'
        local ip = extractJsonStringField(payload, 'ip') or '?'
        self:setStatus('Hotspot ON: ' .. ssid)
        self:setInfo('Pass: ' .. pass .. ' | IP: ' .. ip .. ' | lanHost mulai...')
        local ok = lanHost('Hotspot Room', MABAR_PORT)
        self:setInfo('Pass: ' .. pass .. ' | Client connect WiFi lalu SCAN. IP: ' .. ip)
        if ok then
            self:setStatus('Hotspot ON (' .. ssid .. '), room siap')
        else
            self:setStatus('Hotspot ON, tapi host room gagal')
        end
        self._startingAsHost = false
        return
    end
    if eventName == 'hotspot_error' then
        self:setStatus('Hotspot error')
        self:setInfo(tostring(payload or ''))
        self._startingAsHost = false
        return
    end
    if eventName == 'permissions' then
        local granted = string.find(tostring(payload or ''), 'true') ~= nil
        self:setInfo(granted and 'Permission OK' or 'Permission ditolak — fitur bisa terbatas')
        return
    end
    if eventName == 'peer' then
        self:setInfo(tostring(payload or ''))
        return
    end
    if eventName == 'open' then
        -- koneksi TCP/BT established
        self.isConnected = true
        local transportLabel = (self.transport == 'bluetooth') and 'Bluetooth' or 'WiFi'
        self:setStatus('Tersambung (' .. transportLabel .. ')!')
        self:setInfo('Masuk ke pemilihan karakter...')
        linkStop()
        -- matikan beacon/scan agar tidak menerima room baru
        lanScanStop()
        btScanStop()
        _G.__localMabarActive = true
        _G.__localMabarRole = self.isHost and 'host' or 'client'
        _G.__localLobbyLayer = nil
        enterSelectLayer(GameMode.OneVsOne, false)
        return
    end
    if eventName == 'close' or eventName == 'error' then
        if not self.isConnected then
            self:setStatus('Gagal: ' .. tostring(payload or eventName))
        end
        self.isConnected = false
        return
    end
end

function LocalLobbyLayer:handleRoomsFound(payload)
    -- payload: JSON array [{"name","host_ip","port","players","max"}]
    local rooms = {}
    for ip, name in string.gmatch(tostring(payload or ''),
            '"host_ip"%s*:%s*"([^"]+)"[^{]-"name"%s*:%s*"([^"]+)"') do
        rooms[#rooms + 1] = {ip = ip, name = name}
    end
    -- fallback order (name sebelum ip)
    if #rooms == 0 then
        for name, ip in string.gmatch(tostring(payload or ''),
                '"name"%s*:%s*"([^"]+)"[^{]-"host_ip"%s*:%s*"([^"]+)"') do
            rooms[#rooms + 1] = {ip = ip, name = name}
        end
    end
    if #rooms == 0 then
        self:setStatus('Tidak ada room')
        return
    end
    self.rooms = rooms
    local room = rooms[1]
    self:setStatus('Room: ' .. room.name)
    self:setInfo('Connect ke ' .. room.ip .. ':' .. MABAR_PORT)
    lanScanStop()
    lanJoin(room.ip, MABAR_PORT)
end

function LocalLobbyLayer:handleBtDevices(payload)
    -- payload: JSON array [{"addr","name","paired"}]
    local devices = {}
    for addr, name in string.gmatch(tostring(payload or ''),
            '"addr"%s*:%s*"([^"]+)"[^{]-"name"%s*:%s*"([^"]*)"') do
        if addr and addr ~= '' then
            devices[#devices + 1] = {addr = addr, name = name}
        end
    end
    if #devices == 0 then
        self:setStatus('Tidak ada device')
        return
    end
    self.devices = devices
    local device = devices[math.min(self._deviceIndex, #devices)]
    self:setStatus('Device: ' .. device.name)
    self:setInfo('Connect ke ' .. device.addr)
    btScanStop()
    self._deviceIndex = self._deviceIndex + 1
    btConnect(device.addr)
end
