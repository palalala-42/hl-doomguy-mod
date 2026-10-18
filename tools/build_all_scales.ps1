# build_all_scales.ps1
# Builds the Doom HUD sprite sets for every supported screen scale.
#
# The engine draws HUD sprites 1:1 (there is no scaled sprite draw in the client
# API), so the mod ships one sprite set per scale and the client picks the
# biggest one that fits the screen (see DoomPickScale() in cl_dll/health.cpp).
# A Doom pixel is 6/5 as tall as it is wide, so the x scale is an integer and the
# y scale is always 1.2 * x.  The set name carries the tag 10 * x:
#
#   tag 20   x2.0 / y2.4    fits 640x480       (also smaller 4:3 modes)
#   tag 25   x2.5 / y3.0    fits 800x600       <- the reference, and the one the
#                                                 tools used to build before
#   tag 30   x3.0 / y3.6    fits 1024x768
#   tag 40   x4.0 / y4.8    fits 1280x960 / 1280x720 (widescreen: pillarboxed)
#   tag 50   x5.0 / y6.0    fits 1920x1080 and up
#
# Every set is built by the four builders into a scratch folder and then renamed
# and copied into -OutDir:
#   doomstbar.spr -> dg<TAG>_stbar.spr     doomface.spr  -> dg<TAG>_face.spr
#   doompct.spr   -> dg<TAG>_pct.spr       doomnum.spr   -> dg<TAG>_num.spr
#   dg_shtg_a.spr -> dg<TAG>_shtg_a.spr    (all viewmodels and their flashes)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File build_all_scales.ps1
#   powershell -ExecutionPolicy Bypass -File build_all_scales.ps1 -Tags 25,30
#   powershell -ExecutionPolicy Bypass -File build_all_scales.ps1 -Clean
#
# Pass your own paths if the game is not where the defaults point:
#   -Wad <your iwad>  -Hud <folder with the Doom PNGs>  -OutDir <mod>\sprites

param(
    [string]$Wad    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [string]$Hud    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\hud",
    [string]$OutDir = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites",
    [string]$Tags   = "20,25,30,40,50",
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot

# -Tags accepts "20,25", "20 25" and a real array.  Do not declare it as [int[]]:
# PowerShell joins an array argument with spaces ("20 30") and then coerces that
# string to a single int (2030), silently building a nonsense scale.
$tagList = @()
foreach ($t in ($Tags -split '[,;\s]+')) {
    if ($t -eq '') { continue }
    $n = 0
    if (-not [int]::TryParse($t, [ref]$n)) { throw "-Tags: '$t' is not a number" }
    if ($n -lt 10 -or $n -gt 99)           { throw "-Tags: '$t' is out of range (expect 10..99)" }
    $tagList += $n
}
if ($tagList.Count -eq 0) { throw "-Tags is empty" }

foreach ($p in @($Wad, $Hud)) {
    if (-not (Test-Path $p)) { throw "not found: $p" }
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

if ($Clean) {
    # the untagged names used before the scale sets existed; dg<TAG>_* never
    # matches "dg_*", so current sets are left alone
    Get-ChildItem $OutDir -File | Where-Object {
        $_.Name -in @('doomstbar.spr', 'doompct.spr', 'doomface.spr', 'doomnum.spr') -or $_.Name -like 'dg_*.spr'
    } | ForEach-Object { "clean    : removing $($_.Name)"; Remove-Item $_.FullName -Force }
}

foreach ($tag in $tagList) {

    $sx = $tag / 10.0
    $sy = [math]::Round($sx * 1.2, 4)

    $tmp = Join-Path $env:TEMP "dgspr$tag"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null

    "=== tag $tag : x$sx / y$sy  ->  $OutDir ==="

    $common = @('-ExecutionPolicy', 'Bypass', '-File')
    & powershell @common (Join-Path $tools 'build_stbar_spr.ps1') `
        -Wad $Wad -Hud $Hud -OutDir $tmp -ScaleX $sx -ScaleY $sy -Mock (Join-Path $tmp 'mock.png') | Out-Null
    & powershell @common (Join-Path $tools 'build_face_spr.ps1') `
        -Wad $Wad -Hud $Hud -Out (Join-Path $tmp 'doomface.spr') -ScaleX $sx -ScaleY $sy | Out-Null
    & powershell @common (Join-Path $tools 'build_doomnum_spr.ps1') `
        -Wad $Wad -Hud $Hud -Out (Join-Path $tmp 'doomnum.spr') -ScaleX $sx -ScaleY $sy | Out-Null
    & powershell @common (Join-Path $tools 'doom_weapon_sprites.ps1') `
        -Wad $Wad -OutDir $tmp -ScaleX $sx -ScaleY $sy | Out-Null

    $n = 0
    $bytes = 0
    foreach ($f in (Get-ChildItem $tmp -Filter '*.spr' | Sort-Object Name)) {

        # doomstbar/doompct/doomface/doomnum keep their widget name, the
        # viewmodels are "dg_<key>_<frame>", i.e. just drop the leading "dg_"
        $what = switch -Regex ($f.Name) {
            '^doomstbar\.spr$' { 'stbar' }
            '^doompct\.spr$'   { 'pct'   }
            '^doomface\.spr$'  { 'face'  }
            '^doomnum\.spr$'   { 'num'   }
            default            { $f.Name -replace '^dg_', '' -replace '\.spr$', '' }
        }

        $dest = "dg${tag}_$what.spr"
        Copy-Item $f.FullName (Join-Path $OutDir $dest) -Force
        $n++
        $bytes += $f.Length
    }

    "{0,-11} {1,3} sprites  {2,8:N2} MB" -f "tag $tag", $n, ($bytes / 1MB)
}

"done. total in $OutDir : {0} files, {1:N2} MB" -f `
    (Get-ChildItem $OutDir -Filter 'dg*.spr').Count, `
    (((Get-ChildItem $OutDir -Filter 'dg*.spr') | Measure-Object Length -Sum).Sum / 1MB)
