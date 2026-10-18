// Agave Finder - native seed reader (UE4SS C++ mod, dlls/main.dll).
//
// Why native: the game keeps each agave plant's "harvests left" (0 = no seeds) in a private map inside its
// HarvestableInstancedMeshComponent - not a reflected property, so Lua cannot read it. This DLL gives the mod's Lua one
// function:
//
//     AgaveSeedsLeft(componentAddress, plantCount) -> left0, left1, ... (one per plant), or nothing
//
// It returns nothing when the memory does not look like the layout below (another game build): the Lua side then shows
// every plant, as before. Reads go through ReadProcessMemory on our own process, so a bad address fails the read
// instead of crashing the game. It only reads; nothing in the game is written.
//
// Layout (Dune Awakening build 25789117, found 2026-10-18 by reading memory while Josh picked and regrew plants):
//   component + 0xE40  TMap<int32 plant, uint64 plantId>    (TSet elements of 24 bytes: key@0, id@8)
//   component + 0xE90  TMap<uint64 plantId, int32 left>     (TSet elements of 24 bytes: id@0, left@8)
// Each TMap starts with its element array {data, num, max} and, 16 bytes in, the first word of its allocation bits.
//
// Built without the C runtime (no CRT; see build.sh), so nothing here depends on UE4SS's runtime version. The UE4SS
// classes below are declared exactly as in UE4SS v3.0.1 (Git f58e8f84) CppUserModBase.hpp / LuaMadeSimple.hpp, so
// the compiler lays out the same virtual table; only the members UE4SS reads have to match in size.

using size_t = decltype(sizeof(0));
using int32 = int;
using int64 = long long;
using uint32 = unsigned int;
using uint64 = unsigned long long;

// ---- the few standard-library types UE4SS's interface names (same MSVC names; only their sizes matter) ----
namespace std {
template <class C> struct char_traits;
template <class T> class allocator;
template <class C, class T = char_traits<C>> class basic_string_view {
  public:
    const C* data_;
    size_t size_;
};
template <class C, class T = char_traits<C>, class A = allocator<C>> class basic_string {
  public:
    union { C inline_[16 / sizeof(C)]; C* heap_; } text_;   // MSVC small-string buffer
    size_t size_;
    size_t capacity_;
};
template <class T, class A = allocator<T>> class vector {
    T* first_; T* last_; T* end_;
};
}  // namespace std

namespace RC {
namespace LuaMadeSimple {
class Lua {
  public:
    using LuaFunction = int (*)(const Lua&);
    __declspec(dllimport) void register_function(const std::basic_string<char>& name, const LuaFunction& function) const;
    __declspec(dllimport) int64 get_integer(int32 force_index = 1) const;
    __declspec(dllimport) void set_integer(int64 number) const;
};
}  // namespace LuaMadeSimple

using StringViewType = std::basic_string_view<wchar_t>;
using StringType = std::basic_string<wchar_t>;
namespace GUI { class GUITab; }
template <class T> class shared_ptr_layout { T* object_; void* control_; };

class CppUserModBase {
  protected:
    std::vector<shared_ptr_layout<GUI::GUITab>> GUITabs;
  public:
    StringType ModName, ModVersion, ModDescription, ModAuthors, ModIntendedSDKVersion;

