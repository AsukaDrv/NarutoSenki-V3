LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := cocos2dcpp

LOCAL_MODULE_FILENAME := libcocos2dcpp

COCOS_ROOT := $(LOCAL_PATH)/../../../../../

LOCAL_SRC_FILES := narutosenki/main.cpp \
	    ../../../Classes/AppDelegate.cpp \
		../../../Classes/ActionButton.cpp \
		../../../Classes/CharacterBase.cpp \
		../../../Classes/BGLayer.cpp \
		../../../Classes/CreditsLayer.cpp \
		../../../Classes/Effect.cpp \
		../../../Classes/Element.cpp \
		../../../Classes/GameLayer.cpp \
		../../../Classes/GameOver.cpp \
		../../../Classes/GameScene.cpp \
		../../../Classes/GearLayer.cpp \
		../../../Classes/HPBar.cpp \
		../../../Classes/HudLayer.cpp \
		../../../Classes/JoyStick.cpp \
		../../../Classes/LoadLayer.cpp \
		../../../Classes/PauseLayer.cpp \
		../../../Classes/SelectLayer.cpp \
		../../../Classes/StartMenu.cpp \
		../../../Classes/GameLoginHttp.cpp \
		../../../Classes/Mods/ModRegistry.cpp \
		../../../Classes/MyUtils/CCScrewLayer.cpp \
		../../../Classes/MyUtils/CCShake.cpp \
		../../../Classes/MyUtils/CCStrokeLabel.cpp \
		../../../Classes/MyUtils/KTools.cpp \
		../../../Classes/MyUtils/MD5ChecksumDefines.cpp \
		../../../Classes/UI/GameModeLayer.cpp \
        ../../../../../external/sqlite3/src/sqlite3.c \

LOCAL_C_INCLUDES := $(LOCAL_PATH)/../../../Classes \
					$(LOCAL_PATH)/../../../Classes/Core \
					$(COCOS_ROOT)/external \
					$(COCOS_ROOT)/external/sqlite3/src \

LOCAL_WHOLE_STATIC_LIBRARIES += cocos2dx_static
LOCAL_WHOLE_STATIC_LIBRARIES += cocosdenshion_static
LOCAL_WHOLE_STATIC_LIBRARIES += cocos_lua_static
LOCAL_WHOLE_STATIC_LIBRARIES += cocos_extension_static

include $(BUILD_SHARED_LIBRARY)

$(call import-module,cocos2dx)
$(call import-module,CocosDenshion/android)
$(call import-module,extensions)
$(call import-module,scripting/lua/proj.android)
