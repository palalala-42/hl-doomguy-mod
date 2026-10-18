# build_stbar_spr.ps1
# Doom status bar (STBAR) for the Half-Life HUD.
#
# Builds, from the PNGs in dg_mod\hud (same pipeline as the face and the digits):
#   sprites/doomstbar.spr   STBAR background        320x32 -> 800x96   (x2.5 / y3.0)
#   sprites/doompct.spr     STTPRCNT percent sign   14x16  ->  35x48
#
# and renders tools/stbar_mock.png: a 800x600 screen with the bar composed exactly
# the way the client draws it (bar + face + health/armor/ammo + percent signs),
# so the layout can be approved before it goes into the game.
#
# Geometry is taken from Doom itself (linuxdoom st_stuff.c / st_lib.c):
#   - ST_Y = 168 : the bar occupies the bottom 32 rows of the 320x200 screen
#   - STlib_drawNum() right-aligns the digits and ENDS at n->x  (x -= w per digit)
#   - STlib_updatePercent() draws "%" AT n->x, i.e. right after the digits
#   - ST_AMMOX 44 / ST_AMMOY 171      ST_HEALTHX 90 / ST_HEALTHY 171
#   - ST_ARMORX 221 / ST_ARMORY 171   ST_FACESX 143 / ST_FACESY 168
#   - tallnum cell = 14x16 (the advance is the width of the '0' patch)
# Screen scale: 800/320 = 2.5 in x, 600/200 = 3.0 in y  (the Doom 4:3 image).
#
# Usage: powershell -ExecutionPolicy Bypass -File build_stbar_spr.ps1

param(
    [string]$Hud    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\hud",
    [string]$OutDir = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\sprites",
    [string]$Wad    = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [string]$Mock   = "",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0
)

if ($Mock -eq "") { $Mock = Join-Path $PSScriptRoot "stbar_mock.png" }

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---------------- WAD: palette + patch offsets ----------------
$wb  = [IO.File]::ReadAllBytes($Wad)
$num = [BitConverter]::ToInt32($wb, 4)
$dir = [BitConverter]::ToInt32($wb, 8)
$ofs = @{}
for ($i = 0; $i -lt $num; $i++) {
    $e = $dir + $i * 16
    $nm = [Text.Encoding]::ASCII.GetString($wb, $e + 8, 8).Trim([char]0)
    $ofs[$nm] = [BitConverter]::ToInt32($wb, $e)
}
if (-not $ofs.ContainsKey('PLAYPAL')) { throw "PLAYPAL not found in $Wad" }
$palOfs = $ofs['PLAYPAL']
$pal    = [byte[]]$wb[$palOfs..($palOfs + 767)]

function PatchInfo([string]$Name) {
    if (-not $ofs.ContainsKey($Name)) { throw "lump $Name not found in $Wad" }
    $p = $ofs[$Name]
    return @{
        W  =  [int][BitConverter]::ToUInt16($wb, $p)
        H  =  [int][BitConverter]::ToUInt16($wb, $p + 2)
        X0 = -[int][BitConverter]::ToInt16($wb, $p + 4)
        Y0 = -[int][BitConverter]::ToInt16($wb, $p + 6)
    }
}

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

# ---------------- WAD fallback (no PNG in dg_mod\hud, e.g. STBAR) ----------------
function DecodeWadInto([string]$Name, [byte[]]$Cell, [int]$CellW, [int]$CellH, [int]$PlaceX, [int]$PlaceY) {
    $pi = PatchInfo $Name
    $p  = $ofs[$Name]
    for ($c = 0; $c -lt $pi.W; $c++) {
        $o = $p + [BitConverter]::ToInt32($wb, $p + 8 + $c * 4)
        while ($true) {
            $top = [int]$wb[$o]
            if ($top -eq 255) { break }
            $len = [int]$wb[$o + 1]
            for ($k = 0; $k -lt $len; $k++) {
                $cx = $PlaceX + $c; $cy = $PlaceY + $top + $k
                if ($cx -ge 0 -and $cy -ge 0 -and $cx -lt $CellW -and $cy -lt $CellH) {
                    $Cell[$cy * $CellW + $cx] = $wb[$o + 3 + $k]
                }
            }
            $o += $len + 4
        }
    }
}

