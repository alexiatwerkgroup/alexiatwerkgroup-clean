$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE'
$playlistRoot = Join-Path $root 'playlist'
$targets = @(
  (Join-Path $playlistRoot 'index.html')
) + (Get-ChildItem -LiteralPath $playlistRoot -Directory | ForEach-Object {
  Join-Path $_.FullName 'index.html'
})

$stats = [ordered]@{
  FilesScanned = 0
  FilesChanged = 0
  HrefRewrites = 0
  JsonFilenameRewrites = 0
}

foreach ($file in $targets) {
  if (-not (Test-Path -LiteralPath $file)) { continue }

  $stats.FilesScanned++
  $original = Get-Content -LiteralPath $file -Raw
  $updated = $original

  $hrefMatches = [regex]::Matches($updated, 'href="((?!https?:|/|#|mailto:|javascript:)[^"]+?)\.html"', 'IgnoreCase').Count
  if ($hrefMatches -gt 0) {
    $updated = [regex]::Replace(
      $updated,
      'href="((?!https?:|/|#|mailto:|javascript:)[^"]+?)\.html"',
      {
        param($match)
        $target = $match.Groups[1].Value
        if ($target -ieq 'index') { return 'href="../index.html"' }
        if ($target -like '../*') { return 'href="' + $target + '"' }
        return 'href="' + $target + '"'
      },
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $stats.HrefRewrites += $hrefMatches
  }

  $jsonMatches = [regex]::Matches($updated, '"filename"\s*:\s*"([^"]+?)\.html"', 'IgnoreCase').Count
  if ($jsonMatches -gt 0) {
    $updated = [regex]::Replace(
      $updated,
      '"filename"\s*:\s*"([^"]+?)\.html"',
      {
        param($match)
        $target = $match.Groups[1].Value
        if ($target -ieq 'index') { return '"filename":"../index.html"' }
        if ($target -like '../*') { return '"filename":"' + $target + '"' }
        return '"filename":"' + $target + '"'
      },
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $stats.JsonFilenameRewrites += $jsonMatches
  }

  if ($updated -ne $original) {
    [System.IO.File]::WriteAllText($file, $updated, [System.Text.Encoding]::UTF8)
    $stats.FilesChanged++
  }
}

$report = @(
  'Playlist internal link normalization report'
  "Files scanned: $($stats.FilesScanned)"
  "Files changed: $($stats.FilesChanged)"
  "Href rewrites: $($stats.HrefRewrites)"
  "JSON filename rewrites: $($stats.JsonFilenameRewrites)"
)

$reportPath = Join-Path $root 'PLAYLIST_INTERNAL_LINK_NORMALIZATION_REPORT.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
