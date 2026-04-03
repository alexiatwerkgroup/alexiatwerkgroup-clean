$ErrorActionPreference = 'Stop'

$src = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE'
$zip = 'C:\Users\Claudio\OneDrive\Desktop\Web\alexia_site_v22_fixed_time_modal_live_SAFE-clean.zip'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $zip) {
  Remove-Item -LiteralPath $zip -Force
}

$files = Get-ChildItem -Path $src -Recurse -File
$base = (Resolve-Path $src).Path

$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
try {
  $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($file in $files) {
      $full = $file.FullName
      $relative = $full.Substring($base.Length).TrimStart('\')
      $entryName = ($relative -replace '\\','/')
      $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
      $entryStream = $entry.Open()
      try {
        $input = [System.IO.File]::OpenRead($full)
        try {
          $input.CopyTo($entryStream)
        } finally {
          $input.Dispose()
        }
      } finally {
        $entryStream.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
  }
} finally {
  $fs.Dispose()
}

$samplePath = 'playlist/jazz-funk-kids-animal-shkola-tantsev-street-project-volzhskii.html'
$zipRead = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  $entry = $zipRead.Entries | Where-Object { $_.FullName -eq $samplePath } | Select-Object -First 1
  @(
    "Files zipped: $($files.Count)"
    "Zip path: $zip"
    "Zip bytes: $((Get-Item $zip).Length)"
    "Sample entry found: $([bool]$entry)"
    "Sample entry: $samplePath"
  )
} finally {
  $zipRead.Dispose()
}
