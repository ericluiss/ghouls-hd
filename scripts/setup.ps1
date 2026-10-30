# Prepara o projeto no Windows:
#   1. baixa o godot-cpp e compila a GDExtension libretro_host
#   2. baixa o core Genesis Plus GX Wide (é ele que desenha o cenário em 16:9)
# Requisitos: Git, Python 3 e o "Visual Studio Build Tools" com a carga "Desenvolvimento para desktop com C++".
# Uso (num PowerShell na pasta do projeto):  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$GodotCppTag = "godot-4.3-stable"
New-Item -ItemType Directory -Force -Path (Join-Path $Root "deps"), (Join-Path $Root "game\cores") | Out-Null

$GodotCpp = Join-Path $Root "deps\godot-cpp"
if (-not (Test-Path $GodotCpp)) {
    git clone --depth 1 -b $GodotCppTag https://github.com/godotengine/godot-cpp $GodotCpp
}

py -m pip install --user scons
Push-Location $Root
py -m SCons platform=windows target=template_debug -j $env:NUMBER_OF_PROCESSORS
py -m SCons platform=windows target=template_release -j $env:NUMBER_OF_PROCESSORS
Pop-Location

$CoreZip = Join-Path $Root "deps\core.zip"
Invoke-WebRequest -Uri "https://buildbot.libretro.com/nightly/windows/x86_64/latest/genesis_plus_gx_wide_libretro.dll.zip" -OutFile $CoreZip
Expand-Archive -Force -Path $CoreZip -DestinationPath (Join-Path $Root "game\cores")

Write-Host ""
Write-Host "Pronto. Coloque a ROM em game\roms\ e abra game\project.godot no Godot 4.3 ou mais novo."
