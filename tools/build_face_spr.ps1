# build_face_spr.ps1
# Builds ONE multi-frame Half-Life v2 sprite (sprites/doomface.spr) from the Doom
# face PNGs in dg_mod\hud, all composited onto a single canvas so the head never
# jumps.  Frame order (42 frames):
#   0- 2  STFST00/01/02   gaze, health >=80          (three gaze directions)
#   3- 5  STFST10/11/12   gaze, health 60..79
#   6- 8  STFST20/21/22   gaze, health 40..59
#   9-11  STFST30/31/32   gaze, health 20..39
#  12-14  STFST40/41/42   gaze, health 0..19
#  15-19  STFOUCH0..4     grimace after a hard hit (>20 at once)
#  20-24  STFEVL0..4      evil grin after picking up a weapon
#  25-29  STFKILL0..4     rampage while the attack button is held
#  30     STFGOD0         god mode
#  31     STFDEAD0        dead
#  32-36  STFTL00/10/20/30/40  turned left
#  37-41  STFTR00/10/20/30/40  turned right
#
# Usage: powershell -ExecutionPolicy Bypass -File build_face_spr.ps1 [-ScaleX 2.5] [-ScaleY 3.0]
#
# ScaleX / ScaleY match Doom's 320x200 screen on 800x600 (2.5 in x, 3.0 in y),
# which is what the status bar is laid out with, so the face lines up with it.

param(
    [string]$Hud  = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\hud",
    [string]$Out  = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites\doomface.spr",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [string]$Wad  = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---------------- frame order ----------------
$order = New-Object System.Collections.ArrayList
foreach ($lvl in 0..4) { [void]$order.Add("STFST${lvl}0"); [void]$order.Add("STFST${lvl}1"); [void]$order.Add("STFST${lvl}2") }
foreach ($lvl in 0..4) { [void]$order.Add("STFOUCH$lvl") }
foreach ($lvl in 0..4) { [void]$order.Add("STFEVL$lvl") }
foreach ($lvl in 0..4) { [void]$order.Add("STFKILL$lvl") }
[void]$order.Add("STFGOD0")
[void]$order.Add("STFDEAD0")
foreach ($lvl in 0..4) { [void]$order.Add("STFTL${lvl}0") }
foreach ($lvl in 0..4) { [void]$order.Add("STFTR${lvl}0") }

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

# ---------------- per-frame header info ----------------
$frames = @()
$minX = 9999; $minY = 9999; $maxX = -9999; $maxY = -9999
foreach ($n in $order) {
    if (-not $lumpOf.ContainsKey($n)) { throw "lump $n not found in WAD" }
    $p  = $lumpOf[$n]
    $w  = [BitConverter]::ToUInt16($wb, $p)
    $h  = [BitConverter]::ToUInt16($wb, $p + 2)
    $l  = [BitConverter]::ToInt16($wb, $p + 4)
    $t  = [BitConverter]::ToInt16($wb, $p + 6)
    $x0 = -$l; $y0 = -$t
    if ($x0 -lt $minX) { $minX = $x0 }; if ($y0 -lt $minY) { $minY = $y0 }
    if (($x0 + $w) -gt $maxX) { $maxX = $x0 + $w }
    if (($y0 + $h) -gt $maxY) { $maxY = $y0 + $h }
    $frames += [pscustomobject]@{ Name=$n; X0=$x0; Y0=$y0; W=$w; H=$h }
}

# ---------------- canvas: multiples of 8, union centred ----------------
$unionW = $maxX - $minX
$unionH = $maxY - $minY
$cw = [int]([Math]::Ceiling($unionW / 8.0) * 8)
$ch = [int]([Math]::Ceiling($unionH / 8.0) * 8)
$ox = $minX - [int](($cw - $unionW) / 2)
$oy = $minY - [int](($ch - $unionH) / 2)

$ow = [int][Math]::Round($cw * $ScaleX)
$oh = [int][Math]::Round($ch * $ScaleY)

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

# ---------------- render every frame ----------------
$frameData = @()
$badOpaque255 = 0
foreach ($f in $frames) {
    $png = New-Object System.Drawing.Bitmap("$Hud\$($f.Name).png")
    $cx0 = $f.X0 - $ox
    $cy0 = $f.Y0 - $oy
    $data = New-Object byte[] ($ow * $oh)
    for ($y = 0; $y -lt $oh; $y++) {
        for ($x = 0; $x -lt $ow; $x++) {
            $sx = [int][Math]::Floor($x / $ScaleX) - $cx0
            $sy = [int][Math]::Floor($y / $ScaleY) - $cy0
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

"canvas   : union $($unionW)x$($unionH) at ($minX,$minY) -> $($cw)x$($ch), origin ($ox,$oy)"
"output   : $ow x $oh  (x$Scale), frames=$($frames.Count), $($ms.Length) bytes"
"opaque pixels that mapped to index 255: $badOpaque255"
"wrote    : $Out"
"frame list:"
$i = 0
foreach ($f in $frames) { "{0,3} {1,-9} x{2} y{3} {4}x{5}" -f $i, $f.Name, ($f.X0-$ox), ($f.Y0-$oy), $f.W, $f.H; $i++ }