# ---------------- one PNG (or WAD patch) -> Doom-pixel cell -> scaled buffer ----------------
# PlaceX / PlaceY are the patch offsets in CELL space (Doom pixels), ScaleX / ScaleY
# the nearest-neighbour scale of the finished cell.
function Render([string]$Name, [int]$CellW, [int]$CellH, [int]$PlaceX, [int]$PlaceY, [double]$SX, [double]$SY) {
    $pi  = PatchInfo $Name
    $pngPath = Join-Path $Hud "$Name.png"
    $cell = New-Object byte[] ($CellW * $CellH)
    for ($i = 0; $i -lt $cell.Length; $i++) { $cell[$i] = 255 }
    if (Test-Path $pngPath) {
        $png = New-Object System.Drawing.Bitmap($pngPath)
        for ($y = 0; $y -lt $pi.H; $y++) {
            for ($x = 0; $x -lt $pi.W; $x++) {
                $cx = $PlaceX + $x; $cy = $PlaceY + $y
                if ($cx -lt 0 -or $cy -lt 0 -or $cx -ge $CellW -or $cy -ge $CellH) { continue }
                $c = $png.GetPixel($x, $y)
                if ($c.A -lt 128) { continue }
                $cell[$cy * $CellW + $cx] = MapIdx $c.R $c.G $c.B
            }
        }
        $png.Dispose()
    }
    else {
        DecodeWadInto $Name $cell $CellW $CellH $PlaceX $PlaceY
    }
    $ow = [int][Math]::Round($CellW * $SX)
    $oh = [int][Math]::Round($CellH * $SY)
    $d  = New-Object byte[] ($ow * $oh)
    for ($y = 0; $y -lt $oh; $y++) {
        $iy = [int][Math]::Floor($y / $SY); if ($iy -ge $CellH) { $iy = $CellH - 1 }
        for ($x = 0; $x -lt $ow; $x++) {
            $ix = [int][Math]::Floor($x / $SX); if ($ix -ge $CellW) { $ix = $CellW - 1 }
            $d[$y * $ow + $x] = $cell[$iy * $CellW + $ix]
        }
    }
    return @{ W = $ow; H = $oh; D = $d }
}

# ---------------- Half-Life v2 sprite writer ----------------
function WriteSpr([string]$Path, [object[]]$Images, [byte[]]$Pal) {
    $w = $Images[0].W; $h = $Images[0].H
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('IDSP'))
    $bw.Write([int]2)                                  # version
    $bw.Write([int]2)                                  # type: parallel upright
    $bw.Write([int]3)                                  # texFormat: index alpha
    $bw.Write([single]([Math]::Sqrt($w*$w + $h*$h) / 2.0))
    $bw.Write([int]$w)
    $bw.Write([int]$h)
    $bw.Write([int]$Images.Count)
    $bw.Write([single]0.0)
    $bw.Write([int]1)
    $bw.Write([int16]256)
    $bw.Write($Pal)
    foreach ($im in $Images) {
        $bw.Write([int]0)                              # SPR_SINGLE
        $bw.Write([int](-([int]($im.W / 2))))
        $bw.Write([int]([int]($im.H / 2)))
        $bw.Write([int]$im.W)
        $bw.Write([int]$im.H)
        $bw.Write([byte[]]$im.D)
    }
    $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
    return $ms.Length
}

# ===========================================================================
# 1. the two new sprites
# ===========================================================================
$bar = Render 'STBAR'    320 32 0 0 $ScaleX $ScaleY
$pct = Render 'STTPRCNT'  14 16 0 0 $ScaleX $ScaleY

$n1 = WriteSpr (Join-Path $OutDir 'doomstbar.spr') @($bar) $pal
$n2 = WriteSpr (Join-Path $OutDir 'doompct.spr')   @($pct) $pal

