#!/usr/bin/env bash
# Builds dlls/main.dll (the native seed reader) with clang-cl + lld-link, no MSVC and no C runtime.
# Usage: native/build.sh /path/to/UE4SS.dll   (the UE4SS v3.0.1 the mod runs under; its exports make the import lib)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ue4ss="${1:?usage: build.sh /path/to/UE4SS.dll}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

{
    echo "LIBRARY UE4SS.dll"
    echo "EXPORTS"
    llvm-readobj --coff-exports "$ue4ss" | sed -n 's/^ *Name: //p' |
        grep -E 'CppUserModBase@RC@@|register_function@Lua@LuaMadeSimple@RC@@|\?[gs]et_integer@Lua@LuaMadeSimple@RC@@'
} > "$work/UE4SS.def"
printf 'LIBRARY KERNEL32.dll\nEXPORTS\nReadProcessMemory\nGetProcessHeap\nHeapAlloc\nHeapFree\n' > "$work/kernel32.def"
llvm-dlltool -m i386:x86-64 -d "$work/UE4SS.def" -l "$work/UE4SS.lib"
llvm-dlltool -m i386:x86-64 -d "$work/kernel32.def" -l "$work/kernel32.lib"

clang-cl --target=x86_64-pc-windows-msvc /Brepro /std:c++20 /O2 /GS- /GR- /EHs-c- /Zl /W4 /WX -Wno-unused-parameter \
    /c "$here/seeds.cpp" "/Fo$work/seeds.obj"
lld-link /DLL /NODEFAULTLIB /NOIMPLIB /Brepro /ENTRY:DllMain "/OUT:$here/../dlls/main.dll" "$work/seeds.obj" \
    "$work/UE4SS.lib" "$work/kernel32.lib"
echo "built $here/../dlls/main.dll"
