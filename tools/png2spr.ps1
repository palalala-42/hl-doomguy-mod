# png2spr.ps1
# Converts a Doom weapon/PNG (with alpha) into a Half-Life v2 sprite (.spr).
# Palette is taken from PLAYPAL inside the local doom.wad (personal, offline use).
# Transparent pixels (alpha < 128) become index 255 (SPR_INDEXALPHA -> transparent).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File png2spr.ps1 -Src in.png -Out out.spr [-ScaleX 2.5] [-ScaleY 3.0]

param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Out,
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [int]$MaxSize = 256,
    [string]$Wad = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---- 1. Read PLAYPAL (768 bytes) from the Doom WAD ----
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

# ---- 2. Load PNG and compute output size ----
$bm = [System.Drawing.Bitmap]::FromFile($Src)
$sw = $bm.Width; $sh = $bm.Height
# engine/sprgen rules: frame dimensions must be multiples of 8 (sprgen caps at 256; MaxSize raises that)
function Round8([double]$v) {
    $r = [int]([Math]::Round($v / 8.0, [System.MidpointRounding]::AwayFromZero)) * 8
    if ($r -gt $MaxSize) { $r = $MaxSize }
    if ($r -lt 8)   { $r = 8 }
    return $r
}
$ow = Round8 ($sw * $ScaleX)
$oh = Round8 ($sh * $ScaleY)

# nearest palette colour (index 0..254 only, so 255 stays reserved for transparent)
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

# ---- 3. Nearest-neighbour resample + palette index ----
$data = New-Object byte[] ($ow * $oh)
for ($y = 0; $y -lt $oh; $y++) {
    $sy = [int][Math]::Floor($y * $sh / $oh); if ($sy -ge $sh) { $sy = $sh - 1 }
    for ($x = 0; $x -lt $ow; $x++) {
        $sx = [int][Math]::Floor($x * $sw / $ow); if ($sx -ge $sw) { $sx = $sw - 1 }
        $c = $bm.GetPixel($sx, $sy)
        if ($c.A -lt 128) { $data[$y*$ow + $x] = 255 }
        else { $data[$y*$ow + $x] = MapIdx $c.R $c.G $c.B }
    }
}
$bm.Dispose()

# ---- 4. Write the .spr v2 (layout verified against v_/HUD sprites) ----
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([Text.Encoding]::ASCII.GetBytes('IDSP'))
$bw.Write([int]2)                                 # version
$bw.Write([int]2)                                 # type (parallel upright)
$bw.Write([int]3)                                 # texFormat = INDEXALPHA (index 255 transparent)
$bw.Write([single]([Math]::Sqrt($ow*$ow + $oh*$oh) / 2.0))
$bw.Write([int]$ow)
$bw.Write([int]$oh)
$bw.Write([int]1)                                 # numframes
$bw.Write([single]0.0)                            # beamlength
$bw.Write([int]1)                                 # synchtype
$bw.Write([int16]256)                             # paletteSize (only ONE short - see sprgen.c)
$bw.Write($pal)                                   # 768 bytes (starts right after the short)
$bw.Write([int]0)                                 # frame type = SPR_SINGLE
$bw.Write([int](-($ow / 2)))                      # frame origin x  (-(w>>1), like sprgen)
$bw.Write([int]($oh / 2))                         # frame origin y  (   h>>1, like sprgen)
$bw.Write([int]$ow)
$bw.Write([int]$oh)
$bw.Write($data)
$bw.Flush()
[IO.File]::WriteAllBytes($Out, $ms.ToArray())

"wrote {0}  ({1}x{2}, {3} bytes, from {4}x{5})" -f $Out, $ow, $oh, $ms.Length, $sw, $sh
