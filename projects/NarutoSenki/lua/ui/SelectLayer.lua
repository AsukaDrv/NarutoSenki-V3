--
-- SelectLayer — UI pilih karakter ala Naruto Ultimate Ninja Storm 4
--
-- Layout (design 570x320, FIXED_HEIGHT — display.width bisa lebih lebar):
--   [ KIRI ]  panel art besar hero (half art) + nama
--   [ KANAN ] grid tile 7x3 (3 halaman), cursor emas ala Storm 4
--   [ BAWAH ] panah ganti halaman + indikator halaman
--
-- Semua logika network/mabar/custom dari versi lama tetap dipertahankan.
--

local function extractJsonStringField(payload, fieldName)
    local pattern = '"' .. fieldName .. '"%s*:%s*"([^"]+)"'
    return string.match(payload or '', pattern)
end

local function extractJsonNumberField(payload, fieldName)
    local pattern = '"' .. fieldName .. '"%s*:%s*(%d+)'
    local value = string.match(payload or '', pattern)
    if not value then return nil end
    return tonumber(value)
end

-- Catatan: pola Lua tidak punya alternasi '|'. Jangan pakai (true|false).
local function extractJsonBoolField(payload, fieldName)
    local head = '"' .. fieldName .. '"%s*:%s*'
    local v = string.match(payload or '', head .. '(true)')
    if v == 'true' then return true end
    v = string.match(payload or '', head .. '(false)')
    if v == 'false' then return false end
    return nil
end

local function hasFrame(name)
    return CCSpriteFrameCache:sharedSpriteFrameCache():spriteFrameByName(name) ~= nil
end

