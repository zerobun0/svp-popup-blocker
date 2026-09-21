<#
.SYNOPSIS
    Compiles src/svp-popup-blocker.ps1 into a standalone dist/SvpPopupBlocker.exe.

.DESCRIPTION
    Uses the ps2exe module. The output is a true GUI-subsystem binary
    (-noConsole), so it never allocates a console window at all, unlike a
    plain powershell.exe invocation. That removes the last source of the
    Windows Terminal tab-flash problem entirely, rather than working
    around it with a wrapper.
#>

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe
Add-Type -AssemblyName System.Drawing

$AppVersion = "1.2.0"
$srcPath = Join-Path $PSScriptRoot "src\svp-popup-blocker.ps1"
$distDir = Join-Path $PSScriptRoot "dist"
$outPath = Join-Path $distDir "SvpPopupBlocker.exe"

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

# Same shield-and-checkmark glyph the running app draws for its tray icon,
# used here as the compiled exe's own file icon (Explorer/Task Manager).
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
[System.Drawing.Point[]]$pts = @(
    [System.Drawing.Point]::new(16, 1),
    [System.Drawing.Point]::new(30, 7),
    [System.Drawing.Point]::new(30, 16),
    [System.Drawing.Point]::new(16, 31),
    [System.Drawing.Point]::new(2, 16),
    [System.Drawing.Point]::new(2, 7)
)
$path.AddPolygon($pts)
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(41, 128, 185))
$g.FillPath($brush, $path)
$pen = New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(60, 0, 0, 0)), 1.5)
$g.DrawPath($pen, $path)
$checkPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
$checkPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$checkPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
[System.Drawing.Point[]]$checkPts = @(
    [System.Drawing.Point]::new(9, 16),
    [System.Drawing.Point]::new(14, 22),
    [System.Drawing.Point]::new(23, 10)
)
$g.DrawLines($checkPen, $checkPts)

$tempIco = Join-Path $env:TEMP "svp-popup-blocker-build.ico"
$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)
$fs = [System.IO.File]::Create($tempIco)
$icon.Save($fs)
$fs.Close()

Invoke-ps2exe -inputFile $srcPath -outputFile $outPath `
    -noConsole -STA `
    -title "SVP Popup Blocker" `
    -product "SVP Popup Blocker" `
    -description "Closes the SVP4 activation nag dialog automatically" `
    -version "$AppVersion.0" `
    -requireAdmin:$false `
    -iconFile $tempIco

if (-not (Test-Path $outPath)) {
    Write-Error "Build failed: $outPath was not created."
    exit 1
}
Write-Host "Built: $outPath"
