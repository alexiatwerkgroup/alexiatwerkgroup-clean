$ErrorActionPreference = 'Stop'

$root = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE'
$playlistDir = Join-Path $root 'playlist'
$reportPath = Join-Path $root 'PLAYLIST_LINK_NORMALIZATION_REPORT.txt'

$canonical = @{}
Get-ChildItem -Path $playlistDir -Filter '*.html' -File | ForEach-Object {
  $canonical[$_.BaseName.ToLowerInvariant()] = $true
}

$files = Get-ChildItem -Path $root -Recurse -File -Include *.html,*.js,*.xml,*.txt
$filesChanged = 0
$rewrites = 0

foreach ($file in $files) {
  if ($file.FullName -like "$playlistDir\\*") { continue }
  $content = Get-Content -Path $file.FullName -Raw
  $original = $content

  $content = [regex]::Replace(
    $content,
    '(?<prefix>href=["'']/playlist/)(?<slug>[^/"''?#]+)(?<suffix>["''])',
    {
      param($m)
      $slug = $m.Groups['slug'].Value
      $lower = $slug.ToLowerInvariant()
      if ($lower -eq '' -or $lower -eq 'index.html' -or $lower.EndsWith('.html')) {
        return $m.Value
      }
      if ($canonical.ContainsKey($lower)) {
        $script:rewrites++
        return $m.Groups['prefix'].Value + $slug + '.html' + $m.Groups['suffix'].Value
      }
      return $m.Value
    }
  )

  $content = [regex]::Replace(
    $content,
    '(?<prefix>href=["'']playlist/)(?<slug>[^/"''?#]+)(?<suffix>["''])',
    {
      param($m)
      $slug = $m.Groups['slug'].Value
      $lower = $slug.ToLowerInvariant()
      if ($lower -eq '' -or $lower -eq 'index.html' -or $lower.EndsWith('.html')) {
        return $m.Value
      }
      if ($canonical.ContainsKey($lower)) {
        $script:rewrites++
        return $m.Groups['prefix'].Value + $slug + '.html' + $m.Groups['suffix'].Value
      }
      return $m.Value
    }
  )

  if ($content -ne $original) {
    Set-Content -Path $file.FullName -Value $content -NoNewline
    $filesChanged++
  }
}

$report = @(
  "Files scanned: $($files.Count)"
  "Files changed: $filesChanged"
  "Playlist link rewrites: $rewrites"
  "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
)
Set-Content -Path $reportPath -Value $report
Get-Content -Path $reportPath
