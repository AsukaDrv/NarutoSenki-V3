#include "CreditsLayer.h"
#include "Data/Config.h"
#include "StartMenu.h"
#include "Constants/UiFlowKeys.hpp"

bool CreditsLayer::init()
{
        RETURN_FALSE_IF(!Layer::init());

        auto bgSprite = Sprite::create("blue_bg.png");
        FULL_SCREEN_SPRITE(bgSprite);
        bgSprite->setAnchorPoint(Vec2(0, 0));
        bgSprite->setPosition(Vec2(0, 0));
        addChild(bgSprite, -5);

        // produce the cloud
        auto cloud_left = Sprite::createWithSpriteFrameName("cloud.png");
        cloud_left->setPosition(Vec2(0, 15));
        cloud_left->setFlipX(true);
        cloud_left->setFlipY(true);
        cloud_left->setAnchorPoint(Vec2(0, 0));
        addChild(cloud_left, 1);

        auto cmv1 = MoveBy::create(1, Vec2(-15, 0));
        auto cseq1 = RepeatForever::create(newSequence(cmv1, cmv1->reverse()));
        cloud_left->runAction(cseq1);

        auto cloud_right = Sprite::createWithSpriteFrameName("cloud.png");
        cloud_right->setPosition(Vec2(winSize.width - cloud_right->getContentSize().width,
                                                                  winSize.height - (cloud_right->getContentSize().height + 15)));
        cloud_right->setAnchorPoint(Vec2(0, 0));
        addChild(cloud_right, 1);

        auto cmv2 = MoveBy::create(1, Vec2(15, 0));
        auto cseq2 = RepeatForever::create(newSequence(cmv2, cmv2->reverse()));
        cloud_right->runAction(cseq2);

        // produce the menu_bar
        auto menu_bar_b = Sprite::create("menu_bar2.png");
        menu_bar_b->setAnchorPoint(Vec2(0, 0));
        FULL_SCREEN_SPRITE(menu_bar_b);
        addChild(menu_bar_b, 2);

        auto menu_bar_t = Sprite::create("menu_bar3.png");
        menu_bar_t->setAnchorPoint(Vec2(0, 0));
        menu_bar_t->setPosition(Vec2(0, winSize.height - menu_bar_t->getContentSize().height));
        FULL_SCREEN_SPRITE(menu_bar_t);
        addChild(menu_bar_t, 2);

        // Overlay gelap sinematik: konten teks lebih fokus & nyaman dibaca
        auto dim = LayerColor::create(ccc4(5, 5, 12, 150), winSize.width, winSize.height);
        dim->setPosition(Vec2(0, 0));
        addChild(dim, 2);

        auto staff_title = Sprite::createWithSpriteFrameName("staff_title.png");
        staff_title->setAnchorPoint(Vec2(0, 0));
        staff_title->setPosition(Vec2(2, winSize.height - staff_title->getContentSize().height - 2));
        addChild(staff_title, 3);

        // ------------------------------------------------------------------
        // Konten kredit terstruktur (gaya Storm 4: emas/putih/abu, fade-in)
        // ------------------------------------------------------------------
        const float cx = winSize.width / 2;
        const float cy = winSize.height / 2;
        const ccColor3B GOLD = ccc3(255, 214, 90);
        const ccColor3B WHITE = ccc3(235, 235, 235);
        const ccColor3B GRAY = ccc3(165, 165, 165);

        float delay = 0.f;
        auto addLine = [&](float y, const char *text, float size,
                           const ccColor3B &color) {
                CCLabelTTF *label = CCLabelTTF::create(text, FONT_NAME, size);
                label->setPosition(Vec2(cx, y));
                label->setColor(color);
                label->setOpacity(0);
                label->runAction(CCSequence::create(
                        CCDelayTime::create(delay), CCFadeIn::create(0.45f), NULL));
                addChild(label, 3);
                delay += 0.07f;
        };
        auto addDivider = [&](float y) {
                auto line = LayerColor::create(ccc4(255, 214, 90, 170), 190, 2);
                line->setPosition(Vec2(cx - 95, y));
                line->setOpacity(0);
                line->runAction(CCSequence::create(
                        CCDelayTime::create(delay), CCFadeIn::create(0.45f), NULL));
                addChild(line, 3);
                delay += 0.07f;
        };

        addLine(cy + 112, "NARUTO SENKI V3", 26, GOLD);
        addLine(cy + 88, "Edisi Mabar - mod & pengembangan oleh BF667", 12, WHITE);
        addDivider(cy + 74);

        addLine(cy + 54, "FITUR", 15, GOLD);
        addLine(cy + 36, "Mabar lokal: WiFi LAN / Hotspot / Bluetooth", 11, WHITE);
        addLine(cy + 21, "Recall ke base & kontrol perbaikan", 11, WHITE);
        addLine(cy + 6, "UI pilih karakter ala Ultimate Ninja Storm 4", 11, WHITE);
        addLine(cy - 9, "Fullscreen tanpa title bar & sistem mod Lua", 11, WHITE);
        addDivider(cy - 24);

        addLine(cy - 44, "TERIMA KASIH", 14, GOLD);
        addLine(cy - 60, "Kwikdanprasya (game asli) + AsukaDrv (NarutoSenki-V3)", 10, WHITE);
        addLine(cy - 74, "Komunitas Naruto Senki & semua pemain", 10, WHITE);
        addLine(cy - 96, "Aset & karakter milik pemiliknya masing-masing.", 9, GRAY);
        addLine(cy - 110, "Dibuat untuk hiburan - bukan produk resmi.", 9, GRAY);

        auto returnBtnItem = MenuItemSprite::create(
                Sprite::create("UI/return_btn.png"),
                nullptr,
                nullptr,
                this,
                menu_selector(CreditsLayer::onReturnBtn));
        auto returnBtnMenu = Menu::create(returnBtnItem, nullptr);
        returnBtnMenu->setPosition(winSize.width - 38, 65);
        addChild(returnBtnMenu, 5);

        if (UserDefault::sharedUserDefault()->getBoolForKey("isBGM"))
                SimpleAudioEngine::sharedEngine()->playBackgroundMusic(CREDITS_MUSIC, true);

        return true;
}

void CreditsLayer::onEnterTransitionDidFinish()
{
        Layer::onEnterTransitionDidFinish();
        setKeypadEnabled(true);
}

void CreditsLayer::keyBackClicked()
{
        setKeypadEnabled(false);

        lua_call_func(UiFlowKeys::kCreditsBackToStartMenu);
}

void CreditsLayer::onReturnBtn(Ref *sender)
{
        (void)sender;
        keyBackClicked();
}