    __declspec(dllimport) CppUserModBase();
    __declspec(dllimport) virtual ~CppUserModBase();
    __declspec(dllimport) virtual void on_update();
    __declspec(dllimport) virtual void on_unreal_init();
    __declspec(dllimport) virtual void on_ui_init();
    __declspec(dllimport) virtual void on_program_start();
    __declspec(dllimport) virtual void on_lua_start(StringViewType mod_name, LuaMadeSimple::Lua& lua,
        LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, std::vector<LuaMadeSimple::Lua*>& hook_luas);
    __declspec(dllimport) virtual void on_lua_start(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua,
        LuaMadeSimple::Lua& async_lua, std::vector<LuaMadeSimple::Lua*>& hook_luas);
    __declspec(dllimport) virtual void on_lua_stop(StringViewType mod_name, LuaMadeSimple::Lua& lua,
        LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, std::vector<LuaMadeSimple::Lua*>& hook_luas);
    __declspec(dllimport) virtual void on_lua_stop(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua,
        LuaMadeSimple::Lua& async_lua, std::vector<LuaMadeSimple::Lua*>& hook_luas);
    __declspec(dllimport) virtual void on_dll_load(StringViewType dll_name);
    __declspec(dllimport) virtual void render_tab();
    __declspec(dllimport) virtual void on_lua_start(StringViewType mod_name, LuaMadeSimple::Lua& lua,
        LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua);
    __declspec(dllimport) virtual void on_lua_start(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua,
        LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua);
    __declspec(dllimport) virtual void on_lua_stop(StringViewType mod_name, LuaMadeSimple::Lua& lua,
        LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua);
    __declspec(dllimport) virtual void on_lua_stop(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua,
        LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua);
    __declspec(dllimport) virtual void on_cpp_mods_loaded();
};
}  // namespace RC

static_assert(sizeof(RC::CppUserModBase) == 8 + 24 + 5 * 32, "CppUserModBase must match UE4SS's size");

// ---- Windows, declared by hand (no SDK headers) ----
extern "C" {
__declspec(dllimport) int __stdcall ReadProcessMemory(void* process, const void* address, void* buffer, size_t size,
    size_t* bytes_read);
__declspec(dllimport) void* __stdcall GetProcessHeap();
__declspec(dllimport) void* __stdcall HeapAlloc(void* heap, uint32 flags, size_t bytes);
__declspec(dllimport) int __stdcall HeapFree(void* heap, uint32 flags, void* memory);
}

void* operator new(size_t, void* where) noexcept { return where; }
void operator delete(void* memory, size_t) noexcept { HeapFree(GetProcessHeap(), 0, memory); }
void operator delete(void* memory) noexcept { HeapFree(GetProcessHeap(), 0, memory); }

namespace {

constexpr const char LUA_FUNCTION_NAME[] = "AgaveSeedsLeft";
constexpr const wchar_t OUR_LUA_MOD[] = L"AgaveFinder";
constexpr uint64 PLANT_TO_ID_MAP = 0xE40;
constexpr uint64 ID_TO_LEFT_MAP = 0xE90;
constexpr uint64 ALLOCATION_BITS = 0x10;          // offset of the first allocation word inside a map
constexpr int32 ELEMENT_BYTES = 24;
constexpr int32 MOST_PLANTS = 32;                 // one allocation word; spawners hold 8
constexpr int32 MOST_HARVESTS = 100;              // a larger "left" means the layout is not what we expect
void* const OUR_PROCESS = reinterpret_cast<void*>(static_cast<long long>(-1));

bool readMemory(uint64 address, void* into, size_t bytes) {
    size_t got = 0;
    return address != 0 && ReadProcessMemory(OUR_PROCESS, reinterpret_cast<const void*>(address), into, bytes, &got)
        && got == bytes;
}

template <class T> bool readValue(uint64 address, T& into) { return readMemory(address, &into, sizeof(T)); }

// One of the component's two private maps: its element bytes, after checking it holds exactly `plants` live elements.
struct PlantMap {
    unsigned char bytes[MOST_PLANTS * ELEMENT_BYTES];

    bool read(uint64 mapAddress, int32 plants) {
        uint64 elements = 0;
        int32 count = 0;
        uint32 allocated = 0;
        if (!readValue(mapAddress, elements) || !readValue(mapAddress + 8, count)
            || !readValue(mapAddress + ALLOCATION_BITS, allocated)) {
            return false;
        }
        const uint32 everyPlant = plants == MOST_PLANTS ? 0xFFFFFFFFu : ((1u << static_cast<uint32>(plants)) - 1u);
        return count == plants && (allocated & everyPlant) == everyPlant
            && readMemory(elements, bytes, static_cast<size_t>(plants) * ELEMENT_BYTES);
    }

