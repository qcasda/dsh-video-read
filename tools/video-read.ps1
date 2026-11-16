# video-read.ps1 - read any web page that plays a <video> and print a compact subtitle timeline.
#
# The page is rendered in a HEADLESS Edge instance, so nothing appears on your screen.
# Frames are captured through the DevTools Protocol, OCR'd with the Windows OCR engine,
# and de-duplicated so only newly appearing text is printed.
#
# Requirements: Windows 10/11, Microsoft Edge, Node.js 18+
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\video-read.ps1 -Url <page-url> [-Frames 16] [-Audio]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$Frames = 16,
    [switch]$Audio,
    [string]$WorkDir = (Join-Path $env:TEMP 'video-read'),
    [int]$Port = 9222
)

$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "Node.js (18+) is required: https://nodejs.org" }

$edgeCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
$edge = $edgeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw "Microsoft Edge not found." }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$prof = Join-Path $WorkDir 'edge-profile'
$framesDir = Join-Path $WorkDir 'frames'
if (Test-Path $framesDir) { Remove-Item $framesDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $framesDir | Out-Null

function Stop-Headless {
    Get-Process msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -eq '' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

# 1. start a throwaway headless browser
Stop-Headless
Start-Sleep -Seconds 2
Start-Process $edge -ArgumentList @(
    '--headless=new',
    "--remote-debugging-port=$Port",
    "--user-data-dir=`"$prof`"",
    '--no-first-run', '--disable-gpu',
    '--autoplay-policy=no-user-gesture-required',
    $Url
)
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 2
    if ((Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) { $ready = $true; break }
}
if (-not $ready) { Stop-Headless; throw "headless browser did not open the debug port" }
Start-Sleep -Seconds 8

# 2. capture frames (seek/play is handled inside the script)
$null = & $node (Join-Path $tools 'page-frames.js') $Port $framesDir $Frames "$Url" 2>&1

# 3. optional: grab the audio stream and transcribe with faster-whisper
if ($Audio) {
    $mediaJson = Join-Path $WorkDir 'media.json'
    if (Test-Path $mediaJson) { Remove-Item $mediaJson -Force }
    $null = & $node (Join-Path $tools 'page-media.js') $Port 12 $mediaJson 2>&1
    if (Test-Path $mediaJson) {
        $audioUrl = (Get-Content $mediaJson -Raw | ConvertFrom-Json) | Where-Object { $_ -match 'audio' } | Select-Object -First 1
        if ($audioUrl) {
            $audioFile = Join-Path $WorkDir 'audio.bin'
            try {
                Invoke-WebRequest -Uri $audioUrl -OutFile $audioFile -TimeoutSec 180 `
                    -Headers @{ 'Referer' = $Url; 'User-Agent' = 'Mozilla/5.0' }
                $wav = Join-Path $WorkDir 'audio16k.wav'
                $ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
                if ($ffmpeg) {
                    & $ffmpeg -hide_banner -loglevel error -y -i $audioFile -ar 16000 -ac 1 -c:a pcm_s16le $wav
                    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
                    if ($py -and (Test-Path $wav)) {
                        "--- AUDIO ---"
                        $env:PYTHONIOENCODING = 'utf-8'
                        & $py (Join-Path $tools 'transcribe.py') $wav small 2>$null
                    }
                } else { "AUDIO: ffmpeg not found, skipped" }
            } catch { "AUDIO: download failed - $($_.Exception.Message)" }
        }
    }
}

# 4. OCR every frame, keep only the subtitle band, drop repeats
Add-Type -AssemblyName System.Drawing
$seen = New-Object System.Collections.Generic.HashSet[string]
"SRC: $Url"
"FRAMES: $((Get-ChildItem $framesDir -Filter *.png -ErrorAction SilentlyContinue | Measure-Object).Count)"
Get-ChildItem $framesDir -Filter *.png -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $bmp = [System.Drawing.Bitmap]::FromFile($_.FullName)
    $y0 = [int]($bmp.Height * 0.55)
    $crop = $bmp.Clone((New-Object System.Drawing.Rectangle 0, $y0, $bmp.Width, ($bmp.Height - $y0)), $bmp.PixelFormat)
    $tmp = Join-Path $WorkDir 'sub.png'
    $crop.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose(); $bmp.Dispose()

    $lines = powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'ocr-words.ps1') -Path $tmp 2>$null
    if (-not $lines) { return }
    try { $arr = $lines | ConvertFrom-Json } catch { return }
    $new = @()
    foreach ($l in $arr) {
        $t = ($l.text -replace '\s+', '').Trim()
        if ($t.Length -lt 4) { continue }
        if ($t -match '循环播放|浏览器限制|静音|auto-play|muted') { continue }
        if ($seen.Contains($t)) { continue }
        [void]$seen.Add($t)
        $new += $t
    }
    if ($new.Count -gt 0) { "{0} | {1}" -f $_.BaseName, ($new -join ' | ') }
}

Stop-Headless
"END lines=$($seen.Count)"
