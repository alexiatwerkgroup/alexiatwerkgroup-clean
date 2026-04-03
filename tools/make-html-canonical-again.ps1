$ErrorActionPreference = 'Stop'

$playlistRoot = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\playlist'
$reportPath = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE\PLAYLIST_HTML_CANONICAL_REPORT.txt'

function Convert-DetailContentBackToHtml {
  param(
    [string]$Content,
    [string]$Slug
  )

  $updated = $Content

  $canonicalClean = 'https://alexiatwerkgroup.com/playlist/' + $Slug
  $canonicalHtml = 'https://alexiatwerkgroup.com/playlist/' + $Slug + '.html'
  $updated = $updated.Replace($canonicalClean, $canonicalHtml)

  $updated = [regex]::Replace($updated, 'href="\.\./assets/', 'href="assets/')
  $updated = [regex]::Replace($updated, 'src="\.\./assets/', 'src="assets/')
  $updated = [regex]::Replace($updated, '\("\.\./assets/', '("assets/')
  $updated = [regex]::Replace($updated, "='\.\./assets/", "='assets/")

  $updated = [regex]::Replace($updated, 'href="\.\./index\.html"', 'href="index.html"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $updated = [regex]::Replace($updated, 'href="\.\./([^"/?#]+)"', 'href="$1.html"')
  $updated = [regex]::Replace($updated, '"filename":"\.\./([^"]+)"', '"filename":"$1.html"')

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
  HtmlRestored = 0
  DirRedirectsWritten = 0
  AliasesPreserved = 0
}

$dirs = Get-ChildItem -LiteralPath $playlistRoot -Directory
foreach ($dir in $dirs) {
  $slug = $dir.Name
  $dirIndex = Join-Path $dir.FullName 'index.html'
  $htmlFile = Join-Path $playlistRoot ($slug + '.html')

  if (-not (Test-Path -LiteralPath $dirIndex)) { continue }
  if (-not (Test-Path -LiteralPath $htmlFile)) { continue }

  $dirContent = Get-Content -LiteralPath $dirIndex -Raw
  $looksLikeRedirect = $dirContent -match 'location\.replace\(' -or $dirContent -match 'meta http-equiv="refresh"'

  if (-not $looksLikeRedirect) {
    $htmlContent = Convert-DetailContentBackToHtml -Content $dirContent -Slug $slug
    [System.IO.File]::WriteAllText($htmlFile, $htmlContent, [System.Text.Encoding]::UTF8)
    $stats.HtmlRestored++

    $redirectDoc = New-RedirectDocument -DestinationPath ('../' + $slug + '.html') -CanonicalUrl ('https://alexiatwerkgroup.com/playlist/' + $slug + '.html')
    [System.IO.File]::WriteAllText($dirIndex, $redirectDoc, [System.Text.Encoding]::UTF8)
    $stats.DirRedirectsWritten++
  }
  else {
    $stats.AliasesPreserved++
  }
}

$report = @(
  'Playlist html canonical restore report'
  "HTML pages restored: $($stats.HtmlRestored)"
  "Directory redirects written: $($stats.DirRedirectsWritten)"
  "Alias directories preserved: $($stats.AliasesPreserved)"
)

$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report -join [Environment]::NewLine
