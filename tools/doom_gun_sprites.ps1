# doom_gun_sprites.ps1
# Converts the Doom shotgun frames (idle/fire/flash) into Half-Life v2 sprites,
# all composited onto ONE common canvas so they share a single anchor point
# (no jumping between frames).  Offsets come from the Doom WAD patches.
#
# Rules: frame dims multiples of 8; palette from doom.wad PLAYPAL; alpha<128 -> index 255.
# The canvas may exceed 256 on purpose (option "b"): the engine loads it fine.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File doom_gun_sprites.ps1
#   powershell -ExecutionPolicy Bypass -File doom_gun_sprites.ps1 -ScaleX 2.5 -ScaleY 3.0

param(
    [string]$Hud    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\hud",
    [string]$OutDir = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites",
    [string]$Wad    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [int]$MaxSize   = 4096
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---- 1. PLAYPAL from the WAD ----
$wb  = [IO.File]::ReadAllBytes($Wad)
$num = [BitConverter]::ToInt32($wb, 4)
$dir = [BitConverter]::ToInt32($wb, 8)
$pal = $null
for ($i = 0; $i -lt $num; $i++) {
    $e    = $dir + $i * 16
    $pos  = [BitConverter]::ToInt32($wb, $e)
    $name = [Text.Encoding]::ASCII.GetString($wb, $e + 8, 8).Trim([char]0)
    if ($name -eq 'PLAYPAL') { $pal = [byte[]]$wb[$pos..($pos + 767)]; break }
}
if (-not $pal) { throw "PLAYPAL not found in $Wad" }

# ---- 2. Frame table: PNG file, and Doom patch leftoffset/topoffset from the WAD ----
$frames = @(
    [pscustomobject]@{ Out='shtgidle.spr'; Png='SHTGA0.png'; Left=-121; Top=-108 },
    [pscustomobject]@{ Out='shtgb.spr';    Png='SHTGB0.png'; Left= -43; Top= -47 },
    [pscustomobject]@{ Out='shtgc.spr';    Png='SHTGC0.png'; Left= -30; Top= -17 },
    [pscustomobject]@{ Out='shtgd.spr';    Png='SHTGD0.png'; Left= -29; Top= -37 },
    [pscustomobject]@{ Out='shtfa.spr';    Png='SHTFA0.png'; Left=-141; Top= -95 },
    [pscustomobject]@{ Out='shtfb.spr';    Png='SHTFB0.png'; Left=-136; Top= -86 }
)

# psprite-space placement: x = -left, y = -top (so a shared anchor lines all frames up)
$info = @()
foreach ($f in $frames) {
    $bm = [System.Drawing.Bitmap]::FromFile((Join-Path $Hud $f.Png))
    $info += [pscustomobject]@{ f=$f; bm=$bm; x=(-$f.Left); y=(-$f.Top); w=$bm.Width; h=$bm.Height }
}

$minX = ($info | ForEach-Object { $_.x }             | Measure-Object -Minimum).Minimum
$minY = ($info | ForEach-Object { $_.y }             | Measure-Object -Minimum).Minimum
$maxX = ($info | ForEach-Object { $_.x + $_.w }      | Measure-Object -Maximum).Maximum
$maxY = ($info | ForEach-Object { $_.y + $_.h }      | Measure-Object -Maximum).Maximum
$cW = $maxX - $minX
$cH = $maxY - $minY

function Round8([double]$v, [int]$max) {
    $r = [int]([Math]::Round($v / 8.0, [System.MidpointRounding]::AwayFromZero)) * 8
    if ($r -gt $max) { $r = $max }
    if ($r -lt 8)    { $r = 8 }
    return $r
}
$OutW = Round8 ($cW * $ScaleX) $MaxSize
$OutH = Round8 ($cH * $ScaleY) $MaxSize
$Sx = $OutW / $cW
$Sy = $OutH / $cH

"canvas psprite = {0}x{1}  ->  output {2}x{3}  (scale {4:N3}x{5:N3})" -f $cW, $cH, $OutW, $OutH, $Sx, $Sy

# ---- 3. palette mapper (index 0..254 only; 255 reserved for transparent) ----
$cache = @{}
function MapIdx([int]$r, [int]$g, [int]$b) {
    $key = ($r -shl 16) -bor ($g -shl 8) -bor $b
    if ($cache.ContainsKey($key)) { return $cache[$key] }
    $best = 0; $bd = [int]::MaxValue
    for ($p = 0; $p -lt 255; $p++) {
        $dr = $pal[$p*3] - $r; $dg = $pal[$p*3+1] - $g; $db = $pal[$p*3+2] - $b
        $d = $dr*$dr + $dg*$dg + $db*$db
        if ($d -lt $bd) { $bd = $d; $best = $p; if ($d -eq 0) { break } }
    }
    $cache[$key] = [byte]$best
    return [byte]$best
}

function Write-Spr([string]$path, [int]$ow, [int]$oh, [byte[]]$data) {
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('IDSP'))
    $bw.Write([int]2)
    $bw.Write([int]2)
    $bw.Write([int]3)
    $bw.Write([single]([Math]::Sqrt($ow*$ow + $oh*$oh) / 2.0))
    $bw.Write([int]$ow)
    $bw.Write([int]$oh)
    $bw.Write([int]1)
    $bw.Write([single]0.0)
    $bw.Write([int]1)
    $bw.Write([int16]256)
    $bw.Write($pal)
    $bw.Write([int]0)
    $bw.Write([int](-($ow / 2)))
    $bw.Write([int]($oh / 2))
    $bw.Write([int]$ow)
    $bw.Write([int]$oh)
    $bw.Write($data)
    $bw.Flush()
    [IO.File]::WriteAllBytes($path, $ms.ToArray())
    return $ms.Length
}

# ---- 4. composite each frame onto the shared canvas and write the .spr ----
$totalOpaque255 = 0
foreach ($it in $info) {
    $canvas = New-Object System.Drawing.Bitmap($OutW, $OutH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.CompositingMode   = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $ox = [int][Math]::Round(($it.x - $minX) * $Sx)
    $oy = [int][Math]::Round(($it.y - $minY) * $Sy)
    $dw = [int][Math]::Max(1, [Math]::Round($it.w * $Sx))
    $dh = [int][Math]::Max(1, [Math]::Round($it.h * $Sy))
    $rect = New-Object System.Drawing.Rectangle($ox, $oy, $dw, $dh)
    $g.DrawImage($it.bm, $rect)
    $g.Dispose()

    $data  = New-Object byte[] ($OutW * $OutH)
    $op255 = 0
    for ($y = 0; $y -lt $OutH; $y++) {
        for ($x = 0; $x -lt $OutW; $x++) {
            $c = $canvas.GetPixel($x, $y)
            if ($c.A -lt 128) { $data[$y*$OutW + $x] = 255 }
            else {
                $idx = MapIdx $c.R $c.G $c.B
                if ($idx -eq 255) { $op255++ }
                $data[$y*$OutW + $x] = $idx
            }
        }
    }
    $canvas.Dispose()
    $totalOpaque255 += $op255

    $bytes = Write-Spr (Join-Path $OutDir $it.f.Out) $OutW $OutH $data
    "{0,-12} -> {1,-14} frame off=({2},{3}) {4}x{5}  bytes={6}  opaque@palette255={7}" -f $it.f.Png, $it.f.Out, $ox, $oy, $dw, $dh, $bytes, $op255
    $it.bm.Dispose()
}

"total opaque pixels mapped to palette index 255 (must be 0): {0}" -f $totalOpaque255
