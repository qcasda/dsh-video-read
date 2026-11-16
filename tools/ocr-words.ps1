# ocr-words.ps1 - OCR an image and print every line with its bounding box.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\ocr-words.ps1 -Path <img>
# Output: JSON array [ { text, x, y, w, h }, ... ]

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'
$Path = (Resolve-Path $Path).Path

Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$engine = $null
foreach ($tag in @('zh-Hans-CN', 'zh-CN', 'zh-Hans')) {
    try {
        $lang = New-Object Windows.Globalization.Language $tag
        if ([Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($lang)) {
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
            if ($engine) { break }
        }
    } catch { }
}
if (-not $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if (-not $engine) { throw "No OCR language pack available." }

$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

$lines = @()
foreach ($line in $result.Lines) {
    $text = $line.Text
    $minX = [double]::MaxValue; $minY = [double]::MaxValue
    $maxX = 0.0; $maxY = 0.0
    foreach ($w in $line.Words) {
        $r = $w.BoundingRect
        if ($r.X -lt $minX) { $minX = $r.X }
        if ($r.Y -lt $minY) { $minY = $r.Y }
        if (($r.X + $r.Width) -gt $maxX) { $maxX = $r.X + $r.Width }
        if (($r.Y + $r.Height) -gt $maxY) { $maxY = $r.Y + $r.Height }
    }
    if ($minX -eq [double]::MaxValue) { continue }
    $lines += [pscustomobject]@{
        text = $text
        x    = [int]$minX
        y    = [int]$minY
        w    = [int]($maxX - $minX)
        h    = [int]($maxY - $minY)
    }
}

$lines | ConvertTo-Json -Compress -Depth 3
$stream.Dispose()
