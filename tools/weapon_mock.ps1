# weapon_mock.ps1
# Renders each Doom viewmodel on a mock 800x600 screen, using exactly the placement
# the client dll uses:
#     canvasLeft = ScreenWidth/2 - round(Sx * centerX)      (centerX = 160.5 - minX)
#     canvasTop  = ScreenHeight - 96 - OutH
# so an error in the constants shows up here before the game is restarted.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File weapon_mock.ps1

param(
    [string]$Wad = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [string]$Out = "$PSScriptRoot\weapon_mock.png",
    [double]$ScaleX = 2.5,
    [double]$ScaleY = 3.0,
    [int]$PanelScale = 50,     # percent, for the contact sheet
    [int]$ScreenW = 800,
    [int]$ScreenH = 600,
    [int]$Baseline = 96
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$weapons = @(
    [pscustomobject]@{ Key='pung'; Hl='crowbar -> fist';      Frames=@('PUNGA0','PUNGB0','PUNGC0','PUNGD0');                       Flash=@() }
    [pscustomobject]@{ Key='pisg'; Hl='9mm -> pistol';        Frames=@('PISGA0','PISGB0','PISGC0','PISGD0','PISGE0');               Flash=@('PISFA0') }
    [pscustomobject]@{ Key='shtg'; Hl='shotgun -> shotgun';   Frames=@('SHTGA0','SHTGB0','SHTGC0','SHTGD0');                       Flash=@('SHTFA0','SHTFB0') }
    [pscustomobject]@{ Key='chgg'; Hl='MP5 -> chaingun';      Frames=@('CHGGA0','CHGGB0');                                        Flash=@('CHGFA0','CHGFB0') }
    [pscustomobject]@{ Key='misg'; Hl='RPG -> rocket';        Frames=@('MISGA0','MISGB0');                                        Flash=@('MISFA0','MISFB0','MISFC0','MISFD0') }
    [pscustomobject]@{ Key='plsg'; Hl='crossbow -> plasma';   Frames=@('PLSGA0','PLSGB0');                                        Flash=@('PLSFA0','PLSFB0') }
    [pscustomobject]@{ Key='bfgg'; Hl='gauss -> BFG';         Frames=@('BFGGA0','BFGGB0','BFGGC0');                               Flash=@('BFGFA0','BFGFB0') }
)

# ---- WAD ----
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

function Get-Patch([string]$name) {
    $p = $lump[$name]
    $w = [BitConverter]::ToUInt16($wb, $p)
    $h = [BitConverter]::ToUInt16($wb, $p + 2)
    $l = [BitConverter]::ToInt16($wb, $p + 4)
    $t = [BitConverter]::ToInt16($wb, $p + 6)
    $bm = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $d = $bm.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($d.Stride * $h)
    for ($x = 0; $x -lt $w; $x++) {
        $q = $p + [BitConverter]::ToInt32($wb, $p + 8 + $x * 4)
        while ($true) {
            $td = $wb[$q]; $q++
            if ($td -eq 255) { break }
            $len = $wb[$q]; $q += 2
            for ($i = 0; $i -lt $len; $i++) {
                $idx = $wb[$q + $i]
                $o = ($td + $i) * $d.Stride + $x * 4
                $buf[$o] = $pal[$idx*3+2]; $buf[$o+1] = $pal[$idx*3+1]; $buf[$o+2] = $pal[$idx*3]; $buf[$o+3] = 255
            }
            $q += $len + 1
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $d.Scan0, $buf.Length)
    $bm.UnlockBits($d)
    return [pscustomobject]@{ Bm = $bm; W = $w; H = $h; Left = $l; Top = $t }
}

function Round8([double]$v) {
    $r = [int]([Math]::Round($v / 8.0, [System.MidpointRounding]::AwayFromZero)) * 8
    if ($r -lt 8) { $r = 8 }
    return $r
}

$pw = [int]($ScreenW * $PanelScale / 100)
$ph = [int]($ScreenH * $PanelScale / 100)
$cols = 2
$rows = [Math]::Ceiling($weapons.Count / $cols)
$sheet = New-Object System.Drawing.Bitmap(($pw * $cols), ($ph * $rows), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::FromArgb(255, 10, 10, 12))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font('Consolas', 10)
$br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 220, 140))
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 60, 60, 70))

