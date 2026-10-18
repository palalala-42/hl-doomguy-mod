# weapon_preview.ps1
# Decodes the Doom weapon patches straight out of doom.wad and renders ONE preview
# sheet: one row per weapon, one cell per frame (plus a cell per muzzle flash
# composited over the idle frame, i.e. exactly how the game will draw it).
#
# Every weapon gets its own union canvas built from the patch left/top offsets, the
# same rule tools/doom_gun_sprites.ps1 uses, so the numbers printed here are the
# numbers the .spr builder will need.
#
# All cells share one absolute scale and one anchor (the psprite origin, drawn as a
# small red cross), so relative sizes and the alignment of the frames are truthful.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File weapon_preview.ps1
#   powershell -ExecutionPolicy Bypass -File weapon_preview.ps1 -Scale 2

param(
    [string]$Wad = "D:\SteamLibrary\steamapps\common\Half-Life\dg_mod\doom.wad",
    [string]$Out = "$PSScriptRoot\weapon_preview.png",
    [double]$Scale = 1.5
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- weapons ----
# Frames are drawn in order; Flash frames are drawn on top of the FIRST frame.
$weapons = @(
    [pscustomobject]@{ Key='PUNG'; Hl='crowbar (ближний бой)';            Frames=@('PUNGA0','PUNGB0','PUNGC0','PUNGD0'); Flash=@() }
    [pscustomobject]@{ Key='PISG'; Hl='9mm пистолет';                     Frames=@('PISGA0','PISGB0','PISGC0','PISGD0','PISGE0'); Flash=@('PISFA0') }
    [pscustomobject]@{ Key='SHTG'; Hl='дробовик (уже сделан)';            Frames=@('SHTGA0','SHTGB0','SHTGC0','SHTGD0'); Flash=@('SHTFA0','SHTFB0') }
    [pscustomobject]@{ Key='CHGG'; Hl='MP5 / пулемёт';                    Frames=@('CHGGA0','CHGGB0'); Flash=@('CHGFA0','CHGFB0') }
    [pscustomobject]@{ Key='MISG'; Hl='RPG / ракетница';                  Frames=@('MISGA0','MISGB0'); Flash=@('MISFA0','MISFB0','MISFC0','MISFD0') }
    [pscustomobject]@{ Key='PLSG'; Hl='egon / плазма';                    Frames=@('PLSGA0','PLSGB0'); Flash=@('PLSFA0','PLSFB0') }
    [pscustomobject]@{ Key='BFGG'; Hl='gauss / BFG';                      Frames=@('BFGGA0','BFGGB0','BFGGC0'); Flash=@('BFGFA0','BFGFB0') }
    [pscustomobject]@{ Key='SAWG'; Hl='резерв (бензопила)';              Frames=@('SAWGA0','SAWGB0','SAWGC0','SAWGD0'); Flash=@() }
)

# ------------------------------------------------------------------- wad ----
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

# Decode one Doom patch (column/post format) into a 32bpp ARGB bitmap.
function Get-Patch([string]$name) {
    if (-not $lump.ContainsKey($name)) { throw "lump $name not found" }
    $p = $lump[$name]
    $w = [BitConverter]::ToUInt16($wb, $p)
    $h = [BitConverter]::ToUInt16($wb, $p + 2)
    $l = [BitConverter]::ToInt16($wb, $p + 4)
    $t = [BitConverter]::ToInt16($wb, $p + 6)

    $bm  = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bm.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = New-Object byte[] ($data.Stride * $h)      # zero = fully transparent

    for ($x = 0; $x -lt $w; $x++) {
        $q = $p + [BitConverter]::ToInt32($wb, $p + 8 + $x * 4)
        while ($true) {
            $td = $wb[$q]; $q++
            if ($td -eq 255) { break }
            $len = $wb[$q]; $q += 2                  # length + unused byte
            for ($i = 0; $i -lt $len; $i++) {
                $idx = $wb[$q + $i]
                $o = ($td + $i) * $data.Stride + $x * 4
                $buf[$o]     = $pal[$idx * 3 + 2]    # B
                $buf[$o + 1] = $pal[$idx * 3 + 1]    # G
                $buf[$o + 2] = $pal[$idx * 3]        # R
                $buf[$o + 3] = 255                   # A
            }
            $q += $len + 1
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $data.Scan0, $buf.Length)
    $bm.UnlockBits($data)
    return [pscustomobject]@{ Bm = $bm; W = $w; H = $h; Left = $l; Top = $t }
}

# ------------------------------------------------- per-weapon union canvas ----
foreach ($wp in $weapons) {
    $info = @()
    foreach ($n in @($wp.Frames + $wp.Flash)) {
        $pt = Get-Patch $n
        $info += [pscustomobject]@{ Name = $n; Pt = $pt; X = (-$pt.Left); Y = (-$pt.Top) }
    }
    $minX = ($info | ForEach-Object { $_.X }         | Measure-Object -Minimum).Minimum
    $minY = ($info | ForEach-Object { $_.Y }         | Measure-Object -Minimum).Minimum
    $maxX = ($info | ForEach-Object { $_.X + $_.Pt.W } | Measure-Object -Maximum).Maximum
    $maxY = ($info | ForEach-Object { $_.Y + $_.Pt.H } | Measure-Object -Maximum).Maximum
    Add-Member -InputObject $wp -NotePropertyName Info -NotePropertyValue $info -Force
    Add-Member -InputObject $wp -NotePropertyName MinX -NotePropertyValue $minX -Force
    Add-Member -InputObject $wp -NotePropertyName MinY -NotePropertyValue $minY -Force
    Add-Member -InputObject $wp -NotePropertyName CW   -NotePropertyValue ($maxX - $minX) -Force
    Add-Member -InputObject $wp -NotePropertyName CH   -NotePropertyValue ($maxY - $minY) -Force
    Add-Member -InputObject $wp -NotePropertyName Ox   -NotePropertyValue (-$minX) -Force   # psprite origin in canvas coords
    Add-Member -InputObject $wp -NotePropertyName Oy   -NotePropertyValue (-$minY) -Force
}

# ------------------------------------------------------------- the sheet ----
$cellW = [int](($weapons | ForEach-Object { $_.CW } | Measure-Object -Maximum).Maximum * $Scale) + 16
$cellH = [int](($weapons | ForEach-Object { $_.CH } | Measure-Object -Maximum).Maximum * $Scale) + 34
$labelW = 250
$cells  = [int](($weapons | ForEach-Object { $_.Frames.Count + $_.Flash.Count } | Measure-Object -Maximum).Maximum)
$sheetW = $labelW + $cells * $cellW + 16
$sheetH = $weapons.Count * $cellH + 40

$sheet = New-Object System.Drawing.Bitmap($sheetW, $sheetH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bg = [System.Drawing.Graphics]::FromImage($sheet)
$bg.Clear([System.Drawing.Color]::FromArgb(255, 24, 24, 28))
$bg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$bg.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$bg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$font  = New-Object System.Drawing.Font('Consolas', 11)
$fontB = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$penBg = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 70, 70, 80))
$penCross = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 255, 60, 60), 1)
$brText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 220, 220, 220))
$brLabel = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 210, 120))
$brCap = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 150, 200, 255))

