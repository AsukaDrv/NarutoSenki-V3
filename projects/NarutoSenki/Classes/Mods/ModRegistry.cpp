#include "ModRegistry.hpp"

#include "CCLuaEngine.h"
#include "script_support/CCScriptSupport.h"
#include "platform/CCFileUtils.h"
#include "Utils/CCDeprecated.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

#include <string>
#include <vector>

namespace
{
        /**
         * Sisipkan tabel (stack index 1) ke global registry (tabel Lua).
         * Registry = array Lua: __ns_hero_registry / __ns_mode_registry.
         */
        static void appendRegistryTable(lua_State *L, const char *registryName)
        {
                if (!lua_istable(L, 1))
                {
                        luaL_error(L, "%s: parameter pertama harus table", registryName);
                        return;
                }

                lua_getglobal(L, registryName);
                if (!lua_istable(L, -1))
                {
                        lua_pop(L, 1);
                        lua_newtable(L);
                }

                const int nextIndex = (int)lua_objlen(L, -1) + 1;
                lua_pushvalue(L, 1);      // salin tabel mod
                lua_rawseti(L, -2, nextIndex);
                lua_setglobal(L, registryName);
        }

        static int luaRegisterHero(lua_State *L)
        {
                appendRegistryTable(L, "__ns_hero_registry");
                return 0;
        }

        static int luaRegisterMode(lua_State *L)
        {
                appendRegistryTable(L, "__ns_mode_registry");
                return 0;
        }

        static void initRegistry(lua_State *L, const char *registryName)
        {
                lua_getglobal(L, registryName);
                if (!lua_istable(L, -1))
                {
                        lua_pop(L, 1);
                        lua_newtable(L);
                        lua_setglobal(L, registryName);
                }
                else
                {
                        lua_pop(L, 1);
                }
        }

        /**
         * Jalankan satu script mod. Return true jika sukses.
         * PENTING: executeScriptFile() cocos2d-x 2.2.6 mengembalikan int,
         * 0 = sukses, non-zero = gagal (lihat CCLuaStack.cpp).
         */
        static bool runModScript(LuaEngine *engine, const std::string &path)
        {
                const int ret = engine->executeScriptFile(path.c_str());
                if (ret != 0)
                {
                        CCLOG("[Mods] gagal menjalankan %s (code %d)", path.c_str(), ret);
                        return false;
                }
                return true;
        }

        static std::vector<std::string> parseModList(const std::string &content)
        {
                std::vector<std::string> mods;
                size_t begin = 0;
                while (begin <= content.size())
                {
                        size_t end = content.find('\n', begin);
                        std::string line = content.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
                        if (!line.empty() && line.back() == '\r')
                                line.pop_back();
                        // buang spasi di ujung
                        size_t first = line.find_first_not_of(" \t");
                        if (first != std::string::npos)
                        {
                                size_t last = line.find_last_not_of(" \t");
                                line = line.substr(first, last - first + 1);
                        }
                        else
                        {
                                line.clear();
                        }
                        if (!line.empty() && line[0] != '#')
                                mods.push_back(line);
                        if (end == std::string::npos)
                                break;
                        begin = end + 1;
                }
                return mods;
        }

        static void callLuaGlobal(lua_State *L, const char *globalName)
        {
                lua_getglobal(L, globalName);
                if (lua_isfunction(L, -1))
                {
                        if (lua_pcall(L, 0, 0, 0) != 0)
                        {
                                const char *err = lua_tostring(L, -1);
                                CCLOG("[Mods] error %s: %s", globalName, err ? err : "<unknown>");
                                lua_pop(L, 1);
                        }
                }
                else
                {
                        lua_pop(L, 1);
                }
        }
} // namespace

void ModRegistry::loadAll()
{
        LuaEngine *engine = LuaEngine::defaultEngine();
        if (!engine || !engine->getLuaStack())
                return;

        lua_State *L = engine->getLuaStack()->getLuaState();
        if (!L)
                return;

        // 1. Register API mod + reset registry
        lua_register(L, "nsRegisterHero", &luaRegisterHero);
        lua_register(L, "nsRegisterMode", &luaRegisterMode);
        initRegistry(L, "__ns_hero_registry");
        initRegistry(L, "__ns_mode_registry");

        // 2. Tambahkan search path mods/
        engine->addSearchPath("mods");
        FileUtils *utils = FileUtils::sharedFileUtils();
        utils->addSearchPath("mods");

        // 3. Baca daftar mod dari mods/list.txt
        std::vector<std::string> mods;
        unsigned long listSize = 0;
        unsigned char *listData = utils->getFileData("mods/list.txt", "rb", &listSize);
        if (listData && listSize > 0)
        {
                mods = parseModList(std::string(reinterpret_cast<const char *>(listData), listSize));
                delete[] listData;
        }

        if (mods.empty())
        {
                CCLOG("[Mods] tidak ada mod terdaftar di mods/list.txt");
                callLuaGlobal(L, "nsOnModsLoaded");
                return;
        }

        // 4. Jalankan init.lua tiap mod
        int loaded = 0;
        for (size_t i = 0; i < mods.size(); i++)
        {
                const std::string &name = mods[i];
                if (name.find("..") != std::string::npos || name.find('/') != std::string::npos)
                {
                        CCLOG("[Mods] nama mod tidak valid: %s", name.c_str());
                        continue;
                }
                const std::string script = "mods/" + name + "/init.lua";
                if (!utils->isFileExist(script))
                {
                        CCLOG("[Mods] mod '%s' tidak punya init.lua, dilewati", name.c_str());
                        continue;
                }
                if (runModScript(engine, script))
                {
                        loaded++;
                        CCLOG("[Mods] mod dimuat: %s", name.c_str());
                }
        }

        CCLOG("[Mods] selesai: %d/%d mod aktif", loaded, (int)mods.size());

        // 5. Beri tahu Lua bahwa semua mod sudah dimuat
        callLuaGlobal(L, "nsOnModsLoaded");
}