# ===========================================================================
# 2. face canvas (needed for the mock; the real sprite is built by
#    build_face_spr.ps1 -ScaleX 2.5 -ScaleY 3.0 with the same union rule)
# ===========================================================================
$faceOrder = New-Object System.Collections.ArrayList
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFST${lvl}0"); [void]$faceOrder.Add("STFST${lvl}1"); [void]$faceOrder.Add("STFST${lvl}2") }
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFOUCH$lvl") }
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFEVL$lvl") }
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFKILL$lvl") }
[void]$faceOrder.Add("STFGOD0")
[void]$faceOrder.Add("STFDEAD0")
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFTL${lvl}0") }
foreach ($lvl in 0..4) { [void]$faceOrder.Add("STFTR${lvl}0") }

$minX = 9999; $minY = 9999; $maxX = -9999; $maxY = -9999
foreach ($n in $faceOrder) {
    $pi = PatchInfo $n
    if ($pi.X0 -lt $minX) { $minX = $pi.X0 }
    if ($pi.Y0 -lt $minY) { $minY = $pi.Y0 }
    if (($pi.X0 + $pi.W) -gt $maxX) { $maxX = $pi.X0 + $pi.W }
    if (($pi.Y0 + $pi.H) -gt $maxY) { $maxY = $pi.Y0 + $pi.H }
}
$unionW = $maxX - $minX
$unionH = $maxY - $minY
$cw = [int]([Math]::Ceiling($unionW / 8.0) * 8)
$ch = [int]([Math]::Ceiling($unionH / 8.0) * 8)
$ox = $minX - [int](($cw - $unionW) / 2)
$oy = $minY - [int](($ch - $unionH) / 2)

# ===========================================================================
# 3. mock of the composed status bar
# ===========================================================================
$SW = 800; $SH = 600
$scr = New-Object int[] ($SW * $SH)
for ($i = 0; $i -lt $scr.Length; $i++) { $scr[$i] = 0x101010 }

function Blit($screen, [int]$W, [int]$H, $img, [int]$X, [int]$Y) {
    for ($ly = 0; $ly -lt $img.H; $ly++) {
        $dy = $Y + $ly; if ($dy -lt 0 -or $dy -ge $H) { continue }
        for ($lx = 0; $lx -lt $img.W; $lx++) {
            $dx = $X + $lx; if ($dx -lt 0 -or $dx -ge $W) { continue }
            $idx = $img.D[$ly * $img.W + $lx]
            if ($idx -eq 255) { continue }
            # NB: cast to [int] first - in PowerShell a Byte operand keeps its type,
            # so ([byte]27 -shl 16) would truncate to 0.
            $rr = [int]$pal[$idx*3]; $gg = [int]$pal[$idx*3+1]; $bb = [int]$pal[$idx*3+2]
            $screen[$dy * $W + $dx] = ($rr -shl 16) -bor ($gg -shl 8) -bor $bb
        }
    }
}

$barX = [int](($SW - $bar.W) / 2)
$barY = $SH - $bar.H
Blit $scr $SW $SH $bar $barX $barY

# bar-relative anchors (Doom coords scaled)
$Y_TALL   = [int][Math]::Round((171 - 168) * $ScaleY)      # 9
$X_AMMO   = [int][Math]::Round( 44 * $ScaleX)              # 110
$X_HEALTH = [int][Math]::Round( 90 * $ScaleX)              # 225
$X_ARMOR  = [int][Math]::Round(221 * $ScaleX)              # 553
$CELLW    = [int][Math]::Round( 14 * $ScaleX)              # 35
$FACE_X   = [int][Math]::Round((143 + $ox) * $ScaleX)      # 360
$FACE_Y   = [int][Math]::Round((168 + $oy) * $ScaleY) - $barY          # 3 (relative to the bar top)

# face frame 0
$pi0 = PatchInfo 'STFST00'
$face0 = Render 'STFST00' $cw $ch ($pi0.X0 - $ox) ($pi0.Y0 - $oy) $ScaleX $ScaleY
Blit $scr $SW $SH $face0 ($barX + $FACE_X) ($barY + $FACE_Y)