-- ----------------------------------------------------------------------
-- init — layout gaya Storm 4
-- ----------------------------------------------------------------------
function SelectLayer:init()
    log('Initial SelectLayer (Storm4 UI)...')

    self.mode = _G.mode
    self.enableCustomSelect = _G.enableCustomSelect
    if self.mode == GameMode.Clone or self.mode == GameMode.OneVsOne then
        self.enableCustomSelect = false
        self.is3v3Mode = false
        self.is4v4Mode = false
    else
        self.is3v3Mode = self.mode == GameMode.Classic or self.mode ==
                             GameMode.RandomDeathmatch
        self.is4v4Mode = self.mode == GameMode.FourVsFour or self.mode ==
                             GameMode.HardCore_4Vs4
    end
    self.enableHardCore = false

    self.pageNum = 3

    self._comLabel1 = nil
    self._comLabel2 = nil
    self._comLabel3 = nil
    self._com1Select = nil
    self._com2Select = nil
    self._com3Select = nil

    self._heroName = nil
    self._heroHalfImage = nil

    self.pageLayers = {}
    self.pageButtons = {}

    self._playerSelect = nil
    self.selectHero = nil
    -- Mabar lokal (WiFi LAN / Hotspot / Bluetooth): host/client via Lua link API
    self.isLocalMabar = _G.__localMabarActive == true
    self._mabarIsHost = (_G.__localMabarRole == 'host')
    self.isNetworkMode = _G.__networkMatchId ~= nil or self.isLocalMabar
    self._networkVsBot = self.isNetworkMode and (_G.__networkVsBot == true)
    _G.__networkVsBot = nil
    self._remoteHero = nil
    self._remoteLocked = false
    self._networkInfoLabel = nil
    self._networkLockLabel = nil
    self._networkCountdownLabel = nil
    self._localLocked = false
    self._networkGameStarting = false
    self._networkStartDelay = nil
    self._networkStartElapsed = 0
    self._countdownSeconds = 25
    self._countdownElapsed = 0
    self._lockFx = nil

    tools.addSprites('Record.plist', 'Record2.plist', 'Select.plist',
                     'UI.plist', 'Report.plist', 'Ougis.plist', 'Ougis2.plist',
                     'Map.plist', 'Gears.plist')

    local width, height = display.width, display.height

    -- Training (offline / GameModeLayer): red backdrop. Online match: blue unless custom roster.
    local bg_src
    if self.isNetworkMode then
        bg_src = self.enableCustomSelect and 'red_bg.png' or 'blue_bg.png'
    else
        bg_src = 'red_bg.png'
    end
    local bgSprite = display.newSprite(bg_src, 0, 0)
    bgSprite:setAnchorPoint(0, 0)
    bgSprite:fullScreen()
    self:addChild(bgSprite, -5)

    -- Overlay gelap sinematik ala Storm 4
    local dim = CCLayerColor:create(ccc4(8, 8, 14, 110))
    dim:setPosition(0, 0)
    self:addChild(dim, -4)

    -- menu bar bawah & atas (bingkai layar, tetap dipakai)
    local menu_bar_b = display.newSprite('menu_bar2.png')
    menu_bar_b:setAnchorPoint(0, 0)
    menu_bar_b:fullScreen()
    self:addChild(menu_bar_b, 2)

    local menu_bar_t = display.newSprite('menu_bar3.png')
    menu_bar_t:setAnchorPoint(0, 0)
    menu_bar_t:setPosition(0, height - menu_bar_t:getContentSize().height)
    menu_bar_t:fullScreen()
    self:addChild(menu_bar_t, 2)

    -- ------------------------------------------------------------------
    -- Panel art besar (kiri) — gaya Storm 4
    -- ------------------------------------------------------------------
    self._bigArtMode = not (self.enableCustomSelect and
                                (self.is3v3Mode or self.is4v4Mode))

    local panelScale = 0.85
    local panelX, panelBottom = 6, (height - 200 * panelScale) / 2
    if not self._bigArtMode then
        panelBottom = 24
    end
    local artPanel = display.newSprite('UI/storm_art_panel.png', panelX,
                                       panelBottom)
    artPanel:setAnchorPoint(0, 0)
    artPanel:setScale(panelScale)
    self:addChild(artPanel, 1)

    local hero = 'Naruto'
    self._artCenter = CCPoint(panelX + 176 * panelScale / 2,
                              panelBottom + 200 * panelScale / 2)
    self._nameY = panelBottom + 200 * panelScale + 2

    -- Mode kecil di atas panel
    local modeName = 'TRAINING'
    if self.isLocalMabar then
        modeName = self._mabarIsHost and 'MABAR (HOST)' or 'MABAR (CLIENT)'
    elseif self.isNetworkMode then
        modeName = 'ONLINE MATCH'
    elseif self.is4v4Mode then
        modeName = '4 VS 4'
    elseif self.is3v3Mode then
        modeName = '3 VS 3'
    elseif self.mode == GameMode.OneVsOne then
        modeName = '1 VS 1'
    elseif self.mode == GameMode.Clone then
        modeName = 'CLONE'
    elseif self.mode == GameMode.HardCore then
        modeName = 'HARDCORE'
    elseif self.mode == GameMode.RandomDeathmatch then
        modeName = 'RANDOM DEATHMATCH'
    end
    local modeLabel = display.newTTFLabelWithShadow({
        text = modeName,
        size = 11,
        x = self._artCenter.x,
        y = panelBottom - 12,
        align = ui.TEXT_ALIGN_CENTER
    })
    self:addChild(modeLabel, 6)

    -- ------------------------------------------------------------------
    -- Grid tile karakter (kanan) — 7 kolom x 3 baris per halaman
    -- ------------------------------------------------------------------
    local tileW, tileH = 35, 65
    local cols, rows = 7, 3
    local gap = 6
    local rightReserve = 100            -- ruang tombol start/skill
    local topLimit = height - 44
    local bottomLimit = 28

    -- lebar tersedia untuk grid
    local panelRight = panelX + 176 * panelScale + 10
    local availW = width - 12 - rightReserve - panelRight
    local scale = math.min(1.25, (availW + gap) / cols / tileW - gap / tileW)
    if scale > topLimit - bottomLimit then
        scale = 1.0
    end
    -- batas vertikal: pitchY = tileH*scale + gap harus muat rows baris
    local maxPitchY = (topLimit - bottomLimit) / rows
    if tileH * scale + gap > maxPitchY then
        scale = math.max(0.6, (maxPitchY - gap) / tileH)
    end
    if scale < 0.6 then scale = 0.6 end
    self._tileScale = scale

    local pitchX = tileW * scale + gap
    local pitchY = tileH * scale + gap
    local gridW = cols * pitchX - gap
    local gridH = rows * pitchY - gap
    local gridX = width - 12 - rightReserve - gridW
    if gridX < panelRight then gridX = panelRight end
    local rowTopY = topLimit - tileH * scale
    self._gridRect = {x = gridX, y = rowTopY, w = gridW, h = gridH,
                      pitchX = pitchX, pitchY = pitchY}

    -- backdrop gelap grid ala Storm 4
    local gridBg = CCLayerColor:create(ccc4(12, 12, 20, 150))
    gridBg:setContentSize(CCSize(gridW + 14, gridH + 14))
    gridBg:setAnchorPoint(0, 0)
    gridBg:setPosition(gridX - 7, rowTopY - 7)
    self:addChild(gridBg, 3)

    -- judul kecil di pojok kiri atas
    local titleLabel = display.newTTFLabelWithShadow({
        text = 'PILIH NINJAMU',
        size = 14,
        x = 14,
        y = height - 26,
        align = ui.TEXT_ALIGN_LEFT
    })
    self:addChild(titleLabel, 6)

    -- halaman (TouchGroup) — mekanisme lama dipertahankan
    local selectNameList = {}
    local selectButtons = {}

    for i = 1, self.pageNum do
        local index = i
        local pageLayer = TouchGroup:create()
        self:addChild(pageLayer, 5)
        if i == 1 then
            pageLayer:show()
        else
            pageLayer:hide()
            pageLayer:setPositionY(2000)
        end
        table.insert(self.pageLayers, pageLayer)
    end

    local charactersList = ns.CharactersLayout
    local pageNum = #self.pageLayers

    for i = 1, #charactersList do
        local charName = charactersList[i]
        selectNameList[#selectNameList + 1] = charName

        local idx = i - 1
        local column = idx % cols
        local row = toint(idx / cols)
        local page = toint(idx / (cols * rows))

        local selectSkin = charName
        if charName == 'None' and not self.isNetworkMode then
            selectSkin = 'None3'
        end
        local select_btn = SelectButton:create(selectSkin .. '_select.png')
        select_btn._selectLayer = self
        select_btn._charName = charName
        select_btn:setScale(scale)
        local px = gridX + column * pitchX
        local py = rowTopY - (row - rows * page) * pitchY
        if py > rowTopY then py = rowTopY end
        select_btn:setPosition(CCPoint(px, py))

        if page + 1 > pageNum then
            log('Select page index out of range')
            break
        end
        self.pageLayers[page + 1]:addWidget(select_btn)

        selectButtons[#selectButtons + 1] = select_btn
    end

    self.selectButtons = selectButtons
    self.selectNameList = selectNameList
    self:setSelectList(table.toCCArray(selectNameList))

    -- art besar awal
    local firstHero = selectNameList[1] or hero
    self:updateBigArt(firstHero)

    -- cursor emas ala Storm 4 (menggantikan ikon '1p' kedip lama)
    local firstBtn = selectButtons[1]
    self.selectHero = firstBtn and firstBtn._charName or firstHero
    if firstBtn then
        local fx, fy = self:cursorPosForTile(firstBtn)
        local cursor = display.newSprite('UI/storm_frame.png', fx, fy)
        cursor:setAnchorPoint(0, 0)
        self:addChild(cursor, 500)
        self._selectImg = cursor
        self:startCursorPulse()
    end

    if self.enableCustomSelect then
        if self.is3v3Mode or self.is4v4Mode then
            self:initCustomSelectMode()
        end
    end

    -- ------------------------------------------------------------------
    -- Panah halaman (bawah grid) + indikator halaman — gaya Storm 4
    -- ------------------------------------------------------------------
    self._currentPage = 1
    local arrowY = 18
    local arrowCenterX = gridX + gridW / 2

    local leftArrow = ui.newImageMenuItem({
        image = 'UI/storm_arrow_left.png',
        listener = function() self:onPageButtonClick(self._currentPage - 1) end
    })
    local leftMenu = ui.newMenu({leftArrow})
    leftMenu:setPosition(arrowCenterX - 44, arrowY)
    self:addChild(leftMenu, 10)

    local rightArrow = ui.newImageMenuItem({
        image = 'UI/storm_arrow_right.png',
        listener = function() self:onPageButtonClick(self._currentPage + 1) end
    })
    local rightMenu = ui.newMenu({rightArrow})
    rightMenu:setPosition(arrowCenterX + 44, arrowY)
    self:addChild(rightMenu, 10)

    self._pageLabel = display.newTTFLabelWithShadow({
        text = '1 / ' .. tostring(pageNum),
        size = 12,
        x = arrowCenterX,
        y = arrowY + 1,
        align = ui.TEXT_ALIGN_CENTER
    })
    self:addChild(self._pageLabel, 10)

    local hint = display.newTTFLabelWithShadow({
        text = 'Ketuk 2x untuk konfirmasi ninja',
        size = 9,
        x = 14,
        y = height - 44,
        align = ui.TEXT_ALIGN_LEFT
    })
    self:addChild(hint, 10)

    -- ------------------------------------------------------------------
    -- Tombol aksi (kanan)
    -- ------------------------------------------------------------------
    local start_btn = ui.newImageMenuItem({
        image = '#start_btn.png',
        listener = function()
            if self.isLocalMabar and self._mabarIsHost then
                self:onMabarHostStart()
            elseif not self.isNetworkMode then
                self:onGameStart()
            end
        end
    })
    local menu = ui.newMenu({start_btn})
    menu:setAnchorPoint(0, 0)
    menu:setPosition(width - 44, 36)
    self:addChild(menu, 5)
    -- Mabar lokal: hanya HOST yang boleh memulai kedua sisi
    if self.isNetworkMode and not (self.isLocalMabar and self._mabarIsHost) then
        menu:setVisible(false)
    end

    local skill_btn = ui.newImageMenuItem({
        image = '#skill_btn.png',
        listener = handler(self, SelectLayer.onSkillMenuButtonClick)
    })
    local menu2 = ui.newMenu({skill_btn})
    menu2:setAnchorPoint(0, 0)
    menu2:setPosition(width - 36, 104)
    self:addChild(menu2, 5)

    local ranking_btn = ui.newImageMenuItem({
        image = '#ranking_btn.png',
        listener = handler(self, SelectLayer.onRankingButtonClick)
    })
    ranking_btn:setAnchorPoint(1, 0.5)
    local menu3 = ui.newMenu({ranking_btn})
    menu3:setPosition(width - 10, height - 30)
    self:addChild(menu3, 5)

    -- Desktop return button
    if _G.platform == 'desktop' then
        local return_btn = ui.newImageMenuItem({
            image = '#return_btn.png',
            listener = backToStartMenu
        })
        local menu4 = ui.newMenu({return_btn})
        menu4:setAnchorPoint(0, 0)
        menu4:setPosition(width - 36, 150)
        self:addChild(menu4, 5)
    end

    if save.isBGM() then audio.playMusic(ns.music.SELECT_MUSIC, true) end

    if self.isNetworkMode then
        _G.__networkSelectLayer = self
        self._networkInfoLabel = ui.newTTFLabelWithShadow({
            text = 'Opponent: waiting...',
            size = 11,
            x = display.cx,
            y = height - 22,
            align = ui.TEXT_ALIGN_CENTER
        })
        self:addChild(self._networkInfoLabel, 50)
        self._networkLockLabel = ui.newTTFLabelWithShadow({
            text = 'You: Pick',
            size = 11,
            x = display.cx,
            y = height - 38,
            align = ui.TEXT_ALIGN_CENTER
        })
        self:addChild(self._networkLockLabel, 50)
        self._networkCountdownLabel = ui.newTTFLabelWithShadow({
            text = 'The match will start in 25s',
            size = 11,
            x = display.cx,
            y = height - 54,
            align = ui.TEXT_ALIGN_CENTER
        })
        self:addChild(self._networkCountdownLabel, 50)
        self:scheduleUpdateWithPriorityLua(handler(self, SelectLayer.update), 0)
    end
end

-- ----------------------------------------------------------------------
-- Visual helpers (Storm 4)
-- ----------------------------------------------------------------------
function SelectLayer:makeCursorPulse()
    local pulseUp = CCScaleTo:create(0.55, 1.05)
    local pulseDown = CCScaleTo:create(0.55, 1.0)
    return CCRepeatForever:create(transition.sequence({pulseUp, pulseDown}))
end

function SelectLayer:startCursorPulse()
    if not self._selectImg then return end
    self._selectImg:stopAllActions()
    self._selectImg:runAction(self:makeCursorPulse())
end

function SelectLayer:cursorPosForTile(btn)
    local s = self._tileScale or 1.0
    local fw, fh = 52, 92
    return btn:getPositionX() - (fw - 35 * s) / 2,
           btn:getPositionY() - (fh - 65 * s) / 2
end

--- Ganti art besar + nama (dengan transisi ala Storm 4).
function SelectLayer:updateBigArt(charName)
    local scale = 0.85

    if self._heroHalfImage then
        self._heroHalfImage:removeFromParent()
        self._heroHalfImage = nil
    end

    local artName = '#' .. charName .. '_half.png'
    local art
    if hasFrame(charName .. '_half.png') then
        art = display.newSprite(artName, self._artCenter.x, self._artCenter.y)
    else
        -- fallback: strip sprite select diperbesar
        local skinName = charName
        if charName == 'None' and not self.isNetworkMode then
            skinName = 'None3'
        end
        if hasFrame(skinName .. '_select.png') then
            art = display.newSprite('#' .. skinName .. '_select.png',
                                    self._artCenter.x, self._artCenter.y + 10)
            scale = scale * 1.6
        end
    end

    if art then
        art:setScale(scale * 0.4)
        art:setOpacity(0)
        self:addChild(art, 2)
        local fadeIn = CCFadeIn:create(0.12)
        local zoomIn = CCEaseBackOut:create(CCScaleTo:create(0.22, scale))
        art:runAction(fadeIn)
        art:runAction(zoomIn)
        self._heroHalfImage = art
    end

    -- nama
    if self._heroName then
        self._heroName:removeFromParent()
        self._heroName = nil
    end
    if hasFrame(charName .. '_font.png') then
        local fontArt = display.newSprite('#' .. charName .. '_font.png',
                                          self._artCenter.x,
                                          self._artCenter.y + 105)
        fontArt:setAnchorPoint(0.5, 0)
        fontArt:setScale(0.62)
        self:addChild(fontArt, 6)
        self._heroName = fontArt
    else
        local label = display.newTTFLabelWithShadow({
            text = charName,
            size = 15,
            x = self._artCenter.x,
            y = self._artCenter.y + 100,
            align = ui.TEXT_ALIGN_CENTER
        })
        label:setColor(ccc3(232, 176, 58))
        self:addChild(label, 6)
        self._heroName = label
    end
end

--- Tampilkan/tutup efek lock merah pada tile yang dipilih.
function SelectLayer:setLockFxOnTile(btn)
    if self._lockFx then
        self._lockFx:removeFromParent()
        self._lockFx = nil
    end
    if not btn then return end
    local s = self._tileScale or 1.0
    local fx, fy = self:cursorPosForTile(btn)
    local lockFrame = display.newSprite('UI/storm_lock_frame.png', fx, fy)
    lockFrame:setAnchorPoint(0, 0)
    self:addChild(lockFrame, 499)

    local badge = display.newSprite('UI/storm_lock.png',
                                    btn:getPositionX() + 35 * s - 6,
                                    btn:getPositionY() + 65 * s - 6)
    badge:setAnchorPoint(0.5, 0.5)
    self:addChild(badge, 501)

    self._lockFx = lockFrame
    self._lockBadge = badge
end

function SelectLayer:initCustomSelectMode()
    log('Initial Custom Select Mode...')
    local teamSelector = display.newLayer()

    local teamBg = display.newSprite('#team_bg.png', 0, 185)
    teamBg:setAnchorPoint(0, 0)
    teamSelector:addChild(teamBg)

    -- init com selector 1
    local comSelector1 = display.newSprite('#unknow_select.png', 2, 194)
    comSelector1:setAnchorPoint(0, 0)
    teamSelector:addChild(comSelector1)
    self._comSelector1 = comSelector1

    self._comLabel1 = display.newSprite('#com_label.png')
    self._comLabel1:setPosition(comSelector1:getPositionX() +
                                    comSelector1:getContentSize().width + 2 + 18,
                                comSelector1:getPositionY() +
                                    comSelector1:getContentSize().height / 2)
    teamSelector:addChild(self._comLabel1)

    -- init com selector 2
    local comSelector2 = display.newSprite('#unknow_select.png')
    comSelector2:setAnchorPoint(0, 0)
    comSelector2:setPosition(comSelector1:getPositionX() +
                                 comSelector1:getContentSize().width + 40,
                             comSelector1:getPositionY())
    teamSelector:addChild(comSelector2)

    self._comLabel2 = display.newSprite('#com_label.png')
    self._comLabel2:setPosition(comSelector2:getPositionX() +
                                    comSelector2:getContentSize().width + 2 + 18,
                                comSelector2:getPositionY() +
                                    comSelector2:getContentSize().height / 2)
    teamSelector:addChild(self._comLabel2)
    self._comSelector2 = comSelector2

    -- init com selector 3
    if self.is4v4Mode then
        local comSelector3 = display.newSprite('#unknow_select.png')
        comSelector3:setAnchorPoint(0, 0)
        comSelector3:setPosition(comSelector2:getPositionX() +
                                     comSelector2:getContentSize().width + 40,
                                 comSelector2:getPositionY())
        teamSelector:addChild(comSelector3)

        self._comLabel3 = display.newSprite('#com_label.png')
        self._comLabel3:setPosition(comSelector3:getPositionX() +
                                        comSelector3:getContentSize().width + 3 +
                                        18, comSelector3:getPositionY() +
                                        comSelector3:getContentSize().height / 3)
        teamSelector:addChild(self._comLabel3)
        self._comSelector3 = comSelector3
    end

    self:addChild(teamSelector, 50)
end

function SelectLayer:onQuestBtn()
    -- not support
    self:setTip('ComingSoon')
end

function SelectLayer:onRankingButtonClick()
    -- not support
    self:setTip('ComingSoon')
end

function SelectLayer:onSkillMenuButtonClick()
    local scene = CCScene:create()
    local skillLayer = SkillLayer:create(self)
    scene:addChild(skillLayer)

    director.pushScene(scene)
end

function SelectLayer:onPageButtonClick(index)
    audio.playSound(ns.menu.SELECT_SOUND)

    local total = #self.pageLayers
    if total == 0 then return end
    -- wrap-around ala Storm 4 (panah muter halaman)
    index = ((index - 1) % total) + 1
    self._currentPage = index

    if self._pageLabel then
        self._pageLabel:setString(tostring(index) .. ' / ' .. tostring(total))
    end

    for i, pageLayer in pairs(self.pageLayers) do
        if i == index then
            pageLayer:show()
            pageLayer:setPositionY(0)
        else
            pageLayer:hide()
            pageLayer:setPositionY(10000)
        end
    end

    -- cursor tetap terlihat di tile yang sedang dipilih
    if self._selectImg then
        self._selectImg:setVisible(true)
    end
end

function SelectLayer:setSelected(btn)
    -- cursor emas pindah ke tile (animasi cepat ala Storm 4), lalu pulse lagi
    if self._selectImg then
        local fx, fy = self:cursorPosForTile(btn)
        self._selectImg:stopAllActions()
        local move = CCEaseOut:create(CCMoveTo:create(0.10, CCPoint(fx, fy)), 2.5)
        self._selectImg:runAction(transition.sequence({move, self:makeCursorPulse()}))
    end

    if not self.enableCustomSelect and self._playerSelect then return end

    self.selectHero = btn._charName
    self:updateNetworkInfoLabel()
    if self.isNetworkMode and wsIsConnected() then
        wsSend('{"type":"select_update","hero":"' .. tostring(self.selectHero) .. '"}')
    elseif self.isLocalMabar then
        linkSend('{"type":"select_update","hero":"' .. tostring(self.selectHero) .. '"}')
    end

    local fd = CCFadeOut:create(1.0)
    local seq = CCRepeatForever:create(transition.sequence({fd, fd:reverse()}))

    if not self._playerSelect then
        if btn._clickTime >= 2 then
            self:setSelectHero(btn._charName)
            self._playerSelect = self.selectHero
            self._localLocked = true
            self:updateNetworkInfoLabel()
            if self.isNetworkMode and wsIsConnected() then
                wsSend('{"type":"select_lock","hero":"' .. tostring(self._playerSelect) .. '"}')
            elseif self.isLocalMabar then
                linkSend('{"type":"select_lock","hero":"' .. tostring(self._playerSelect) .. '"}')
            end

            -- efek lock merah ala Storm 4 + zoom art
            self:setLockFxOnTile(btn)
            if self._heroHalfImage then
                self._heroHalfImage:stopAllActions()
                self._heroHalfImage:runAction(
                    CCEaseBackOut:create(CCScaleTo:create(0.25,
                        (self._heroHalfImage:getScale() < 1.0) and 1.0 or
                        self._heroHalfImage:getScale() * 1.06)))
            end

            if not self.enableCustomSelect then
                if self._selectImg then
                    self._selectImg:removeFromParent()
                    self._selectImg = nil
                end
            else
                if self._comLabel1 then
                    self._comLabel1:runAction(seq)
                end
            end
        end

        self:updateBigArt(btn._charName)
    elseif not self._com1Select then
        self._comSelector1:setDisplayFrame(
            display.newSpriteFrame(self.selectHero .. '_small.png'))

        if btn._clickTime >= 2 then
            self._com1Select = self.selectHero
            self:setCom1Select(self._com1Select)

            self._comLabel1:stopAllActions()
            self._comLabel1:setOpacity(255)
            self._comLabel1:setDisplayFrame(
                display.newSpriteFrame('com_label2.png'))
        end
    elseif not self._com2Select then
        self._comSelector2:setDisplayFrame(
            display.newSpriteFrame(self.selectHero .. '_small.png'))

        if btn._clickTime >= 2 then
            self._com2Select = self.selectHero
            self:setCom2Select(self._com2Select)

            self._comLabel2:stopAllActions()
            self._comLabel2:setOpacity(255)
            self._comLabel2:setDisplayFrame(
                display.newSpriteFrame('com_label2.png'))
        end
    elseif not self._com3Select then
        self._comSelector3:setDisplayFrame(
            display.newSpriteFrame(self.selectHero .. '_small.png'))

        if btn._clickTime >= 2 then
            self._com3Select = self.selectHero
            self:setCom3Select(self._com3Select)

            self._comLabel3:stopAllActions()
            self._comLabel3:setOpacity(255)
            self._comLabel3:setDisplayFrame(
                display.newSpriteFrame('com_label2.png'))

            if self._selectImg then
                self._selectImg:removeFromParent()
                self._selectImg = nil
            end
        end
    end
end

function SelectLayer:updateNetworkInfoLabel()
    if not self._networkInfoLabel then return end

    local hero = self._remoteHero or '-'
    local lockText = self._remoteLocked and ' [Picked]' or ''
    local text = 'Enemy: ' .. hero .. lockText
    if self._networkInfoLabel.label then
        self._networkInfoLabel.label:setString(text)
    end
    if self._networkInfoLabel.shadow1 then
        self._networkInfoLabel.shadow1:setString(text)
    end

    if self._networkLockLabel then
        local localHero = self.selectHero or '-'
        local localLockText = self._localLocked and ' [Picked]' or ''
        local lockInfo = 'You: ' .. localHero .. localLockText
        if self._networkLockLabel.label then
            self._networkLockLabel.label:setString(lockInfo)
        end
        if self._networkLockLabel.shadow1 then
            self._networkLockLabel.shadow1:setString(lockInfo)
        end
    end

    if self._networkCountdownLabel then
        local countdownText = tostring(math.max(self._countdownSeconds, 0)) .. 's'
        local countdownInfo = 'The match will start in ' .. countdownText
        if self._networkCountdownLabel.label then
            self._networkCountdownLabel.label:setString(countdownInfo)
        end
        if self._networkCountdownLabel.shadow1 then
            self._networkCountdownLabel.shadow1:setString(countdownInfo)
        end
    end
end

function SelectLayer:autoPickRandomHero()
    if self._playerSelect or not self.selectButtons or #self.selectButtons == 0 then
        return
    end

    local index = math.random(1, #self.selectButtons)
    local randomBtn = self.selectButtons[index]
    if not randomBtn then return end

    randomBtn._clickTime = 2
    self:setSelected(randomBtn)
end

function SelectLayer:update(dt)
    if not self.isNetworkMode then return end
    if self._networkStartDelay ~= nil then
        self._networkStartElapsed = self._networkStartElapsed + dt
        local remain = math.ceil(self._networkStartDelay - self._networkStartElapsed)
        if remain <= 0 then remain = 0 end

        if self._networkCountdownLabel then
            local countdownInfo = 'The match will start in ' .. tostring(remain) .. 's'
            if self._networkCountdownLabel.label then
                self._networkCountdownLabel.label:setString(countdownInfo)
            end
            if self._networkCountdownLabel.shadow1 then
                self._networkCountdownLabel.shadow1:setString(countdownInfo)
            end
        end

        if self._networkStartElapsed >= self._networkStartDelay then
            self._networkStartDelay = nil
            if not self._networkGameStarting then
                self._networkGameStarting = true
                _G.__networkSelectLayer = nil
                self:onGameStart()
            end
        end
        return
    end
    if self._networkGameStarting then return end
    if self._countdownSeconds <= 0 then return end

    self._countdownElapsed = self._countdownElapsed + dt
    if self._countdownElapsed < 1 then return end

    self._countdownElapsed = self._countdownElapsed - 1
    self._countdownSeconds = self._countdownSeconds - 1
    self:updateNetworkInfoLabel()

    -- Lawan bot: auto-pilih hero acak saat sisa waktu <= 10 detik (PVP tetap di detik 0).
    local pickDeadline = self._networkVsBot and 10 or 0
    if self._countdownSeconds <= pickDeadline and not self._localLocked then
        self:autoPickRandomHero()
        self:updateNetworkInfoLabel()
    end
end

function SelectLayer:handleWebSocketEvent(eventName, payload)
    if not self.isNetworkMode then return end
    if eventName == 'close' or eventName == 'error' then
        if not self._networkGameStarting then
            backToStartMenu()
        end
        return
    end
    if eventName ~= 'message' then return end

    local messageType = extractJsonStringField(payload, 'type')
    if messageType == 'select_update' then
        self._remoteHero = extractJsonStringField(payload, 'hero') or self._remoteHero
        self._remoteLocked = false
        self:updateNetworkInfoLabel()
    elseif messageType == 'select_lock' then
        self._remoteHero = extractJsonStringField(payload, 'hero') or self._remoteHero
        self._remoteLocked = true
        self:updateNetworkInfoLabel()
    elseif messageType == 'both_locked' then
        -- Wait for `match_start` packet so both clients start together.
    elseif messageType == 'match_start' then
        local vsBot = extractJsonBoolField(payload, 'opponentIsBot') == true
        if not vsBot and (not self._localLocked or not self._remoteLocked) then
            return
        end
        local delayMs = extractJsonNumberField(payload, 'delayMs') or 1500
        self._networkStartDelay = delayMs / 1000
        self._networkStartElapsed = 0
        local mapId = extractJsonNumberField(payload, 'mapId') or 1
        local team = extractJsonNumberField(payload, 'team')
        if team == nil then team = 0 end
        local yourHero = extractJsonStringField(payload, 'yourHero')
        local enemyHero = extractJsonStringField(payload, 'enemyHero')
        local yourTeamCsv = extractJsonStringField(payload, 'yourTeamCsv')
        local enemyTeamCsv = extractJsonStringField(payload, 'enemyTeamCsv')
        local yourNick = extractJsonStringField(payload, 'yourNickname')
        local enemyNick = extractJsonStringField(payload, 'enemyNickname')
        wsSetMatchConfig(mapId, team, yourHero or '', enemyHero or '',
                         yourTeamCsv or '', enemyTeamCsv or '', vsBot,
                         yourNick or '', enemyNick or '')
        -- keep UI state in sync with authoritative server config
        if yourHero and yourHero ~= '' then
            self.selectHero = yourHero
        end
        if enemyHero and enemyHero ~= '' then
            self._remoteHero = enemyHero
        end
        if vsBot then
            self._remoteLocked = true
        end
        self:updateNetworkInfoLabel()
        local seed = extractJsonNumberField(payload, 'seed')
        if seed then
            math.randomseed(seed)
        end
    elseif messageType == 'mabar_start' then
        -- Mabar lokal: HOST yang mengirim config start (map + hero kedua sisi)
        if not self.isLocalMabar then return end
        local delayMs = extractJsonNumberField(payload, 'delayMs') or 1500
        self._networkStartDelay = delayMs / 1000
        self._networkStartElapsed = 0
        local mapId = extractJsonNumberField(payload, 'mapId') or 1
        local hostHero = extractJsonStringField(payload, 'hostHero') or ''
        local clientHero = extractJsonStringField(payload, 'clientHero') or ''
        local yourHero, enemyHero, team
        if self._mabarIsHost then
            yourHero = hostHero
            enemyHero = clientHero
            team = 0
        else
            yourHero = clientHero
            enemyHero = hostHero
            team = 1
        end
        wsSetMatchConfig(mapId, team, yourHero, enemyHero, '', '', false, '', '')
        if yourHero ~= '' then
            self.selectHero = yourHero
            self._playerSelect = yourHero
            self._localLocked = true
        end
        if enemyHero ~= '' then
            self._remoteHero = enemyHero
            self._remoteLocked = true
        end
        self:updateNetworkInfoLabel()
    elseif messageType == 'opponent_left' then
        backToStartMenu()
    end
end

--- Host mabar lokal: kirim config start lalu mulai countdown kedua sisi.
function SelectLayer:onMabarHostStart()
    if not self.isLocalMabar or not self._mabarIsHost then return end
    if not self._playerSelect then
        self:autoPickRandomHero()
    end
    if not self._playerSelect then return end
    local clientHero = self._remoteHero or 'Naruto'
    local msg = '{"type":"mabar_start","mapId":1,"hostHero":"'
        .. tostring(self._playerSelect) .. '","clientHero":"'
        .. tostring(clientHero) .. '","delayMs":1500}'
    linkSend(msg)
    -- Terapkan config di sisi host juga
    wsSetMatchConfig(1, 0, self._playerSelect, clientHero, '', '', false, '', '')
    self._networkStartDelay = 1.5
    self._networkStartElapsed = 0
end

function SelectLayer:noComSelect()
    if self.is4v4Mode then
        return self._com3Select
    elseif self.is3v3Mode then
        return self._com2Select
    else
        return self._playerSelect
    end
end

function backToStartMenu()
    log('back to main menu')

    clearStaleNetworkSessionForMenu()

    _G.mode = nil
    audio.playSound('Audio/Menu/cancel.wav')
    local menuScene = CCScene:create()
    local menuLayer = StartMenu:create()

    hook.registerInitHandlerOnly(menuLayer)
    menuScene:addChild(menuLayer)
    director.replaceSceneWithFade(menuScene, 1)
end
