$ErrorActionPreference = 'Stop'

$playlistRoot = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist'
$files = Get-ChildItem -LiteralPath $playlistRoot -Filter '*.html' -File

$stats = [ordered]@{
  FilesScanned = 0
  DirectoriesWritten = 0
  RedirectDirs = 0
  FullCopies = 0
}

function Convert-PlaylistContentToCleanRoute {
  param(
    [string]$Content,
    [string]$Slug
  )

  $updated = $Content

  $canonicalHtml = 'https://alexiatwerkgroup.com/playlist/' + $Slug + '.html'
  $canonicalClean = 'https://alexiatwerkgroup.com/playlist/' + $Slug
  $updated = $updated.Replace($canonicalHtml, $canonicalClean)

  $updated = $updated -replace 'href="assets/', 'href="../assets/'
  $updated = $updated -replace 'src="assets/', 'src="../assets/'
  $updated = $updated -replace '\("assets/', '("../assets/'
  $updated = $updated -replace "='assets/", "='../assets/"

  $updated = $updated -replace 'href="index\.html"', 'href="../index.html"'
  $updated = $updated -replace 'href="((?!https?:|/|#|mailto:|javascript:)[^"]+)\.html"', {
    param($m)
    $target = $m.Groups[1].Value
    if ($target -eq 'index') { 'href="../index.html"' } else { 'href="../' + $target + '"' }
  }

  $updated = $updated -replace '"filename":\s*"([^"]+)\.html"', {
    param($m)
    '"filename":"../' + $m.Groups[1].Value + '"'
  }

  return $updated
}

foreach ($file in $files) {
  $stats.FilesScanned++

  $slug = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if ($slug -eq 'index') { continue }

  $targetDir = Join-Path $playlistRoot $slug
  if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
  }

  $targetFile = Join-Path $targetDir 'index.html'
  $content = Get-Content -LiteralPath $file.FullName -Raw

  $redirectMatch = [regex]::Match($content, 'location\.replace\("([^"]+\.html)"\)')
  if (-not $redirectMatch.Success) {
    $redirectMatch = [regex]::Match($content, 'meta http-equiv="refresh" content="0; url=([^"]+\.html)"')
  }

  if ($redirectMatch.Success) {
    $targetHtml = $redirectMatch.Groups[1].Value
    $targetSlug = [System.IO.Path]::GetFileNameWithoutExtension($targetHtml)
    $targetHref = if ($targetSlug -eq 'index') { '../index.html' } else { '../' + $targetSlug }
    $redirectDoc = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Redirecting...</title>
<meta name="robots" content="noindex,follow"/>
<link rel="canonical" href="https://alexiatwerkgroup.com/playlist/$targetSlug"/>
<meta http-equiv="refresh" content="0; url=$targetHref"/>
<script>location.replace("$targetHref");</script>
</head>
<body>
<p>Redirecting...</p>
</body>
</html>
"@
    [System.IO.File]::WriteAllText($targetFile, $redirectDoc, [System.Text.Encoding]::UTF8)
    $stats.RedirectDirs++
  }
  else {
    $updated = Convert-PlaylistContentToCleanRoute -Content $content -Slug $slug
    [System.IO.File]::WriteAllText($targetFile, $updated, [System.Text.Encoding]::UTF8)
    $stats.FullCopies++
  }

  $stats.DirectoriesWritten++
}

$report = @(
  "Playlist clean directory publish report"
  "Files scanned: $($stats.FilesScanned)"
  "Directories written: $($stats.DirectoriesWritten)"
  "Redirect dirs: $($stats.RedirectDirs)"
  "Full copies: $($stats.FullCopies)"
)

$reportPath = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\PLAYLIST_CLEAN_DIRECTORY_REPORT.txt'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