$i = 0
"{0,-6} {1,-22} {2,10} {3,9} {4,10}  {5}" -f 'key', 'HL weapon', 'screen gx', 'gy', 'canvas', 'output'
foreach ($wp in $weapons) {
    # the canvas must be the union of ALL frames + flashes (same rule as the builder)
    $patches = @{}
    foreach ($n in @($wp.Frames + $wp.Flash)) { $patches[$n] = Get-Patch $n }
    $all = $patches.Values

    $minX = ($all | ForEach-Object { -$_.Left }             | Measure-Object -Minimum).Minimum
    $minY = ($all | ForEach-Object { -$_.Top }              | Measure-Object -Minimum).Minimum
    $maxX = ($all | ForEach-Object { (-$_.Left) + $_.W }    | Measure-Object -Maximum).Maximum
    $maxY = ($all | ForEach-Object { (-$_.Top) + $_.H }     | Measure-Object -Maximum).Maximum
    $cW = $maxX - $minX
    $cH = $maxY - $minY
    $OutW = Round8 ($cW * $ScaleX)
    $OutH = Round8 ($cH * $ScaleY)
    $Sx = $OutW / $cW
    $Sy = $OutH / $cH

    # the client dll: gx = ScreenWidth/2 - (int)(gw * centerX / canvasW + 0.5)
    $gx = [int]($ScreenW / 2) - [int]($OutW * (160.5 - $minX) / $cW + 0.5)
    $gy = ($ScreenH - $Baseline) - $OutH
    if ($gy -lt 0) { $gy = 0 }

    # draw into a full-size panel
    $panel = New-Object System.Drawing.Bitmap($ScreenW, $ScreenH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pg = [System.Drawing.Graphics]::FromImage($panel)
    $pg.Clear([System.Drawing.Color]::FromArgb(255, 40, 44, 48))
    $pg.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 58, 62, 66))), 0, [int]($ScreenH/2), $ScreenW, [int]($ScreenH/2))
    $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $pg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

    # idle frame + first flash = the moment a shot starts
    $draw = @($patches[$wp.Frames[0]])
    if ($wp.Flash.Count -gt 0) { $draw += $patches[$wp.Flash[0]] }
    foreach ($pt in $draw) {
        $ox = $gx + [int][Math]::Round((-($pt.Left) - $minX) * $Sx)
        $oy = $gy + [int][Math]::Round((-($pt.Top)  - $minY) * $Sy)
        $dw = [int][Math]::Max(1, [Math]::Round($pt.W * $Sx))
        $dh = [int][Math]::Max(1, [Math]::Round($pt.H * $Sy))
        $pg.DrawImage($pt.Bm, (New-Object System.Drawing.Rectangle($ox, $oy, $dw, $dh)))
    }
    # screen centre + the 96 px baseline
    $pg.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 90, 90, 90), 1)), [int]($ScreenW/2), 0, [int]($ScreenW/2), $ScreenH)
    $pg.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 120, 60, 60), 1)), 0, ($ScreenH - $Baseline), $ScreenW, ($ScreenH - $Baseline))
    $pg.Dispose()

    $cx = ($i % $cols) * $pw
    $cy = [int]([Math]::Floor($i / $cols)) * $ph
    $g.DrawImage($panel, (New-Object System.Drawing.Rectangle($cx, $cy, $pw, $ph)))
    $g.DrawRectangle($pen, $cx, $cy, $pw - 1, $ph - 1)
    $g.DrawString(("{0}  ({1})" -f $wp.Key, $wp.Hl), $font, $br, ($cx + 4), ($cy + 4))
    $panel.Dispose()

    "{0,-6} {1,-22} {2,10} {3,9} {4,10}  {5}x{6}" -f $wp.Key, $wp.Hl, $gx, $gy, ("{0}x{1}" -f $cW, $cH), $OutW, $OutH
    $i++
}

$g.Dispose()
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
"saved: {0}" -f $Out
