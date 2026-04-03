$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$playlistRoot = Join-Path $projectRoot 'playlist'
$reportPath = Join-Path $projectRoot 'PLAYLIST_ALIAS_AUDIT.txt'

if (-not (Test-Path $playlistRoot)) {
  throw "Playlist folder not found: $playlistRoot"
}

function Get-NormalizedSlug {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FileName
  )

  $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()

  for ($i = 0; $i -lt 2; $i++) {
    try {
      $decoded = [uri]::UnescapeDataString($base)
    } catch {
      $decoded = $base
    }

    if ($decoded -eq $base) {
      break
    }

    $base = $decoded
  }

  $base = $base -replace '#u[0-9a-f]{4,6}', '-'
  $base = $base.Normalize([Text.NormalizationForm]::FormD)

  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $base.ToCharArray()) {
    $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($ch)
    }
  }

  $ascii = $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
  $ascii = $ascii -replace '[^\x00-\x7F]', '-'
  $ascii = $ascii -replace '&', ' and '
  $ascii = $ascii -replace "['’]", ''
  $ascii = $ascii -replace '[^a-z0-9]+', '-'
  $ascii = $ascii -replace '-{2,}', '-'
  $ascii = $ascii.Trim('-')

  if ([string]::IsNullOrWhiteSpace($ascii)) {
    $ascii = 'playlist-item'
  }

  return "$ascii.html"
}

function Get-FileHead {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return [System.IO.File]::ReadAllText($Path).Substring(0, [Math]::Min(900, (Get-Item $Path).Length))
}

function Get-RedirectTarget {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $head = Get-FileHead -Path $Path

  $patterns = @(
    'url=([^"''>]+)',
    'location\.replace\("([^"]+)"\)',
    "location\.replace\('([^']+)'\)"
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($head, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      return $match.Groups[1].Value.Trim()
    }
  }

  return $null
}

function Get-CandidateScore {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]$File
  )

  $score = 0
  $name = $File.Name

  if ($name -match '^[a-z0-9-]+\.html$') { $score += 80 }
  if ($name -notmatch '%') { $score += 35 }
  if ($name -notmatch '#U[0-9A-Fa-f]{4,6}') { $score += 30 }
  if ($name -notmatch '[╨╤├┤┐δσµΩ]') { $score += 30 }
  if ($name -notmatch '^-') { $score += 10 }
  if ($name -match '[a-z]{3,}-[a-z]{3,}') { $score += 10 }

  $target = Get-RedirectTarget -Path $File.FullName
  if ($null -eq $target) {
    $score += 120
  } else {
    $score -= 80
  }

  $score += [Math]::Min(40, [Math]::Floor($File.Length / 2000))

  return [int]$score
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
  <title>Redirecting...</title>
  <script>location.replace("$escapedTarget");</script>
</head>
<body>
  <p>Redirecting to <a href="$TargetFileName">$TargetFileName</a>...</p>
</body>
</html>
"@
}

$files = Get-ChildItem $playlistRoot -File -Filter *.html
$groups = $files | Group-Object { Get-NormalizedSlug -FileName $_.Name } | Sort-Object Count -Descending

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Playlist Alias Audit")
$report.Add("Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("Playlist folder: $playlistRoot")
$report.Add("")

$rewritten = 0
$createdAliases = 0
$duplicateGroups = 0

foreach ($group in $groups) {
  if ($group.Count -lt 2) {
    continue
  }

  $duplicateGroups++

  $canonical = $group.Group |
    Sort-Object @{ Expression = { Get-CandidateScore -File $_ }; Descending = $true }, `
                @{ Expression = { $_.Length }; Descending = $true }, `
                @{ Expression = { $_.Name.Length }; Descending = $true } |
    Select-Object -First 1

  $report.Add("Canonical: $($canonical.Name)")
  foreach ($item in $group.Group) {
    $target = Get-RedirectTarget -Path $item.FullName
    $kind = if ($null -eq $target) { 'content' } else { "redirect->$target" }
    $report.Add("  - $($item.Name) [$kind]")
  }

  foreach ($item in $group.Group) {
    if ($item.FullName -eq $canonical.FullName) {
      continue
    }

    $redirectHtml = New-RedirectHtml -TargetFileName $canonical.Name
    [System.IO.File]::WriteAllText($item.FullName, $redirectHtml, [System.Text.Encoding]::UTF8)
    $rewritten++
  }

  $cleanAliasPath = Join-Path $playlistRoot $group.Name
  if (-not (Test-Path $cleanAliasPath)) {
    $aliasHtml = New-RedirectHtml -TargetFileName $canonical.Name
    [System.IO.File]::WriteAllText($cleanAliasPath, $aliasHtml, [System.Text.Encoding]::UTF8)
    $createdAliases++
    $report.Add("  + created clean alias: $($group.Name)")
  }

  $report.Add("")
}

$report.Add("Summary")
$report.Add("Duplicate groups consolidated: $duplicateGroups")
$report.Add("Existing files rewritten as direct redirects: $rewritten")
$report.Add("New clean alias files created: $createdAliases")

[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.Encoding]::UTF8)

Write-Output "Duplicate groups consolidated: $duplicateGroups"
Write-Output "Existing files rewritten as direct redirects: $rewritten"
Write-Output "New clean alias files created: $createdAliases"
Write-Output "Report: $reportPath"
