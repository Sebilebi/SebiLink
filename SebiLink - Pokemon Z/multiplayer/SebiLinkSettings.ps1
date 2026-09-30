# Shared player INI access for native SebiLink windows; no work when dot-sourced.
function Get-SebiSetting {
  param([string]$Path, [string]$Name, [string]$Default = '')
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $Default }
  foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
    if ($line.Trim() -match '^[#;\[]') { continue }
    $pair = $line -split '=', 2
    if ($pair.Length -eq 2 -and $pair[0].Trim() -ieq $Name) { return $pair[1].Trim() }
  }
  return $Default
}

function Get-SebiSettingBool {
  param([string]$Path, [string]$Name, [bool]$Default = $false)
  $value = (Get-SebiSetting $Path $Name ([string]$Default)).ToLowerInvariant()
  if ($value -in @('true', '1', 'yes', 'on', 'si')) { return $true }
  if ($value -in @('false', '0', 'no', 'off')) { return $false }
  return $Default
}

function Set-SebiSetting {
  param([string]$Path, [string]$Name, [string]$Value)
  if ($Name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Clave INI invalida.' }
  $Name = $Name.ToLowerInvariant()
  $Value = $Value -replace '[\r\n]', ' '
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  $lockPath = $Path + '.lock'
  $deadline = [DateTime]::UtcNow.AddSeconds(2)
  $lock = $null
  try {
    while ($null -eq $lock) {
      try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
      catch [IO.IOException] {
        if ([IO.File]::Exists($lockPath) -and ([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($lockPath)).TotalSeconds -gt 30) {
          try { [IO.File]::Delete($lockPath) } catch {}
        }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'No se pudo bloquear sebilink.ini.' }
        Start-Sleep -Milliseconds 20
      }
    }
    $values = @{}
    if ([IO.File]::Exists($Path)) {
      foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        if ($line.Trim() -match '^[#;\[]') { continue }
        $pair = $line -split '=', 2
        if ($pair.Length -eq 2) { $values[$pair[0].Trim().ToLowerInvariant()] = $pair[1].Trim() }
      }
    }
    $values[$Name] = $Value
    if ($values.ContainsKey('config_seeded_keys')) {
      $values['config_seeded_keys'] = @($values['config_seeded_keys'] -split ',' | Where-Object { $_ -ne $Name -and $_ -ne '' } | Sort-Object -Unique) -join ','
    }
    # Leave the migration marker to Ruby, which imports legacy network settings.
    $lines = @('# SebiLink player settings.', '# control_0..15: Abajo, Izquierda, Derecha, Arriba, Aceptar C, Aceptar Enter, Cancelar X, Cancelar Esc, Correr, Turbo, Objeto, Pag abajo, Pag arriba, Curar, Vuelo, Radar.', '# randomizer_regions: 1 Kanto, 2 Johto, 3 Hoenn, 4 Sinnoh, 5 Teselia, 6 Kalos, 7 Alola, 8 Galar/Hisui, 9 Paldea.') + @($values.Keys | Sort-Object | ForEach-Object { $_ + '=' + $values[$_] })
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllLines($tmp, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $Path) }
  } finally {
    if ($null -ne $lock) { $lock.Dispose(); [IO.File]::Delete($lockPath) }
  }
}
