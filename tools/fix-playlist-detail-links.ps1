$ErrorActionPreference = 'Stop'

$playlistRoot = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist'
$detailFiles = Get-ChildItem -LiteralPath $playlistRoot -Directory | ForEach-Object {
  Join-Path $_.FullName 'index.html'
}

$stats = [ordered]@{
  FilesScanned = 0
  FilesChanged = 0
  PlaylistHubFixes = 0
  IndexPathFixes = 0
}

foreach ($file in $detailFiles) {
  if (-not (Test-Path -LiteralPath $file)) { continue }

  $stats.FilesScanned++
  $original = Get-Content -LiteralPath $file -Raw
  $updated = $original

  $count1 = ([regex]::Matches($updated, 'href="\.\./\.\./index(?:\.html)?"', 'IgnoreCase')).Count
  if ($count1 -gt 0) {
    $updated = [regex]::Replace($updated, 'href="\.\./\.\./index(?:\.html)?"', 'href="../index.html"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $stats.PlaylistHubFixes += $count1
  }

  $count2 = ([regex]::Matches($updated, 'href="\.\./index"', 'IgnoreCase')).Count
  if ($count2 -gt 0) {
    $updated = [regex]::Replace($updated, 'href="\.\./index"', 'href="../index.html"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $stats.IndexPathFixes += $count2
  }

  if ($updated -ne $original) {
    [System.IO.File]::WriteAllText($file, $updated, [System.Text.Encoding]::UTF8)
    $stats.FilesChanged++
  }
}

$report = @(
  'Playlist detail link fix report'
  "Files scanned: $($stats.FilesScanned)"
  "Files changed: $($stats.FilesChanged)"
  "Playlist hub fixes: $($stats.PlaylistHubFixes)"
  "Index path fixes: $($stats.IndexPathFixes)"
)

$reportPath = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\PLAYLIST_DETAIL_LINK_FIX_REPORT.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
