# Shared updater functions. Dot-sourcing this file performs no network/write/restart.
function ConvertTo-SebiVersion {
  param([string]$Text)
  if ($Text -notmatch '^(0|[1-9][0-9]{0,7})\.(0|[1-9][0-9]{0,7})\.(0|[1-9][0-9]{0,7})$') {
    throw "Version SebiLink invalida: $Text"
  }
  return [version]$Text
}

function Get-SebiSource {
  param([string]$GameDir)
  $config = Get-Content -LiteralPath (Join-Path $GameDir 'multiplayer\updates\update-source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  [void](ConvertTo-SebiVersion $config.version)
  if ($config.game_id -ne 'pokemon-z' -or $config.package_path -ne 'SebiLink - Pokemon Z') { throw 'Carpeta de juego no admitida.' }
  if ($config.repository -notmatch '^https://github\.com/([A-Za-z0-9_-]+)/([A-Za-z0-9_.-]+)/?$') { throw 'Repositorio GitHub invalido.' }
  $config | Add-Member NoteProperty owner $Matches[1] -Force
  $config | Add-Member NoteProperty repo $Matches[2] -Force
  if ($config.branch -notmatch '^[A-Za-z0-9_./-]+$') { throw 'Rama GitHub invalida.' }
  return $config
}

function Get-SebiReadmeVersion {
  param([string]$Readme, [string]$PackagePath = 'SebiLink - Pokemon Z')
  $block = [regex]::Match($Readme, '(?s)<!-- SEBILINK_VERSIONS_BEGIN -->(.*?)<!-- SEBILINK_VERSIONS_END -->')
  if (!$block.Success) { throw 'El README de GitHub todavia no tiene la tabla de versiones SebiLink.' }
  $versions = @()
  foreach ($line in ($block.Groups[1].Value -split '\r?\n')) {
    $cells = $line.Split('|')
    if ($cells.Count -ne 5) { continue }
    # Backticks are Markdown decoration only; numeric version is read from README.
    if ($cells[3].Trim().Trim([char]96) -eq $PackagePath) {
      $value = $cells[2].Trim().Trim([char]96)
      [void](ConvertTo-SebiVersion $value)
      $versions += $value
    }
  }
  if ($versions.Count -ne 1) { throw 'El README debe tener exactamente una version de Pokemon Z.' }
  return $versions[0]
}

function Invoke-SebiText {
  param([string]$Uri)
  $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15 -Headers @{'User-Agent'='SebiLink-PokemonZ-Updater'; 'Cache-Control'='no-cache'}
  if ($response.RawContentLength -gt 524288) { throw 'Respuesta de actualizacion demasiado grande.' }
  return [string]$response.Content
}

function Get-SebiRemote {
  param([object]$Source)
  $branch = [Uri]::EscapeDataString([string]$Source.branch)
  $commitInfo = Invoke-SebiText "https://api.github.com/repos/$($Source.owner)/$($Source.repo)/git/ref/heads/$branch" | ConvertFrom-Json
  $commit = [string]$commitInfo.object.sha
  if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'GitHub no devolvio un commit valido.' }
  $base = "https://raw.githubusercontent.com/$($Source.owner)/$($Source.repo)/$commit"
  $version = Get-SebiReadmeVersion (Invoke-SebiText "$base/README.md") $Source.package_path
  return [PSCustomObject]@{version=$version; commit=$commit; raw_base=$base}
}

