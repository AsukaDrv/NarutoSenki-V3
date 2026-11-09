APP_STL := c++_shared

APP_CPPFLAGS :=  -std=c++2a -frtti -fsigned-char -fexceptions
APP_LDFLAGS := -latomic -Wl,-z,max-page-size=16384

APP_SHORT_COMMANDS := true

ifeq ($(NDK_DEBUG),1)
  APP_CPPFLAGS += -DNDEBUG -DCOCOS2D_DEBUG=1
else
  APP_CPPFLAGS += -DCOCOS2D_DEBUG=0
endif
