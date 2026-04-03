$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE'
$playlist = Join-Path $root 'playlist'
$report = Join-Path $root 'PLAYLIST_DIRECTORY_PUBLISH_REPORT.txt'

$htmlFiles = Get-ChildItem -Path $playlist -Filter '*.html' -File
$canonical = @{}
$redirectPages = @{}

foreach ($file in $htmlFiles) {
  $content = (Get-Content -Path $file.FullName -TotalCount 12) -join "`n"
  if ($content -match '<title>Redirecting\.\.\.</title>') {
    $redirectPages[$file.BaseName] = $file
  } else {
    $canonical[$file.BaseName] = $file
  }
}

$dirsPublished = 0
$dirsRedirected = 0

foreach ($dir in Get-ChildItem -Path $playlist -Directory) {
  $idx = Join-Path $dir.FullName 'index.html'
  $slug = $dir.Name
  if (-not (Test-Path $idx)) { continue }

  if ($canonical.ContainsKey($slug)) {
    $source = $canonical[$slug].FullName
    Copy-Item -LiteralPath $source -Destination $idx -Force
    $dirsPublished++
    continue
  }

  if ($redirectPages.ContainsKey($slug)) {
    $raw = Get-Content -Path $redirectPages[$slug].FullName -Raw
    $target = $null
    $m = [regex]::Match($raw, 'location\.replace\("\./(?<target>[^"]+)"\)')
    if ($m.Success) {
      $target = $m.Groups['target'].Value
    } else {
      $m = [regex]::Match($raw, 'url=\./(?<target>[^"''<>]+)')
      if ($m.Success) { $target = $m.Groups['target'].Value }
    }

    if ($target) {
      $targetFolder = $target -replace '\.html$',''
      $redirectDoc = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Redirecting...</title>
<meta name="robots" content="noindex,follow"/>
<link rel="canonical" href="https://alexiatwerkgroup.com/playlist/$targetFolder/"/>
<meta http-equiv="refresh" content="0; url=../$targetFolder/"/>
<script>location.replace("../$targetFolder/");</script>
</head>
<body>
<p>Redirecting...</p>
</body>
</html>
"@
      Set-Content -Path $idx -Value $redirectDoc -NoNewline
      $dirsRedirected++
    }
  }
}

$lines = @(
  "Canonical html pages: $($canonical.Count)"
  "Alias html redirects: $($redirectPages.Count)"
  "Directory pages published: $dirsPublished"
  "Alias directories redirected to folders: $dirsRedirected"
  "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)
Set-Content -Path $report -Value $lines
Get-Content -Path $report
