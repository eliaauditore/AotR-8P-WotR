#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Drawing

if (-not ("AotR8PNeutralAssetNative" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AotR8PNeutralAssetNative {
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@
}

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToUpperInvariant()
        }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Save-Crop(
    [Drawing.Bitmap]$Source,
    [Drawing.Rectangle]$Rectangle,
    [string]$Path
) {
    $crop = $Source.Clone($Rectangle, $Source.PixelFormat)
    try {
        $crop.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $crop.Dispose() }
}

$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$skinPath = Join-Path $OutputRoot "launcher_skin.png"
$iconPath = Join-Path $OutputRoot "launcher.ico"
$row1Path = Join-Path $OutputRoot "row1cleanpatch.png"
$row2Path = Join-Path $OutputRoot "row2cleanpatch.png"
$row3Path = Join-Path $OutputRoot "row3cleanpatch.png"
$readyPath = Join-Path $OutputRoot "readycleanpatch.png"

$width = 900
$height = 675
$bitmap = New-Object Drawing.Bitmap($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([Drawing.Color]::FromArgb(255, 13, 18, 22))

    $topBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 17, 24, 29))
    $panelBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 21, 30, 36))
    $buttonBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 28, 41, 48))
    $borderPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 92, 112, 119), 1.0)
    $accentPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 126, 153, 159), 1.0)
    $softPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 50, 68, 76), 1.0)
    try {
        $graphics.FillRectangle($topBrush, 0, 0, 900, 41)
        $graphics.DrawLine($softPen, 0, 41, 900, 41)

        # Main status area. Geometry follows the existing 900x675 launcher canvas,
        # but all artwork is generated from simple primitives owned by this project.
        $graphics.FillRectangle($panelBrush, 205, 244, 490, 205)
        $graphics.DrawRectangle($borderPen, 205, 244, 489, 204)
        $graphics.DrawRectangle($softPen, 214, 253, 471, 186)

        # Launch/status area.
        $graphics.FillRectangle($panelBrush, 195, 500, 510, 92)
        $graphics.DrawRectangle($borderPen, 195, 500, 509, 91)
        $graphics.FillRectangle($buttonBrush, 225, 513, 450, 61)
        $graphics.DrawRectangle($accentPen, 225, 513, 449, 60)

        # Minimal decorative geometry: no imported imagery, logos, fonts or textures.
        $graphics.DrawLine($accentPen, 285, 92, 615, 92)
        $graphics.DrawLine($softPen, 320, 102, 580, 102)
        $graphics.DrawEllipse($accentPen, 441, 82, 18, 18)
        $graphics.DrawLine($accentPen, 450, 72, 450, 110)
        $graphics.DrawLine($accentPen, 431, 91, 469, 91)

        # Subtle corner marks.
        foreach ($x in @(22, 858)) {
            $graphics.DrawLine($softPen, $x, 650, $x + 20, 650)
        }
    }
    finally {
        $topBrush.Dispose()
        $panelBrush.Dispose()
        $buttonBrush.Dispose()
        $borderPen.Dispose()
        $accentPen.Dispose()
        $softPen.Dispose()
    }

    $bitmap.Save($skinPath, [Drawing.Imaging.ImageFormat]::Png)

    # Existing GUI failure overlays expect these exact patch dimensions/offsets.
    # Cropping from the generated skin guarantees matching background pixels.
    Save-Crop $bitmap (New-Object Drawing.Rectangle(233, 264, 405, 44)) $row1Path
    Save-Crop $bitmap (New-Object Drawing.Rectangle(233, 314, 405, 44)) $row2Path
    Save-Crop $bitmap (New-Object Drawing.Rectangle(233, 361, 405, 47)) $row3Path
    Save-Crop $bitmap (New-Object Drawing.Rectangle(330, 450, 260, 45)) $readyPath
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

# 32x32 icon generated solely from primitives: outer ring + eight radial marks.
$iconBitmap = New-Object Drawing.Bitmap(32, 32, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$iconGraphics = [Drawing.Graphics]::FromImage($iconBitmap)
try {
    $iconGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $iconGraphics.Clear([Drawing.Color]::FromArgb(255, 13, 18, 22))
    $ringPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 145, 170, 176), 2.0)
    $dotBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 190, 202, 205))
    try {
        $iconGraphics.DrawEllipse($ringPen, 6, 6, 19, 19)
        $cx = 15.5
        $cy = 15.5
        $radius = 10.5
        foreach ($degree in @(0,45,90,135,180,225,270,315)) {
            $radian = $degree * [Math]::PI / 180.0
            $x = [single]($cx + ([Math]::Cos($radian) * $radius) - 1.25)
            $y = [single]($cy + ([Math]::Sin($radian) * $radius) - 1.25)
            $iconGraphics.FillEllipse($dotBrush, $x, $y, 2.5, 2.5)
        }
    }
    finally {
        $ringPen.Dispose()
        $dotBrush.Dispose()
    }

    $hIcon = $iconBitmap.GetHicon()
    if ($hIcon -eq [IntPtr]::Zero) { throw "Could not create neutral launcher icon handle." }
    try {
        $icon = [Drawing.Icon]::FromHandle($hIcon)
        $stream = [IO.File]::Create($iconPath)
        try { $icon.Save($stream) }
        finally { $stream.Dispose() }
    }
    finally {
        [void][AotR8PNeutralAssetNative]::DestroyIcon($hIcon)
    }
}
finally {
    $iconGraphics.Dispose()
    $iconBitmap.Dispose()
}

$records = foreach ($name in @(
    "launcher_skin.png", "launcher.ico",
    "row1cleanpatch.png", "row2cleanpatch.png", "row3cleanpatch.png", "readycleanpatch.png"
)) {
    $path = Join-Path $OutputRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated asset missing: $name" }
    [ordered]@{
        name = $name
        size = [int64](Get-Item -LiteralPath $path).Length
        sha256 = Get-Sha256 $path
    }
}

$manifest = [ordered]@{
    schema = 1
    purpose = "non-release SignPath Foundation neutral visual asset proof-of-concept"
    generator = "launcher-source/v20-signpath/GENERATE_NEUTRAL_ASSETS.ps1"
    ownership = "generated by project source from geometric primitives only; no imported artwork or external image inputs"
    canvas = @{ width = 900; height = 675 }
    assets = $records
    release_status = "NON_RELEASE_POC"
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot "ASSET_PROVENANCE.json") -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SignPath neutral asset PoC generated" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
foreach ($record in $records) {
    Write-Host ("{0}  {1}  {2}" -f $record.sha256, $record.size, $record.name)
}
Write-Host "Output: $OutputRoot"
