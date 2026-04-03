$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE'
$playlistDir = Join-Path $root 'playlist'
$reportPath = Join-Path $root 'PLAYLIST_SURGICAL_FIX_REPORT.txt'

$htmlFiles = Get-ChildItem -Path $playlistDir -Filter '*.html' -File
$canonicalNames = @{}
foreach ($file in $htmlFiles) {
  $canonicalNames[$file.BaseName] = $true
}

$aliasRedirectsFixed = 0
$autoplayCallsDisabled = 0
$autoplayRedirectsDisabled = 0
$playlistIndexLinksFixed = 0
$filesChanged = 0

foreach ($file in $htmlFiles) {
  $content = Get-Content -Path $file.FullName -Raw
  $original = $content

  if ($file.Name -ieq 'index.html') {
    $content = [regex]::Replace(
      $content,
      'href=(["''])([^/"''#?:]+)\1',
      {
        param($m)
        $quote = $m.Groups[1].Value
        $target = $m.Groups[2].Value
        if (
          $target -ne 'index.html' -and
          $canonicalNames.ContainsKey($target) -and
          -not $target.EndsWith('.html')
        ) {
          $script:playlistIndexLinksFixed++
          return "href=$quote$target.html$quote"
        }
        return $m.Value
      }
    )
  } elseif ($content -match '<title>Redirecting\.\.\.</title>') {
    $content = [regex]::Replace(
      $content,
      '(?<prefix>url=\./)(?<target>[^"''<>?#]+)(?<suffix>["''])',
      {
        param($m)
        $target = $m.Groups['target'].Value
        if (
          -not $target.EndsWith('.html') -and
          $canonicalNames.ContainsKey($target)
        ) {
          $script:aliasRedirectsFixed++
          return $m.Groups['prefix'].Value + $target + '.html' + $m.Groups['suffix'].Value
        }
        return $m.Value
      }
    )
    $content = [regex]::Replace(
      $content,
      '(?<prefix>location\.replace\("\./)(?<target>[^"''<>?#]+)(?<suffix>"\))',
      {
        param($m)
        $target = $m.Groups['target'].Value
        if (
          -not $target.EndsWith('.html') -and
          $canonicalNames.ContainsKey($target)
        ) {
          $script:aliasRedirectsFixed++
          return $m.Groups['prefix'].Value + $target + '.html' + $m.Groups['suffix'].Value
        }
        return $m.Value
      }
    )
  } else {
    $content = [regex]::Replace(
      $content,
      '(?m)^\s*initAutoplayNext\(".*?"\);\s*\r?\n?',
      {
        param($m)
        $script:autoplayCallsDisabled++
        return ''
      }
    )

    $content = [regex]::Replace(
      $content,
      'location\.href\s*=\s*next\.filename;',
      {
        param($m)
        $script:autoplayRedirectsDisabled++
        return '// autoplay redirect disabled to prevent forced navigation'
      }
    )
  }

  if ($content -ne $original) {
    Set-Content -Path $file.FullName -Value $content -NoNewline
    $filesChanged++
  }
}

$report = @(
  "Playlist files scanned: $($htmlFiles.Count)"
  "Files changed: $filesChanged"
  "Playlist index links normalized to .html: $playlistIndexLinksFixed"
  "Alias redirects retargeted to .html: $aliasRedirectsFixed"
  "Autoplay init calls removed: $autoplayCallsDisabled"
  "Autoplay forced redirects disabled: $autoplayRedirectsDisabled"
  "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)

Set-Content -Path $reportPath -Value $report
Get-Content -Path $reportPath
