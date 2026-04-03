$ErrorActionPreference = 'Stop'

$playlistRoot = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist'
$reportPath = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\PLAYLIST_ROUTE_REBUILD_REPORT.txt'

function Get-RedirectTargetSlug {
  param([string]$Content)

  $patterns = @(
    'location\.replace\("([^"]+?)(?:\.html)?"\)',
    'meta http-equiv="refresh" content="0; url=([^"]+?)(?:\.html)?"'
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return [System.IO.Path]::GetFileNameWithoutExtension($match.Groups[1].Value)
    }
  }

  return $null
}

function Convert-ToCleanRouteHtml {
  param(
    [string]$Content,
    [string]$Slug
  )

  $updated = $Content
  $canonicalHtml = 'https://alexiatwerkgroup.com/playlist/' + $Slug + '.html'
  $canonicalClean = 'https://alexiatwerkgroup.com/playlist/' + $Slug
  $updated = $updated.Replace($canonicalHtml, $canonicalClean)

  $updated = [regex]::Replace($updated, 'href="assets/', 'href="../assets/')
  $updated = [regex]::Replace($updated, 'src="assets/', 'src="../assets/')
  $updated = [regex]::Replace($updated, '\("assets/', '("../assets/')
  $updated = [regex]::Replace($updated, "='assets/", "='../assets/")

  $updated = [regex]::Replace($updated, 'href="index\.html"', 'href="../index.html"', 'IgnoreCase')

  $updated = [regex]::Replace(
    $updated,
    'href="((?!https?:|/|#|mailto:|javascript:)[^"]+?)\.html"',
    {
      param($match)
      $target = $match.Groups[1].Value
      if ($target -ieq 'index') { return 'href="../index.html"' }
      return 'href="../' + $target + '"'
    }
  )

  $updated = [regex]::Replace(
    $updated,
    '"filename"\s*:\s*"([^"]+?)\.html"',
    {
      param($match)
      return '"filename":"../' + $match.Groups[1].Value + '"'
    }
  )

  return $updated
}

function New-RedirectDocument {
  param(
    [string]$DestinationPath,
    [string]$CanonicalUrl
  )

@"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Redirecting...</title>
<meta name="robots" content="noindex,follow"/>
<link rel="canonical" href="$CanonicalUrl"/>
<meta http-equiv="refresh" content="0; url=$DestinationPath"/>
<script>location.replace("$DestinationPath");</script>
</head>
<body>
<p>Redirecting...</p>
</body>
</html>
"@
}

$stats = [ordered]@{
  HtmlFiles = 0
  DirectoriesDeleted = 0
  CanonicalPages = 0
  AliasPages = 0
  HtmlRedirectsWritten = 0
  DirectoryPagesWritten = 0
  TempFilesDeleted = 0
}

$existingDirs = Get-ChildItem -LiteralPath $playlistRoot -Directory
foreach ($dir in $existingDirs) {
  Remove-Item -LiteralPath $dir.FullName -Recurse -Force
  $stats.DirectoriesDeleted++
}

$tempFiles = @(
  'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist-live-check.png',
  'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist-live-dom.html'
)
foreach ($temp in $tempFiles) {
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Force
    $stats.TempFilesDeleted++
  }
}

$htmlFiles = Get-ChildItem -LiteralPath $playlistRoot -Filter '*.html' -File
foreach ($file in $htmlFiles) {
  $stats.HtmlFiles++

  $slug = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if ($slug -ieq 'index') { continue }

  $content = Get-Content -LiteralPath $file.FullName -Raw
  $dirPath = Join-Path $playlistRoot $slug
  $dirIndex = Join-Path $dirPath 'index.html'
  New-Item -ItemType Directory -Path $dirPath -Force | Out-Null

  $targetSlug = Get-RedirectTargetSlug -Content $content
  if ($targetSlug) {
    $stats.AliasPages++
    $cleanDest = if ($targetSlug -ieq 'index') { '../index.html' } else { '../' + $targetSlug }
    $cleanCanonical = if ($targetSlug -ieq 'index') { 'https://alexiatwerkgroup.com/playlist/' } else { 'https://alexiatwerkgroup.com/playlist/' + $targetSlug }

    $dirDoc = New-RedirectDocument -DestinationPath $cleanDest -CanonicalUrl $cleanCanonical
    [System.IO.File]::WriteAllText($dirIndex, $dirDoc, [System.Text.Encoding]::UTF8)

    $htmlDest = if ($targetSlug -ieq 'index') { './index' } else { './' + $targetSlug }
    $htmlCanonical = 'https://alexiatwerkgroup.com/playlist/' + $slug
    $htmlDoc = New-RedirectDocument -DestinationPath $htmlDest -CanonicalUrl $htmlCanonical
    [System.IO.File]::WriteAllText($file.FullName, $htmlDoc, [System.Text.Encoding]::UTF8)
  }
  else {
    $stats.CanonicalPages++
    $cleanHtml = Convert-ToCleanRouteHtml -Content $content -Slug $slug
    [System.IO.File]::WriteAllText($dirIndex, $cleanHtml, [System.Text.Encoding]::UTF8)

    $htmlDoc = New-RedirectDocument -DestinationPath ('./' + $slug) -CanonicalUrl ('https://alexiatwerkgroup.com/playlist/' + $slug)
    [System.IO.File]::WriteAllText($file.FullName, $htmlDoc, [System.Text.Encoding]::UTF8)
  }

  $stats.DirectoryPagesWritten++
  $stats.HtmlRedirectsWritten++
}

$report = @(
  "Playlist route rebuild report"
  "HTML files scanned: $($stats.HtmlFiles)"
  "Generated directories cleared: $($stats.DirectoriesDeleted)"
  "Canonical pages rebuilt: $($stats.CanonicalPages)"
  "Alias pages rebuilt: $($stats.AliasPages)"
  "Directory pages written: $($stats.DirectoryPagesWritten)"
  "HTML redirects written: $($stats.HtmlRedirectsWritten)"
  "Temp files deleted: $($stats.TempFilesDeleted)"
)

$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
