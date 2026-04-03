$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist'
$files = Get-ChildItem -LiteralPath $root -Filter '*.html' -File

$stats = [ordered]@{
  FilesScanned = 0
  CssPathFixes = 0
  JsPathFixes = 0
  ExtraBraceFixes = 0
  FilesChanged = 0
}

foreach ($file in $files) {
  $stats.FilesScanned++
  $original = Get-Content -LiteralPath $file.FullName -Raw
  $updated = $original

  $cssMatches = ([regex]'href="playlist/assets/pro-extras\.css"').Matches($updated).Count
  if ($cssMatches -gt 0) {
    $updated = $updated -replace 'href="playlist/assets/pro-extras\.css"', 'href="assets/pro-extras.css"'
    $stats.CssPathFixes += $cssMatches
  }

  $jsMatches = ([regex]'"playlist/assets/pro-extras\.js\?v=trex2"').Matches($updated).Count
  if ($jsMatches -gt 0) {
    $updated = $updated -replace '"playlist/assets/pro-extras\.js\?v=trex2"', '"assets/pro-extras.js?v=trex2"'
    $stats.JsPathFixes += $jsMatches
  }

  $braceMatches = ([regex]'width:auto!important}}').Matches($updated).Count
  if ($braceMatches -gt 0) {
    $updated = $updated -replace 'width:auto!important}}', 'width:auto!important}'
    $stats.ExtraBraceFixes += $braceMatches
  }

  if ($updated -ne $original) {
    [System.IO.File]::WriteAllText($file.FullName, $updated, [System.Text.Encoding]::UTF8)
    $stats.FilesChanged++
  }
}

$report = @(
  "Playlist black-screen repair report"
  "Files scanned: $($stats.FilesScanned)"
  "Files changed: $($stats.FilesChanged)"
  "CSS path fixes: $($stats.CssPathFixes)"
  "JS path fixes: $($stats.JsPathFixes)"
  "Extra brace fixes: $($stats.ExtraBraceFixes)"
)

$reportPath = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\PLAYLIST_BLACK_SCREEN_REPAIR_REPORT.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
