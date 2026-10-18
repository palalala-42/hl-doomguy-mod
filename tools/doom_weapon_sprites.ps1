# doom_weapon_sprites.ps1
# Builds the Doom viewmodel sprites for every weapon mapped in the mod, straight
# from doom.wad (no external PNG extraction needed).
#
# Rules (same as the verified shotgun pipeline in doom_gun_sprites.ps1):
#   * each weapon owns ONE canvas = the union of all its frames (patch left/top),
#     so no frame ever jumps;
#   * frame dimensions are multiples of 8; the palette comes from PLAYPAL;
#   * every pixel is remapped into palette indices 0..254, index 255 = transparent.
#
# Output names: dg_<key>_<a..e>.spr (base frames, 'a' = idle) and
#               dg_<key>_f<a..d>.spr (muzzle flash frames).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File doom_weapon_sprites.ps1

param(
    [string]$Wad    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [string]$OutDir = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [int]$MaxSize   = 4096
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# key        = sprite name fragment
# first frame is the idle frame, flash frames are drawn on top of a base frame
$weapons = @(
    [pscustomobject]@{ Key='pung'; Frames=@('PUNGA0','PUNGB0','PUNGC0','PUNGD0');                   Flash=@() }
    [pscustomobject]@{ Key='pisg'; Frames=@('PISGA0','PISGB0','PISGC0','PISGD0','PISGE0');          Flash=@('PISFA0') }
    [pscustomobject]@{ Key='shtg'; Frames=@('SHTGA0','SHTGB0','SHTGC0','SHTGD0');                   Flash=@('SHTFA0','SHTFB0') }
    [pscustomobject]@{ Key='chgg'; Frames=@('CHGGA0','CHGGB0');                                     Flash=@('CHGFA0','CHGFB0') }
    [pscustomobject]@{ Key='misg'; Frames=@('MISGA0','MISGB0');                                     Flash=@('MISFA0','MISFB0','MISFC0','MISFD0') }
    [pscustomobject]@{ Key='plsg'; Frames=@('PLSGA0','PLSGB0');                                     Flash=@('PLSFA0','PLSFB0') }
    [pscustomobject]@{ Key='bfgg'; Frames=@('BFGGA0','BFGGB0','BFGGC0');                            Flash=@('BFGFA0','BFGFB0') }
)

# ---- 1. WAD: lump table + PLAYPAL ----
$wb  = [IO.File]::ReadAllBytes($Wad)
$num = [BitConverter]::ToInt32($wb, 4)
$dir = [BitConverter]::ToInt32($wb, 8)
$lump = @{}
$pal  = $null
for ($i = 0; $i -lt $num; $i++) {
    $e = $dir + $i * 16
    $p = [BitConverter]::ToInt32($wb, $e)
    $n = [Text.Encoding]::ASCII.GetString($wb, $e + 8, 8).Trim([char]0)
    $lump[$n] = $p
    if ($n -eq 'PLAYPAL') { $pal = [byte[]]$wb[$p..($p + 767)] }
}
if (-not $pal) { throw "PLAYPAL not found in $Wad" }

# ---- 2. Doom patch (column/post) decoder -> 32bpp ARGB bitmap ----
function Get-Patch([string]$name) {
    if (-not $lump.ContainsKey($name)) { throw "lump $name not found in $Wad" }
    $p = $lump[$name]
    $w = [BitConverter]::ToUInt16($wb, $p)
    $h = [BitConverter]::ToUInt16($wb, $p + 2)
    $l = [BitConverter]::ToInt16($wb, $p + 4)
    $t = [BitConverter]::ToInt16($wb, $p + 6)

    $bm   = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $d    = $bm.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf  = New-Object byte[] ($d.Stride * $h)          # zero = transparent

    for ($x = 0; $x -lt $w; $x++) {
        $q = $p + [BitConverter]::ToInt32($wb, $p + 8 + $x * 4)
        while ($true) {
            $td = $wb[$q]; $q++
            if ($td -eq 255) { break }
            $len = $wb[$q]; $q += 2                     # length + unused pad
            for ($i = 0; $i -lt $len; $i++) {
                $idx = $wb[$q + $i]
                $o = ($td + $i) * $d.Stride + $x * 4
                $buf[$o]     = $pal[$idx * 3 + 2]
                $buf[$o + 1] = $pal[$idx * 3 + 1]
                $buf[$o + 2] = $pal[$idx * 3]
                $buf[$o + 3] = 255
            }
            $q += $len + 1
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $d.Scan0, $buf.Length)
    $bm.UnlockBits($d)
    return [pscustomobject]@{ Bm = $bm; W = $w; H = $h; Left = $l; Top = $t }
}

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

# canvas pixels -> palette indices (fast, LockBits)
function Get-Indexed([System.Drawing.Bitmap]$bm) {
    $w = $bm.Width; $h = $bm.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $d = $bm.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($d.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
    $bm.UnlockBits($d)
    $out = New-Object byte[] ($w * $h)
    $o255 = 0
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $d.Stride
        for ($x = 0; $x -lt $w; $x++) {
            $i = $row + $x * 4
            if ($buf[$i + 3] -lt 128) { $out[$y*$w + $x] = 255 }
            else {
                $idx = MapIdx $buf[$i + 2] $buf[$i + 1] $buf[$i]
                if ($idx -eq 255) { $o255++ }
                $out[$y*$w + $x] = $idx
            }
        }
    }
    return [pscustomobject]@{ Data = $out; Opaque255 = $o255 }
}

function Round8([double]$v, [int]$max) {
    $r = [int]([Math]::Round($v / 8.0, [System.MidpointRounding]::AwayFromZero)) * 8
    if ($r -gt $max) { $r = $max }
    if ($r -lt 8)    { $r = 8 }
    return $r
}

# ---- 4. per weapon: canvas, then one .spr per frame ----
$total255 = 0
"{0,-5} {1,10} {2,10} {3,9} {4,9}   {5}" -f 'key', 'canvas', 'output', 'minX', 'minY', 'C++ constants (CENTER_X, CANVAS_W, CANVAS_H)'
foreach ($wp in $weapons) {
    $info = @()
    foreach ($n in @($wp.Frames + $wp.Flash)) {
        $pt = Get-Patch $n
        $info += [pscustomobject]@{ Name = $n; Pt = $pt; X = (-$pt.Left); Y = (-$pt.Top) }
    }

    $minX = ($info | ForEach-Object { $_.X }              | Measure-Object -Minimum).Minimum
    $minY = ($info | ForEach-Object { $_.Y }              | Measure-Object -Minimum).Minimum
    $maxX = ($info | ForEach-Object { $_.X + $_.Pt.W }    | Measure-Object -Maximum).Maximum
    $maxY = ($info | ForEach-Object { $_.Y + $_.Pt.H }    | Measure-Object -Maximum).Maximum
    $cW = $maxX - $minX
    $cH = $maxY - $minY

    $OutW = Round8 ($cW * $ScaleX) $MaxSize
    $OutH = Round8 ($cH * $ScaleY) $MaxSize
    $Sx = $OutW / $cW
    $Sy = $OutH / $cH

    foreach ($it in $info) {
        $canvas = New-Object System.Drawing.Bitmap($OutW, $OutH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($canvas)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.CompositingMode   = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $ox = [int][Math]::Round(($it.X - $minX) * $Sx)
        $oy = [int][Math]::Round(($it.Y - $minY) * $Sy)
        $dw = [int][Math]::Max(1, [Math]::Round($it.Pt.W * $Sx))
        $dh = [int][Math]::Max(1, [Math]::Round($it.Pt.H * $Sy))
        $g.DrawImage($it.Pt.Bm, (New-Object System.Drawing.Rectangle($ox, $oy, $dw, $dh)))
        $g.Dispose()

        $res = Get-Indexed $canvas
        $canvas.Dispose()
        $total255 += $res.Opaque255

        $letter = $it.Name.Substring(4, 1).ToLower()
        $isFlash = $it.Name.Substring(3, 1) -eq 'F'
        $outName = if ($isFlash) { "dg_{0}_f{1}.spr" -f $wp.Key, $letter } else { "dg_{0}_{1}.spr" -f $wp.Key, $letter }
        $bytes = Write-Spr (Join-Path $OutDir $outName) $OutW $OutH $res.Data
        "    {0,-8} -> {1,-18} off=({2},{3}) {4}x{5} bytes={6} opaque@255={7}" -f $it.Name, $outName, $ox, $oy, $dw, $dh, $bytes, $res.Opaque255
        $it.Pt.Bm.Dispose()
    }

    "{0,-5} {1,10} {2,10} {3,9} {4,9}   CENTER_X={5}  CANVAS_W={6}  CANVAS_H={7}" -f `
        $wp.Key, ("{0}x{1}" -f $cW, $cH), ("{0}x{1}" -f $OutW, $OutH), $minX, $minY, (160.5 - $minX), $cW, $cH
}

"total opaque pixels mapped to palette index 255 (must be 0): {0}" -f $total255
