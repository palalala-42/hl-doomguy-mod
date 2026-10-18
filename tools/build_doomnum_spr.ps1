# build_doomnum_spr.ps1
# Builds ONE multi-frame Half-Life v2 sprite (sprites/doomnum.spr) with the Doom
# status bar digits STTNUM0..STTNUM9, frame N = digit N.
#
# Why a fixed cell and not a union box: Doom draws status bar numbers in 14 px
# cells (STlib_drawNum advances by the width of the '0' patch) and positions each
# digit with the patch offsets from the WAD, so every frame must be the SAME
# 14x16 cell with the digit in its own place, otherwise the digits jump.
#   14 x 16 is the Doom cell  ->  ScaleX 2.5 / ScaleY 3.0 -> 35 x 48 on screen
#
# Source pixels come from the PNGs in dg_mod\hud (same pipeline as the face);
# the WAD is used only for the palette and for the per-digit patch offsets.
#
# Usage: powershell -ExecutionPolicy Bypass -File build_doomnum_spr.ps1 [-ScaleX 2.5] [-ScaleY 3.0]

param(
    [string]$Hud   = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\hud",
    [string]$Out   = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites\doomnum.spr",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [string]$Wad   = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [int]$CellW    = 14,
    [int]$CellH    = 16
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# frame N is digit N
$order = @()
foreach ($d in 0..9) { $order += "STTNUM$d" }

# ---------------- read the WAD (palette + patch offsets) ----------------
$wb  = [IO.File]::ReadAllBytes($Wad)
$num = [BitConverter]::ToInt32($wb, 4)
$dir = [BitConverter]::ToInt32($wb, 8)
$pal = $null; $lumpOf = @{}
for ($i = 0; $i -lt $num; $i++) {
    $e    = $dir + $i * 16
    $pos  = [BitConverter]::ToInt32($wb, $e)
    $name = [Text.Encoding]::ASCII.GetString($wb, $e + 8, 8).Trim([char]0)
    $lumpOf[$name] = $pos
    if ($name -eq 'PLAYPAL') { $pal = [byte[]]$wb[$pos..($pos + 767)] }
}
if (-not $pal) { throw "PLAYPAL not found" }

# ---------------- per-digit cell position ----------------
$frames = @()
foreach ($n in $order) {
    if (-not $lumpOf.ContainsKey($n)) { throw "lump $n not found in WAD" }
    $p = $lumpOf[$n]
    $w = [BitConverter]::ToUInt16($wb, $p)
    $h = [BitConverter]::ToUInt16($wb, $p + 2)
    $l = [BitConverter]::ToInt16($wb, $p + 4)
    $t = [BitConverter]::ToInt16($wb, $p + 6)
    $x0 = -$l; $y0 = -$t
    if ($x0 -lt 0 -or $y0 -lt 0 -or ($x0 + $w) -gt $CellW -or ($y0 + $h) -gt $CellH) {
        throw "$n ($w x $h at $x0,$y0) does not fit in the ${CellW}x${CellH} cell"
    }
    $frames += [pscustomobject]@{ Name=$n; X0=$x0; Y0=$y0; W=$w; H=$h }
}

$ow = [int][Math]::Round($CellW * $ScaleX)
$oh = [int][Math]::Round($CellH * $ScaleY)

# ---------------- palette mapping ----------------
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

# ---------------- render every digit into its own cell ----------------
$frameData = @()
$badOpaque255 = 0
foreach ($f in $frames) {
    $png = New-Object System.Drawing.Bitmap("$Hud\$($f.Name).png")
    $data = New-Object byte[] ($ow * $oh)
    for ($y = 0; $y -lt $oh; $y++) {
        for ($x = 0; $x -lt $ow; $x++) {
            $sx = [int][Math]::Floor($x / $ScaleX) - $f.X0
            $sy = [int][Math]::Floor($y / $ScaleY) - $f.Y0
            if ($sx -lt 0 -or $sy -lt 0 -or $sx -ge $f.W -or $sy -ge $f.H) { $data[$y*$ow+$x] = 255; continue }
            $c = $png.GetPixel($sx, $sy)
            if ($c.A -lt 128) { $data[$y*$ow+$x] = 255 }
            else {
                $idx = MapIdx $c.R $c.G $c.B
                if ($idx -eq 255) { $badOpaque255++ }
                $data[$y*$ow+$x] = $idx
            }
        }
    }
    $png.Dispose()
    $frameData += ,$data
}

# ---------------- write the v2 sprite ----------------
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([Text.Encoding]::ASCII.GetBytes('IDSP'))
$bw.Write([int]2)
$bw.Write([int]2)                                  # type: parallel upright
$bw.Write([int]3)                                  # texFormat: index alpha
$bw.Write([single]([Math]::Sqrt($ow*$ow + $oh*$oh) / 2.0))
$bw.Write([int]$ow)
$bw.Write([int]$oh)
$bw.Write([int]$frames.Count)
$bw.Write([single]0.0)
$bw.Write([int]1)
$bw.Write([int16]256)
$bw.Write($pal)
foreach ($data in $frameData) {
    $bw.Write([int]0)                              # SPR_SINGLE
    $bw.Write([int](-($ow / 2)))
    $bw.Write([int]($oh / 2))
    $bw.Write([int]$ow)
    $bw.Write([int]$oh)
    $bw.Write($data)
}
$bw.Flush()
[IO.File]::WriteAllBytes($Out, $ms.ToArray())

"cell     : $CellW x $CellH -> $ow x $oh (x$Scale), frames=$($frames.Count)"
"output   : $($ms.Length) bytes"
"opaque pixels that mapped to index 255: $badOpaque255"
"wrote    : $Out"
"digits   :"
$i = 0
foreach ($f in $frames) { "{0,3} {1,-9} cell x{2} y{3} {4}x{5}" -f $i, $f.Name, $f.X0, $f.Y0, $f.W, $f.H; $i++ }
