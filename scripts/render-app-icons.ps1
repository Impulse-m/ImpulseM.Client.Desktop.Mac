# Renders the macOS application icon PNG set from a master SVG.
#
# The script reads the master logo (a circle plus one polyline stroke, in a square viewBox)
# and draws it with System.Drawing at each size. The whole logo is scaled to (1 - Inset) of the
# canvas and centred, so the launcher disc keeps a margin on every side.
#
# Outputs (the file names are the ones referenced by Contents.json of AppIcon.appiconset):
#   Logo_16, Logo_32, Logo_64, Logo_128, Logo_256, Logo_512, Logo_1024 (.png)
#   and the duplicates Logo_32-1, Logo_256-1, Logo_512-1 copied from the same render.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/render-app-icons.ps1 `
#       -Source <path to master svg> `
#       -OutDir Telegram-Mac/Assets.xcassets/AppIcon.appiconset

param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$OutDir,
    [double]$Inset = 0.04
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

[double]$viewBox = 200.0

[string]$svgPath = (Resolve-Path -LiteralPath $Source).Path
[string]$svgText = [System.IO.File]::ReadAllText($svgPath)

$circleMatch = [regex]::Match($svgText, '<circle\s+cx="([\d.]+)"\s+cy="([\d.]+)"\s+r="([\d.]+)"\s+fill="(#[0-9A-Fa-f]{6})"')
if (-not $circleMatch.Success) {
    throw "Disc circle not found in $svgPath"
}

[double]$discX = [double]::Parse($circleMatch.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
[double]$discY = [double]::Parse($circleMatch.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
[double]$discRadius = [double]::Parse($circleMatch.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
[string]$discColour = $circleMatch.Groups[4].Value

$pathMatch = [regex]::Match($svgText, '<path\s+d="([^"]+)"[^>]*?stroke="(#[0-9A-Fa-f]{6})"[^>]*?stroke-width="([\d.]+)"')
if (-not $pathMatch.Success) {
    $pathMatch = [regex]::Match($svgText, '<path\s+d="([^"]+)"[^>]*?stroke-width="([\d.]+)"[^>]*?stroke="(#[0-9A-Fa-f]{6})"')
    if (-not $pathMatch.Success) {
        throw "Pulse path not found in $svgPath"
    }
    [string]$strokeColour = $pathMatch.Groups[3].Value
    [string]$strokeWidthText = $pathMatch.Groups[2].Value
}
else {
    [string]$strokeColour = $pathMatch.Groups[2].Value
    [string]$strokeWidthText = $pathMatch.Groups[3].Value
}

[double]$strokeWidth = [double]::Parse($strokeWidthText, [System.Globalization.CultureInfo]::InvariantCulture)
[string]$pathData = $pathMatch.Groups[1].Value

[System.Collections.Generic.List[System.Drawing.PointF]]$points = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
[double]$currentX = 0.0
[double]$currentY = 0.0

$commandMatches = [regex]::Matches($pathData, '([MLHV])\s*(-?[\d.]+)(?:[\s,]+(-?[\d.]+))?')
foreach ($commandMatch in $commandMatches) {
    [string]$command = $commandMatch.Groups[1].Value
    [double]$first = [double]::Parse($commandMatch.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    switch ($command) {
        'M' {
            $currentX = $first
            $currentY = [double]::Parse($commandMatch.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        'L' {
            $currentX = $first
            $currentY = [double]::Parse($commandMatch.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        'H' {
            $currentX = $first
        }
        'V' {
            $currentY = $first
        }
    }
    $points.Add([System.Drawing.PointF]::new([single]$currentX, [single]$currentY))
}

if ($points.Count -lt 2) {
    throw "Pulse path has fewer than two points: $pathData"
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

[string]$outFullDir = (Resolve-Path -LiteralPath $OutDir).Path

function Save-Render {
    param(
        [int]$Size,
        [string]$FileName
    )

    [double]$scale = ($Size / $viewBox) * (1.0 - $Inset)
    [double]$offset = $Size * ($Inset / 2.0)

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)

        [double]$discLeft = $offset + ($discX - $discRadius) * $scale
        [double]$discTop = $offset + ($discY - $discRadius) * $scale
        [double]$discSide = 2.0 * $discRadius * $scale

        $discColor = [System.Drawing.ColorTranslator]::FromHtml($discColour)
        $discBrush = New-Object System.Drawing.SolidBrush($discColor)
        try {
            $graphics.FillEllipse($discBrush, [single]$discLeft, [single]$discTop, [single]$discSide, [single]$discSide)
        }
        finally {
            $discBrush.Dispose()
        }

        $scaledPoints = New-Object 'System.Drawing.PointF[]' $points.Count
        for ([int]$index = 0; $index -lt $points.Count; $index++) {
            [double]$px = $offset + $points[$index].X * $scale
            [double]$py = $offset + $points[$index].Y * $scale
            $scaledPoints[$index] = [System.Drawing.PointF]::new([single]$px, [single]$py)
        }

        $strokeColor = [System.Drawing.ColorTranslator]::FromHtml($strokeColour)
        $pen = New-Object System.Drawing.Pen($strokeColor, [single]($strokeWidth * $scale))
        try {
            $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $graphics.DrawLines($pen, $scaledPoints)
        }
        finally {
            $pen.Dispose()
        }

        [string]$target = Join-Path -Path $outFullDir -ChildPath $FileName
        $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $check = [System.Drawing.Image]::FromFile((Join-Path -Path $outFullDir -ChildPath $FileName))
    try {
        if ($check.Width -ne $Size -or $check.Height -ne $Size) {
            throw "$FileName is $($check.Width)x$($check.Height), expected $Size"
        }
    }
    finally {
        $check.Dispose()
    }

    Write-Output "$FileName ${Size}x${Size}"
}

[System.Collections.Specialized.OrderedDictionary]$sizes = [ordered]@{
    'Logo_16.png' = 16
    'Logo_32.png' = 32
    'Logo_64.png' = 64
    'Logo_128.png' = 128
    'Logo_256.png' = 256
    'Logo_512.png' = 512
    'Logo_1024.png' = 1024
}

foreach ($entry in $sizes.GetEnumerator()) {
    Save-Render -Size ([int]$entry.Value) -FileName ([string]$entry.Key)
}

[System.Collections.Specialized.OrderedDictionary]$duplicates = [ordered]@{
    'Logo_32-1.png' = 'Logo_32.png'
    'Logo_256-1.png' = 'Logo_256.png'
    'Logo_512-1.png' = 'Logo_512.png'
}

foreach ($entry in $duplicates.GetEnumerator()) {
    Copy-Item -LiteralPath (Join-Path -Path $outFullDir -ChildPath ([string]$entry.Value)) -Destination (Join-Path -Path $outFullDir -ChildPath ([string]$entry.Key)) -Force
    Write-Output "$($entry.Key) copied from $($entry.Value)"
}