    template <class T> T field(int32 element, int32 offset) const {
        T value;
        __builtin_memcpy(&value, bytes + static_cast<size_t>(element) * ELEMENT_BYTES + offset, sizeof(T));
        return value;
    }
};

// Harvests left for each plant of a component, in plant order. False when the memory is not the expected layout.
bool harvestsLeft(uint64 component, int32 plants, int32* left) {
    PlantMap idOfPlant, leftOfId;
    if (!idOfPlant.read(component + PLANT_TO_ID_MAP, plants) || !leftOfId.read(component + ID_TO_LEFT_MAP, plants)) {
        return false;
    }
    for (int32 plant = 0; plant < plants; ++plant) {
        bool found = false;
        for (int32 a = 0; a < plants && !found; ++a) {
            if (idOfPlant.field<int32>(a, 0) != plant) continue;
            const uint64 id = idOfPlant.field<uint64>(a, 8);
            for (int32 b = 0; b < plants && !found; ++b) {
                if (leftOfId.field<uint64>(b, 0) != id) continue;
                left[plant] = leftOfId.field<int32>(b, 8);
                found = left[plant] >= 0 && left[plant] <= MOST_HARVESTS;
            }
            if (!found) return false;
        }
        if (!found) return false;
    }
    return true;
}

// Lua: AgaveSeedsLeft(componentAddress, plantCount) -> one integer per plant, or nothing.
int luaHarvestsLeft(const RC::LuaMadeSimple::Lua& lua) {
    const uint64 component = static_cast<uint64>(lua.get_integer(1));
    const int64 plants = lua.get_integer(1);
    int32 left[MOST_PLANTS];
    if (plants < 1 || plants > MOST_PLANTS || !harvestsLeft(component, static_cast<int32>(plants), left)) return 0;
    for (int32 plant = 0; plant < plants; ++plant) lua.set_integer(left[plant]);
    return static_cast<int>(plants);
}

bool sameText(const RC::StringViewType& a, const wchar_t* b) {
    size_t i = 0;
    for (; i < a.size_; ++i) {
        if (b[i] == L'\0' || a.data_[i] != b[i]) return false;
    }
    return b[i] == L'\0';
}

// A std::string holding a short name, laid out the way MSVC does (text inside its small-string buffer).
template <size_t N> std::basic_string<char> shortString(const char (&text)[N]) {
    static_assert(N <= 16, "the name must fit MSVC's small-string buffer (15 characters)");
    std::basic_string<char> out{};
    for (size_t i = 0; i < N; ++i) out.text_.inline_[i] = text[i];
    out.size_ = N - 1;
    out.capacity_ = 15;
    return out;
}

class SeedReaderMod : public RC::CppUserModBase {
  public:
    // Only our own Lua mod gets the function.
    void on_lua_start(RC::StringViewType mod_name, RC::LuaMadeSimple::Lua& lua, RC::LuaMadeSimple::Lua&,
        RC::LuaMadeSimple::Lua&, RC::LuaMadeSimple::Lua*) override {
        if (!sameText(mod_name, OUR_LUA_MOD)) return;
        const std::basic_string<char> name = shortString(LUA_FUNCTION_NAME);
        const RC::LuaMadeSimple::Lua::LuaFunction function = &luaHarvestsLeft;
        lua.register_function(name, function);
    }
};

}  // namespace

extern "C" {
__declspec(dllexport) RC::CppUserModBase* start_mod() {
    void* memory = HeapAlloc(GetProcessHeap(), 0, sizeof(SeedReaderMod));
    return memory ? new (memory) SeedReaderMod() : nullptr;
}

__declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }

int __stdcall DllMain(void*, uint32, void*) { return 1; }
}