$row = 0
"{0,-6} {1,-24} {2,10} {3,10}  {4}" -f 'lump', 'HL weapon', 'canvas', 'origin', 'frames (canvas x,y)'
foreach ($wp in $weapons) {
    $y0 = 20 + $row * $cellH

    # label block
    $bg.DrawString(("{0}  ->  {1}" -f $wp.Key, $wp.Hl), $fontB, $brLabel, 8, ($y0 + 6))
    $bg.DrawString(("canvas {0}x{1}  origin ({2},{3})" -f $wp.CW, $wp.CH, $wp.Ox, $wp.Oy), $font, $brText, 8, ($y0 + 26))
    $bg.DrawString(("frames: {0}" -f ($wp.Frames -join ' ')), $font, $brText, 8, ($y0 + 42))
    $bg.DrawString(("flash : {0}" -f ($wp.Flash -join ' ')), $font, $brText, 8, ($y0 + 58))

    $cx = $labelW
    $cellsToDraw = @()
    foreach ($n in $wp.Frames) { $cellsToDraw += [pscustomobject]@{ Name = $n; Overlay = $null } }
    if ($wp.Flash.Count -gt 0) {
        foreach ($n in $wp.Flash) { $cellsToDraw += [pscustomobject]@{ Name = $n; Overlay = $wp.Frames[0] } }
    }

    $frameTxt = @()
    foreach ($c in $cellsToDraw) {
        # the whole weapon canvas goes into the cell, bottom-centre aligned
        $dx = $cx + [int](($cellW - $wp.CW * $Scale) / 2)
        $dy = $y0 + 8 + [int](($cellH - 26 - $wp.CH * $Scale) / 2)

        # base frame
        foreach ($src in @($c.Name, $c.Overlay)) {
            if (-not $src) { continue }
            $it = $wp.Info | Where-Object { $_.Name -eq $src }
            $fx = $dx + [int](($it.X - $wp.MinX) * $Scale)
            $fy = $dy + [int](($it.Y - $wp.MinY) * $Scale)
            $fw = [int]($it.Pt.W * $Scale)
            $fh = [int]($it.Pt.H * $Scale)
            if ($fw -lt 1) { $fw = 1 }; if ($fh -lt 1) { $fh = 1 }
            $bg.DrawImage($it.Pt.Bm, (New-Object System.Drawing.Rectangle($fx, $fy, $fw, $fh)))
        }

        # psprite origin inside this canvas + cell border
        $ax = $dx + [int]($wp.Ox * $Scale)
        $ay = $dy + [int]($wp.Oy * $Scale)
        if ($ax -ge $cx -and $ax -le $cx + $cellW) {
            $bg.DrawLine($penCross, $ax - 5, $ay, $ax + 5, $ay)
            $bg.DrawLine($penCross, $ax, $ay - 5, $ax, $ay + 5)
        }
        $bg.DrawRectangle($penBg, $cx, $y0, $cellW, $cellH - 20)
        $cap = if ($c.Overlay) { ("{0} + {1}" -f $c.Overlay, $c.Name) } else { $c.Name }
        $bg.DrawString($cap, $font, $brCap, ($cx + 4), ($y0 + $cellH - 18))

        $frameTxt += ("{0}=({1},{2})" -f $c.Name, ($ax - $cx), ($ay - $y0 - 8))
        $cx += $cellW
    }

    "{0,-6} {1,-24} {2,10} {3,10}  {4}" -f $wp.Key, $wp.Hl, ("{0}x{1}" -f $wp.CW, $wp.CH), ("{0},{1}" -f $wp.Ox, $wp.Oy), ($frameTxt -join ' ')
    $row++
}

$bg.Dispose()
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

"sheet    : {0}  ({1}x{2}, scale {3})" -f $Out, $sheetW, $sheetH, $Scale
