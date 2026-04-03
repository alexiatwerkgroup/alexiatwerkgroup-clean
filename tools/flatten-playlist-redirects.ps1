$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$playlistRoot = Join-Path $projectRoot 'playlist'
$reportPath = Join-Path $projectRoot 'PLAYLIST_REDIRECT_FLATTEN_REPORT.txt'

function Get-RedirectTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $html = [System.IO.File]::ReadAllText($Path)
  $patterns = @(
    'http-equiv="refresh" content="[^"]*url=([^"]+)"',
    'location\.replace\("([^"]+)"\)',
    "location\.replace\('([^']+)'\)"
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups[1].Value.Trim()
    }
  }

  return $null
}

function New-RedirectHtml {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFileName
  )

  $escapedTarget = $TargetFileName.Replace('"', '\"')

  @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=$TargetFileName">
  <link rel="canonical" href="https://alexiatwerkgroup.com/playlist/$TargetFileName">
  <meta name="robots" content="noindex,follow">
  <title>Redirecting...</title>
  <script>location.replace("$escapedTarget");</script>
</head>
<body>
  <p>Redirecting to <a href="$TargetFileName">$TargetFileName</a>...</p>
</body>
</html>
"@
}

if (-not (Test-Path $playlistRoot)) {
  throw "Playlist folder not found: $playlistRoot"
}

$files = Get-ChildItem $playlistRoot -File -Filter *.html
$flattened = 0
$report = New-Object System.Collections.Generic.List[string]
$report.Add("Playlist Redirect Flatten Report")
$report.Add("Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("")

foreach ($file in $files) {
  $initialTarget = Get-RedirectTarget -Path $file.FullName
  if (-not $initialTarget) {
    continue
  }

  $visited = New-Object System.Collections.Generic.HashSet[string]
  $currentLeaf = Split-Path $initialTarget -Leaf
  $finalLeaf = $currentLeaf
  $depth = 0

  while ($depth -lt 12 -and -not [string]::IsNullOrWhiteSpace($finalLeaf)) {
    $candidatePath = Join-Path $playlistRoot $finalLeaf
    if (-not (Test-Path $candidatePath)) {
      break
    }

    if ($visited.Contains($finalLeaf)) {
      break
    }

    [void]$visited.Add($finalLeaf)

    $nextTarget = Get-RedirectTarget -Path $candidatePath
    if (-not $nextTarget) {
      break
    }

    $nextLeaf = Split-Path $nextTarget -Leaf
    if ([string]::IsNullOrWhiteSpace($nextLeaf)) {
      break
    }

    $finalLeaf = $nextLeaf
    $depth++
  }

  if ($finalLeaf -and $finalLeaf -ne (Split-Path $initialTarget -Leaf) -and (Test-Path (Join-Path $playlistRoot $finalLeaf))) {
    $redirectHtml = New-RedirectHtml -TargetFileName $finalLeaf
    [System.IO.File]::WriteAllText($file.FullName, $redirectHtml, [System.Text.Encoding]::UTF8)
    $flattened++
    $report.Add("$($file.Name) -> $finalLeaf")
  }
}

$report.Add("")
$report.Add("Redirects flattened: $flattened")
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.Encoding]::UTF8)

Write-Output "Redirects flattened: $flattened"
Write-Output "Report: $reportPath"
