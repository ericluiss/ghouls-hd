#!/usr/bin/env python
# Compila a GDExtension "libretro_host" (frontend libretro para Godot).
# Requer o godot-cpp em deps/godot-cpp (veja scripts/setup.sh ou scripts/setup.ps1).

env = SConscript("deps/godot-cpp/SConstruct")

env.Append(CPPPATH=["extension/src", "extension/include"])
if env["platform"] in ("linux", "macos"):
    env.Append(LIBS=["dl"])

sources = Glob("extension/src/*.cpp")
target = "game/addons/libretro_host/bin/liblibretro_host{}{}".format(env["suffix"], env["SHLIBSUFFIX"])
library = env.SharedLibrary(target, source=sources)

Default(library)
