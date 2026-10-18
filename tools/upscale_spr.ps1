# upscale_spr.ps1
# Integer nearest-neighbour upscale of a single-frame Half-Life .spr, reusing its
# embedded palette (index 255 stays transparent).  Used to make the Doom face bigger
# without guessing its source PNG.
#
# Usage: powershell -ExecutionPolicy Bypass -File upscale_spr.ps1 -Src in.spr -Out out.spr -Factor 3

param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Out,
    [int]$Factor = 3
)
$ErrorActionPreference = 'Stop'

$b = [IO.File]::ReadAllBytes($Src)
$magic = [Text.Encoding]::ASCII.GetString($b, 0, 4)
if ($magic -ne 'IDSP') { throw "$Src is not an IDSP sprite" }
$numFrames = [BitConverter]::ToInt32($b, 28)
if ($numFrames -ne 1) { throw "only single-frame sprites supported (got $numFrames)" }

$palOff   = 42
$pal      = [byte[]]$b[$palOff..($palOff + 767)]
$frameOff = $palOff + 768
$frameType = [BitConverter]::ToInt32($b, $frameOff + 0)
$fw        = [BitConverter]::ToInt32($b, $frameOff + 12)
$fh        = [BitConverter]::ToInt32($b, $frameOff + 16)
$pixOff    = $frameOff + 20
$pix       = $b[$pixOff..($pixOff + $fw * $fh - 1)]

$ow = $fw * $Factor
$oh = $fh * $Factor
$data = New-Object byte[] ($ow * $oh)
for ($y = 0; $y -lt $oh; $y++) {
    $sy = [int][Math]::Floor($y / $Factor)
    for ($x = 0; $x -lt $ow; $x++) {
        $sx = [int][Math]::Floor($x / $Factor)
        $data[$y * $ow + $x] = $pix[$sy * $fw + $sx]
    }
}

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
[IO.File]::WriteAllBytes($Out, $ms.ToArray())

"{0} ({1}x{2}) -> {3} ({4}x{5}, x{6}, {7} bytes)" -f $Src, $fw, $fh, $Out, $ow, $oh, $Factor, $ms.Length