function Assert-SebiOwnedPath {
  param([string]$Path)
  if ($Path.Length -gt 220 -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path -match '[:*?"<>|]' -or $Path -match '[\x00-\x1f]') { throw "Ruta no admitida: $Path" }
  foreach ($part in $Path.Split('/')) {
    if ($part -in @('', '.', '..') -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Ruta no admitida: $Path" }
  }
  if ($Path -in @('README.md', '.gitignore', 'mkxp.json')) { return }
  if ($Path -match '^(?i:multiplayer)/' -and $Path -match '\.(?i:rb|ps1|js|txt|json|md)$' -and $Path -notmatch '/(?i:runtime|backups)/') { return }
  if ($Path -match '^tools/randomizer/[A-Za-z0-9_.-]+\.(?:rb|md)$') { return }
  throw "El actualizador solo puede escribir archivos del complemento: $Path"
}

function Resolve-SebiChild {
  param([string]$Root, [string]$Relative)
  $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
  $target = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
  if (!$target.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta fuera del directorio autorizado.' }
  $probe = $target
  while ($probe -and $probe.Length -ge $rootPath.Length) {
    if (Test-Path -LiteralPath $probe) {
      if ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No se actualiza a traves de enlaces/junctions.' }
    }
    if ($probe -eq $rootPath) { break }
    $probe = Split-Path $probe -Parent
  }
  return $target
}

function Assert-SebiManifest {
  param([object]$Manifest, [string]$Version)
  if ($Manifest.package -ne 'SebiLink - Pokemon Z' -or $Manifest.version -ne $Version) { throw 'La version del manifiesto no coincide con el README.' }
  $entries = @($Manifest.files)
  if ($entries.Count -lt 4 -or $entries.Count -gt 512) { throw 'Cantidad de archivos no admitida.' }
  $seen = @{}
  $total = 0L
  foreach ($entry in $entries) {
    $path = [string]$entry.path
    Assert-SebiOwnedPath $path
    if ($seen.ContainsKey($path)) { throw "Ruta duplicada: $path" }
    $seen[$path] = $true
    if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or $entry.bytes -lt 0 -or $entry.bytes -gt 16777216) { throw 'Integridad/tamano de archivo no admitido.' }
    $total += [long]$entry.bytes
  }
  if ($total -gt 67108864) { throw 'El complemento supera el limite de descarga.' }
  foreach ($path in @('mkxp.json','multiplayer/SebiVisualMultiplayer.rb','multiplayer/SebiLinkBootstrap.rb','multiplayer/SebiRandomizer.rb','multiplayer/SebiUpdater.rb','multiplayer/updates/update-source.json','multiplayer/updates/SebiUpdateCore.ps1','multiplayer/updates/SebiUpdateWorker.ps1')) {
    if (!$seen.ContainsKey($path)) { throw "Falta un archivo obligatorio: $path" }
  }
}

function Get-SebiRawUrl {
  param([string]$Base, [string]$Folder, [string]$Relative)
  $parts = ($Folder + '/' + $Relative).Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }
  return $Base + '/' + ($parts -join '/')
}

function Save-SebiDownload {
  param([string]$Uri, [string]$Path)
  [void](New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force)
  Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -TimeoutSec 30 -Headers @{'User-Agent'='SebiLink-PokemonZ-Updater'} | Out-Null
}

function Get-SebiStage {
  param([object]$Source, [object]$Remote, [string]$JobDir)
  $stage = Resolve-SebiChild $JobDir 'stage'
  [void](New-Item -ItemType Directory -Path $stage -Force)
  $manifestText = Invoke-SebiText (Get-SebiRawUrl $Remote.raw_base $Source.package_path 'MANIFEST.json')
  $manifest = $manifestText | ConvertFrom-Json
  Assert-SebiManifest $manifest $Remote.version
  foreach ($entry in @($manifest.files)) {
    $path = Resolve-SebiChild $stage $entry.path
    Save-SebiDownload (Get-SebiRawUrl $Remote.raw_base $Source.package_path $entry.path) $path
    if ((Get-Item -LiteralPath $path).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Descarga incompleta o modificada: $($entry.path)" }
  }
  $newSource = Get-SebiSource $stage
  if ($newSource.version -ne $Remote.version -or $newSource.repository -ne $Source.repository -or $newSource.package_path -ne $Source.package_path) { throw 'El paquete descargado no corresponde al juego/repositorio seleccionado.' }
  [IO.File]::WriteAllText((Join-Path $stage 'MANIFEST.json'), $manifestText, (New-Object Text.UTF8Encoding($false)))
  return $stage
}

function ConvertFrom-SebiJsonComments {
  param([string]$Text)
  # MKXP accepts comments and trailing commas. Never strip // inside JSON strings.
  $clean = New-Object Text.StringBuilder
  $quoted = $false; $escaped = $false; $comment = $false
  for ($i=0; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]
    if ($comment) { if ($c -eq [char]10) { $comment=$false; [void]$clean.Append($c) }; continue }
    if ($quoted) {
      [void]$clean.Append($c)
      if ($escaped) { $escaped=$false } elseif ($c -eq '\') { $escaped=$true } elseif ($c -eq '"') { $quoted=$false }
      continue
    }
    if ($c -eq '"') { $quoted=$true; [void]$clean.Append($c); continue }
    if ($c -eq '/' -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq '/') { $comment=$true; $i++; continue }
    if ($c -eq ',') {
      $next = $i+1
      while ($next -lt $Text.Length) {
        if ([char]::IsWhiteSpace($Text[$next])) { $next++; continue }
        if ($Text[$next] -eq '/' -and $next+1 -lt $Text.Length -and $Text[$next+1] -eq '/') {
          while ($next -lt $Text.Length -and $Text[$next] -ne [char]10) { $next++ }
          continue
        }
        break
      }
      if ($next -lt $Text.Length -and $Text[$next] -in @('}',']')) { continue }
    }
    [void]$clean.Append($c)
  }
  return $clean.ToString() | ConvertFrom-Json
}

function Merge-SebiMkxp {
  param([string]$Text)
  $config = ConvertFrom-SebiJsonComments $Text
  $scripts = @()
  if ($null -ne $config.PSObject.Properties['preloadScript']) { $scripts = @($config.preloadScript) }
  if ($scripts -notcontains 'multiplayer/SebiLinkBootstrap.rb') { $scripts += 'multiplayer/SebiLinkBootstrap.rb' }
  $config | Add-Member NoteProperty preloadScript $scripts -Force
  $config | Add-Member NoteProperty enableReset $false -Force
  return $config | ConvertTo-Json -Depth 30
}

function Write-SebiAtomicFile {
  param([string]$GameDir, [string]$Relative, [byte[]]$Bytes)
  $target = Resolve-SebiChild $GameDir $Relative
  [void](New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force)
  $temporary = Resolve-SebiChild $GameDir ($Relative + '.sebilink-update.tmp')
  try {
    [IO.File]::WriteAllBytes($temporary, $Bytes)
    if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, [NullString]::Value) } else { [IO.File]::Move($temporary, $target) }
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  }
}