# digits: right aligned, cell k from the right at X - CELLW*(k+1)
function DrawDigits($screen, [int]$W, [int]$H, [int]$XRight, [int]$Y, [string]$Text, [int]$Cells) {
    for ($i = 0; $i -lt $Cells; $i++) {
        $k = $Cells - 1 - $i                       # k = 0 is the right-most cell
        $ch2 = $Text[$i]
        if ($ch2 -eq ' ') { continue }
        $d = [int]([string]$ch2)
        $img = Render "STTNUM$d" 14 16 0 0 $ScaleX $ScaleY
        Blit $screen $W $H $img ($XRight - $CELLW * ($k + 1)) $Y
    }
}

DrawDigits $scr $SW $SH $X_AMMO   ($barY + $Y_TALL) ' 50' 3
DrawDigits $scr $SW $SH $X_HEALTH ($barY + $Y_TALL) '100' 3
DrawDigits $scr $SW $SH $X_ARMOR  ($barY + $Y_TALL) '  0' 3
Blit $scr $SW $SH $pct ($barX + $X_HEALTH) ($barY + $Y_TALL)
Blit $scr $SW $SH $pct ($barX + $X_ARMOR)  ($barY + $Y_TALL)

# ---------------- write the mock ----------------
$bmp  = New-Object System.Drawing.Bitmap($SW, $SH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rect = New-Object System.Drawing.Rectangle(0, 0, $SW, $SH)
$bd   = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($bd.Stride * $SH)
for ($y = 0; $y -lt $SH; $y++) {
    for ($x = 0; $x -lt $SW; $x++) {
        $v = $scr[$y * $SW + $x]
        $o = $y * $bd.Stride + $x * 4
        $bytes[$o]   = [byte]($v -band 0xFF)
        $bytes[$o+1] = [byte](($v -shr 8)  -band 0xFF)
        $bytes[$o+2] = [byte](($v -shr 16) -band 0xFF)
        $bytes[$o+3] = 255
    }
}
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $bd.Scan0, $bytes.Length)
$bmp.UnlockBits($bd)
$bmp.Save($Mock, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# ===========================================================================
# 4. report
# ===========================================================================
"bar      : STBAR   320x32 -> $($bar.W)x$($bar.H)  ($n1 bytes)  -> $OutDir\doomstbar.spr"
"percent  : STTPRCNT 14x16 -> $($pct.W)x$($pct.H)  ($n2 bytes)  -> $OutDir\doompct.spr"
"face box : union ${unionW}x${unionH} at ($minX,$minY) -> canvas ${cw}x${ch}, anchor ($ox,$oy)"
"face out : $( [int][Math]::Round($cw*$ScaleX) ) x $( [int][Math]::Round($ch*$ScaleY) ) at 2.5/3.0"
"mock     : $Mock"
""
"layout in Doom coords (bar top = 168, 320x200 screen) -> screen px at 2.5/3.0:"
"  bar       (0,168)                       -> ($barX,$barY) $($bar.W)x$($bar.H)"
"  ammo      right edge 44  y 171          -> x $X_AMMO  y $($barY+$Y_TALL)"
"  health    right edge 90  y 171  % at 90 -> x $X_HEALTH  y $($barY+$Y_TALL)"
"  armor     right edge 221 y 171  % at 221-> x $X_ARMOR  y $($barY+$Y_TALL)"
"  face      draw point (143,168)          -> canvas at ($FACE_X, $FACE_Y) inside the bar"
"  digit cell 14x16                        -> $CELLW x $( [int][Math]::Round(16*$ScaleY) )"
""
"C++ (bar-relative, ScreenWidth/2 centred bar):"
"  #define DOOMBAR_W     $($bar.W)"
"  #define DOOMBAR_H     $($bar.H)"
"  #define DOOMBAR_YAMMO   $X_AMMO       // right edge of the 3 tall digits"
"  #define DOOMBAR_XHEALTH $X_HEALTH"
"  #define DOOMBAR_XARMOR  $X_ARMOR"
"  #define DOOMBAR_YFACE   $FACE_Y"
"  #define DOOMBAR_XFACE   $FACE_X"
"  #define DOOMBAR_YTALL   $Y_TALL"
