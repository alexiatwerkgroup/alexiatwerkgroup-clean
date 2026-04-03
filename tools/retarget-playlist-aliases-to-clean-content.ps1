$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$playlistRoot = Join-Path $projectRoot 'playlist'
$reportPath = Join-Path $projectRoot 'PLAYLIST_CLEAN_TARGET_REPORT.txt'

function Get-RedirectTarget {
  param([string]$Path)

  $html = [System.IO.File]::ReadAllText($Path)
  $patterns = @(
    'http-equiv="refresh" content="[^"]*url=([^"]+)"',
    'location\.replace\("([^"]+)"\)',
    "location\.replace\('([^']+)'\)"
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return (Split-Path $match.Groups[1].Value.Trim() -Leaf)
    }
  }

  return $null
}

function New-RedirectHtml {
  param([string]$TargetFileName)

  $escaped = $TargetFileName.Replace('"', '\"')
  @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=$TargetFileName">
  <link rel="canonical" href="https://alexiatwerkgroup.com/playlist/$TargetFileName">
  <meta name="robots" content="noindex,follow">
  <title>Redirecting...</title>
  <script>location.replace("$escaped");</script>
</head>
<body>
  <p>Redirecting to <a href="$TargetFileName">$TargetFileName</a>...</p>
</body>
</html>
"@
}

function Get-NormalizedName {
  param([string]$FileName)

  $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
  for ($i = 0; $i -lt 2; $i++) {
    try {
      $decoded = [uri]::UnescapeDataString($name)
    } catch {
      $decoded = $name
    }

    if ($decoded -eq $name) { break }
    $name = $decoded
  }

  $name = $name -replace '#u[0-9a-f]{4,6}', '-'
  $name = $name.Normalize([Text.NormalizationForm]::FormD)

  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $name.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($ch)
    }
  }

  $ascii = $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
  $ascii = $ascii -replace '[^\x00-\x7F]', '-'
  $ascii = $ascii -replace "['’]", ''
  $ascii = $ascii -replace '[^a-z0-9]+', '-'
  $ascii = $ascii -replace '-{2,}', '-'
  return $ascii.Trim('-')
}

function Get-Tokens {
  param([string]$FileName)

  $stop = @(
    'html','feat','ft','and','the','with','for','from','dance','centre','center','video',
    'playlist','choreo','choreography','twerk','by'
  )

  $tokens = Get-NormalizedName -FileName $FileName |
    ForEach-Object { $_ -split '-' } |
    Where-Object { $_.Length -ge 3 -and $_ -notin $stop } |
    Select-Object -Unique

  return @($tokens)
}

function Get-CleanScore {
  param([string]$FileName)

  $score = 0
  if ($FileName -match '^[a-z0-9-]+\.html$') { $score += 80 }
  if ($FileName -notmatch '%') { $score += 30 }
  if ($FileName -notmatch '#U[0-9A-Fa-f]{4,6}') { $score += 30 }
  if ($FileName -notmatch '[╨╤├┤┐δσµΩ]') { $score += 30 }
  return $score
}

if (-not (Test-Path $playlistRoot)) {
  throw "Playlist folder not found: $playlistRoot"
}

$files = Get-ChildItem $playlistRoot -File -Filter *.html
$redirectFiles = @()
$contentFiles = @()

foreach ($file in $files) {
  $target = Get-RedirectTarget -Path $file.FullName
  if ($target) {
    $redirectFiles += [pscustomobject]@{
      File = $file
      Target = $target
      Tokens = Get-Tokens -FileName $file.Name
    }
  } else {
    $contentFiles += [pscustomobject]@{
      File = $file
      Tokens = Get-Tokens -FileName $file.Name
      CleanScore = Get-CleanScore -FileName $file.Name
    }
  }
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Playlist Clean Target Report")
$report.Add("Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("")

$updated = 0

foreach ($item in $redirectFiles) {
  if ($item.Tokens.Count -lt 2) {
    continue
  }

  $matches = foreach ($candidate in $contentFiles) {
    $shared = @($item.Tokens | Where-Object { $_ -in $candidate.Tokens }).Count
    if ($shared -lt 2) {
      continue
    }

    [pscustomobject]@{
      Name = $candidate.File.Name
      Shared = $shared
      CleanScore = $candidate.CleanScore
      Length = $candidate.File.Length
    }
  }

  $best = $matches |
    Sort-Object @{ Expression = { $_.Shared }; Descending = $true }, `
                @{ Expression = { $_.CleanScore }; Descending = $true }, `
                @{ Expression = { $_.Length }; Descending = $true } |
    Select-Object -First 1

  if (-not $best) {
    continue
  }

  if ($best.Name -ne $item.Target) {
    $html = New-RedirectHtml -TargetFileName $best.Name
    [System.IO.File]::WriteAllText($item.File.FullName, $html, [System.Text.Encoding]::UTF8)
    $updated++
    $report.Add("$($item.File.Name) -> $($best.Name) (was $($item.Target), shared tokens: $($best.Shared))")
  }
}

$report.Add("")
$report.Add("Aliases retargeted to cleaner content pages: $updated")
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.Encoding]::UTF8)

Write-Output "Aliases retargeted: $updated"
Write-Output "Report: $reportPath"