function Install-SebiStage {
  param([string]$GameDir, [string]$Stage, [string]$JobDir, [string]$Version)
  $manifest = Get-Content -LiteralPath (Join-Path $Stage 'MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert-SebiManifest $manifest $Version
  # Reverify staging immediately before writing; the game has already exited.
  foreach ($entry in @($manifest.files)) {
    $file = Resolve-SebiChild $Stage $entry.path
    if ((Get-FileHash -LiteralPath $file).Hash -ne $entry.sha256 -or (Get-Item -LiteralPath $file).Length -ne $entry.bytes) { throw 'La copia temporal ha cambiado.' }
  }
  $paths = @($manifest.files | ForEach-Object { [string]$_.path })
  $obsolete = @()
  $localManifest = Resolve-SebiChild $GameDir 'MANIFEST.json'
  if (Test-Path -LiteralPath $localManifest) {
    $old = Get-Content -LiteralPath $localManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($old.package -ne 'SebiLink - Pokemon Z') { throw 'Manifiesto local incompatible.' }
    foreach ($entry in @($old.files)) {
      Assert-SebiOwnedPath $entry.path
      if ($paths -notcontains $entry.path) { $obsolete += [string]$entry.path }
    }
  }
  $all = @($paths + $obsolete + 'MANIFEST.json' | Select-Object -Unique)
  $backupRoot = Resolve-SebiChild $JobDir 'backup'
  $plan = @()
  # Back up every touched file before copying any replacement.
  foreach ($relative in $all) {
    $target = Resolve-SebiChild $GameDir $relative
    $backup = Resolve-SebiChild $backupRoot $relative
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    if ((Test-Path -LiteralPath $target) -and !$exists) { throw "Un directorio ocupa el archivo: $relative" }
    if ($exists) {
      [void](New-Item -ItemType Directory -Path (Split-Path $backup -Parent) -Force)
      Copy-Item -LiteralPath $target -Destination $backup -Force
    }
    $plan += [PSCustomObject]@{path=$relative; existed=$exists; backup=$backup}
  }
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $JobDir 'backup-plan.json'), ($plan | ConvertTo-Json -Depth 5), $utf8)
  try {
    # Commit the installed version last, so a failed update never advertises success.
    $ordered = @($paths | Where-Object { $_ -ne 'multiplayer/updates/update-source.json' })
    $ordered += 'MANIFEST.json'
    $ordered += 'multiplayer/updates/update-source.json'
    foreach ($relative in $ordered) {
      $bytes = [IO.File]::ReadAllBytes((Resolve-SebiChild $Stage $relative))
      if ($relative -eq 'mkxp.json' -and (Test-Path -LiteralPath (Join-Path $GameDir $relative))) {
        $bytes = $utf8.GetBytes((Merge-SebiMkxp ([IO.File]::ReadAllText((Join-Path $GameDir $relative)))))
      }
      Write-SebiAtomicFile $GameDir $relative $bytes
    }
    foreach ($relative in $obsolete) {
      $target = Resolve-SebiChild $GameDir $relative
      if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    }
  } catch {
    $failure = $_
    foreach ($entry in $plan) {
      $target = Resolve-SebiChild $GameDir $entry.path
      if ($entry.existed) {
        if (!(Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $entry.backup).Hash) {
          Write-SebiAtomicFile $GameDir $entry.path ([IO.File]::ReadAllBytes($entry.backup))
        }
      } elseif (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    }
    throw "La actualizacion fallo y se ha restaurado el complemento anterior: $($failure.Exception.Message)"
  }
}
