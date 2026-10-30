#!/usr/bin/env bash
# Prepara o projeto no Linux/macOS:
#   1. baixa o godot-cpp e compila a GDExtension libretro_host
#   2. baixa o core Genesis Plus GX Wide (ou compila com --build-core)
# Requisitos: git, python3, um compilador C++ (gcc/clang), curl e unzip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_CPP_TAG="godot-4.3-stable"
BUILD_CORE=0
[[ "${1:-}" == "--build-core" ]] && BUILD_CORE=1

case "$(uname -s)" in
	Darwin) PLATFORM=macos; CORE_EXT=dylib
		[[ "$(uname -m)" == "arm64" ]] && CORE_URL_DIR=apple/osx/arm64 || CORE_URL_DIR=apple/osx/x86_64 ;;
	*) PLATFORM=linux; CORE_EXT=so; CORE_URL_DIR=linux/x86_64 ;;
esac
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

mkdir -p "$ROOT/deps" "$ROOT/game/cores"

if [[ ! -d "$ROOT/deps/godot-cpp" ]]; then
	git clone --depth 1 -b "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$ROOT/deps/godot-cpp"
fi
command -v scons >/dev/null || python3 -m pip install --user scons
SCONS="$(command -v scons || echo "python3 -m SCons")"

cd "$ROOT"
$SCONS platform="$PLATFORM" target=template_debug -j"$JOBS"
$SCONS platform="$PLATFORM" target=template_release -j"$JOBS"

CORE_FILE="genesis_plus_gx_wide_libretro.$CORE_EXT"
if [[ $BUILD_CORE -eq 1 ]]; then
	[[ -d "$ROOT/deps/Genesis-Plus-GX-Wide" ]] || git clone --depth 1 https://github.com/libretro/Genesis-Plus-GX-Wide "$ROOT/deps/Genesis-Plus-GX-Wide"
	make -C "$ROOT/deps/Genesis-Plus-GX-Wide" -f Makefile.libretro -j"$JOBS"
	cp "$ROOT/deps/Genesis-Plus-GX-Wide/$CORE_FILE" "$ROOT/game/cores/"
else
	curl -fL -o "$ROOT/deps/core.zip" "https://buildbot.libretro.com/nightly/$CORE_URL_DIR/latest/$CORE_FILE.zip"
	unzip -o "$ROOT/deps/core.zip" -d "$ROOT/game/cores"
fi

echo
echo "Pronto. Coloque a ROM em game/roms/ e abra game/project.godot no Godot 4.3 ou mais novo."
