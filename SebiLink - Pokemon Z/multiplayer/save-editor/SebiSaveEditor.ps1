Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:BaseDir = $PSScriptRoot
$script:GameDir = Split-Path (Split-Path $script:BaseDir -Parent) -Parent
$script:GameExePath = Join-Path $script:GameDir "Game.exe"
$script:GameIcon = $null

function Get-SebiLinkConfigRoot {
  $profile = $env:USERPROFILE
  if ([string]::IsNullOrWhiteSpace($profile)) {
    $profile = [Environment]::GetFolderPath("UserProfile")
  }
  if ([string]::IsNullOrWhiteSpace($profile)) {
    return (Join-Path $script:GameDir "SebiLinkConfig")
  }
  return (Join-Path (Join-Path (Join-Path $profile "Saved Games") "Pokemon Z") "SebiLinkConfig")
}

function Copy-SebiLinkLegacyRuntime {
  param([string]$OldPath, [string]$NewPath)
  try {
    if ([string]::IsNullOrWhiteSpace($OldPath) -or [string]::IsNullOrWhiteSpace($NewPath)) { return }
    if ((Test-Path -LiteralPath $NewPath) -or !(Test-Path -LiteralPath $OldPath)) { return }
    $parent = Split-Path -Parent $NewPath
    if (!(Test-Path -LiteralPath $parent)) {
      [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    Copy-Item -LiteralPath $OldPath -Destination $NewPath -Recurse -Force
  } catch {
  }
}

$script:SebiLinkConfigRoot = Get-SebiLinkConfigRoot
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'SebiLinkSettings.ps1')
$script:IniPath = Join-Path $script:SebiLinkConfigRoot 'sebilink.ini'
if (!(Test-Path -LiteralPath $script:SebiLinkConfigRoot)) {
  [void](New-Item -ItemType Directory -Path $script:SebiLinkConfigRoot -Force)
}
$script:RuntimeDir = Join-Path $script:SebiLinkConfigRoot "save-editor\runtime"
Copy-SebiLinkLegacyRuntime -OldPath (Join-Path $script:BaseDir "runtime") -NewPath $script:RuntimeDir
$script:StatePath = Join-Path $script:RuntimeDir "state.json"
$script:DataPath = Join-Path $script:RuntimeDir "data.json"
$script:CommandPath = Join-Path $script:RuntimeDir "commands.txt"
$script:ResultPath = Join-Path $script:RuntimeDir "last_result.json"
$script:AlivePath = Join-Path $script:RuntimeDir "window_alive.txt"
$script:EditTargetPath = Join-Path $script:RuntimeDir "edit_target.txt"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:State = $null
$script:Data = $null
$script:SelectedPokemon = $null
$script:LoadingUi = $false
$script:Dirty = $false
$script:PendingUntil = [DateTime]::MinValue
$script:PokemonIconCache = @{}
$script:ItemIconCache = @{}
$script:BallIconCache = @{}
$script:BagPocketIconCache = @{}
$script:AchievementIconCache = @{}
$script:TypeIconCache = @{}
$script:CategoryIconCache = @{}
$script:MetricIconCache = @{}
$script:BlankIcon = $null
$script:StatDisplayToRaw = @(0, 1, 2, 4, 5, 3)
$script:LastKnownBagEntries = @()
$script:LearnableMoveIds = @{}
$script:CurrentMoveIds = @{}
$script:PbsCompatibilityCache = $null
$script:PbsAbilityCache = $null
$script:PostCommandTimer = $null
$script:AliveTimer = $null
$script:PostCommandSeq = ""
$script:PostCommandPolls = 0
$script:LastSavePendingCount = 0
$script:PendingCommands = New-Object System.Collections.ArrayList
$script:PartySlots = @()
$script:PCSlots = @()
$script:HexPartySlots = @()
$script:HexBoxSlots = @()
$script:SelectedSlotTag = $null
$script:DraggedSlotTag = $null
$script:DraggedDraftValues = $null
$script:PendingDragTag = $null
$script:PendingDragPoint = $null
$script:PendingDraftPoint = $null
$script:HistoryStates = New-Object System.Collections.ArrayList
$script:HistoryIndex = -1
$script:HistoryRestoring = $false
$script:HistoryListUpdating = $false
$script:HistoryTimer = $null
$script:HistoryPendingLabel = ""
$script:HistoryPendingCategory = ""
$script:HistoryWindow = $null
$script:HistoryListBox = $null
$script:ModifiedPokemonList = $null
$script:ModifiedPokemonHistoryIndexes = @()
$script:LastHistoryShortcutTime = [DateTime]::MinValue
$script:LastHistoryShortcutAction = ""
$script:SlotMenuTag = $null
$script:SlotContextMenu = $null
$script:SpeciesCombo = $null
$script:ItemCombo = $null
$script:NatureCombo = $null
$script:AbilityCombo = $null
$script:AbilityDescriptionBox = $null
$script:StatusCombo = $null
$script:GenderCombo = $null
$script:PokeBallCombo = $null
$script:MoveCombos = @()
$script:MoveDetailLabels = @()
$script:MoveDetailsBox = $null
$script:ClosingNotified = $false
$script:CreateSpeciesCombo = $null
$script:BaseStatLabels = @()
$script:ActualStatLabels = @()
$script:NatureUpLabel = $null
$script:NatureDownLabel = $null
$script:NatureStatNames = @("Atk", "Def", "Spe", "SpA", "SpD")
$script:ToolTip = New-Object System.Windows.Forms.ToolTip
$script:ToolTip.AutoPopDelay = 9000
$script:ToolTip.InitialDelay = 450
$script:ToolTip.ReshowDelay = 120
$script:ToolTip.ShowAlways = $true

try {
  if (Test-Path -LiteralPath $script:GameExePath) {
    $script:GameIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:GameExePath)
  }
} catch {
  $script:GameIcon = $null
}

if (!(Test-Path -LiteralPath $script:RuntimeDir)) {
  New-Item -ItemType Directory -Path $script:RuntimeDir -Force | Out-Null
}

function Read-JsonFile {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { return $null }
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $stream = $null
    $reader = $null
    try {
      $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      $reader = New-Object System.IO.StreamReader($stream, $script:Utf8NoBom, $true)
      $text = $reader.ReadToEnd()
      if (![string]::IsNullOrWhiteSpace($text)) {
        return $text | ConvertFrom-Json
      }
    } catch {
      if ($attempt -ge 7) { return $null }
    } finally {
      if ($null -ne $reader) { $reader.Dispose() }
      elseif ($null -ne $stream) { $stream.Dispose() }
    }
    Start-Sleep -Milliseconds 40
  }
  return $null
}

function Read-TextFileShared {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { return "" }
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $stream = $null
    $reader = $null
    try {
      $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      $reader = New-Object System.IO.StreamReader($stream, $script:Utf8NoBom, $true)
      return $reader.ReadToEnd()
    } catch {
      if ($attempt -ge 7) { return "" }
    } finally {
      if ($null -ne $reader) { $reader.Dispose() }
      elseif ($null -ne $stream) { $stream.Dispose() }
    }
    Start-Sleep -Milliseconds 40
  }
  return ""
}

function Get-JsonArrayText {
  param([string]$Text, [string]$PropertyName)
  if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($PropertyName)) { return "" }
  $needle = ([string][char]34) + $PropertyName + ([string][char]34) + ":"
  $idx = $Text.IndexOf($needle, [System.StringComparison]::Ordinal)
  if ($idx -lt 0) { return "" }
  $start = $Text.IndexOf("[", $idx + $needle.Length, [System.StringComparison]::Ordinal)
  if ($start -lt 0) { return "" }
  $depth = 0
  $inString = $false
  $escape = $false
  for ($i = $start; $i -lt $Text.Length; $i++) {
    $ch = $Text[$i]
    $code = [int][char]$ch
    if ($inString) {
      if ($escape) {
        $escape = $false
      } elseif ($code -eq 92) {
        $escape = $true
      } elseif ($code -eq 34) {
        $inString = $false
      }
      continue
    }
    if ($code -eq 34) {
      $inString = $true
    } elseif ($code -eq 91) {
      $depth++
    } elseif ($code -eq 93) {
      $depth--
      if ($depth -eq 0) {
        return $Text.Substring($start, ($i - $start + 1))
      }
    }
  }
  return ""
}

function Get-ValidBagEntries {
  param($Bag)
  if ($null -eq $Bag) { return @() }
  $ret = New-Object System.Collections.ArrayList
  foreach ($entry in @($Bag)) {
    if ($null -eq $entry) { continue }
    $idValue = $null
    if ($entry -is [System.Collections.IDictionary]) {
      if ($entry.Contains("id")) { $idValue = $entry["id"] }
      elseif ($entry.Contains("ID")) { $idValue = $entry["ID"] }
    } else {
      $prop = $entry.PSObject.Properties["id"]
      if ($null -eq $prop) { $prop = $entry.PSObject.Properties["ID"] }
      if ($null -ne $prop) { $idValue = $prop.Value }
      elseif ($entry.PSObject.Properties.Match("id").Count -gt 0) { $idValue = $entry.id }
    }
    try {
      if ([int]$idValue -gt 0) { [void]$ret.Add($entry) }
    } catch {
    }
  }
  return @($ret)
}

function Get-BagEntriesFromStateFile {
  param([string]$Path)
  $entries = @()
  $state = Read-JsonFile $Path
  if ($null -ne $state) {
    $entries = @(Get-ValidBagEntries -Bag $state.bag)
    if ($entries.Count -gt 0) { return @($entries) }
  }
  $text = Read-TextFileShared $Path
  $bagText = Get-JsonArrayText $text "bag"
  if (![string]::IsNullOrWhiteSpace($bagText)) {
    try {
      $rawEntries = $bagText | ConvertFrom-Json
      $entries = @(Get-ValidBagEntries -Bag $rawEntries)
      if ($entries.Count -gt 0) { return @($entries) }
    } catch {
      return @()
    }
  }
  return @()
}

function Update-StateBagCache {
  if ($null -eq $script:State) { return @() }
  $entries = @(Get-ValidBagEntries -Bag $script:State.bag)
  if ($entries.Count -eq 0 -and (Test-Path -LiteralPath $script:StatePath)) {
    $entries = @(Get-BagEntriesFromStateFile $script:StatePath)
    if ($entries.Count -gt 0) {
      Set-ObjectProperty $script:State "bag" @($entries)
    }
  }
  if ($entries.Count -gt 0) {
    $script:LastKnownBagEntries = @($entries)
  }
  return @($entries)
}

function Encode-Field {
  param($Value)
  return [System.Uri]::EscapeDataString([string]$Value)
}

function New-EditorCommandLine {
  param([string]$Seq, [string]$Command, [hashtable]$Values)
  $parts = New-Object System.Collections.Generic.List[string]
  $parts.Add($Seq)
  $parts.Add($Command)
  foreach ($key in $Values.Keys) {
    $parts.Add(("{0}={1}" -f $key, (Encode-Field $Values[$key])))
  }
  return ($parts -join "|")
}

function Get-PendingCommandCount {
  if ($null -eq $script:PendingCommands) { return 0 }
  return [int]$script:PendingCommands.Count
}

function Update-PendingStatus {
  param([string]$Action = "Cambio pendiente")
  $count = Get-PendingCommandCount
  if ($null -ne $script:StatusLabel) {
    $script:StatusLabel.Text = ("{0}. Cambios pendientes: {1}. Usa Archivo > Guardar partida para aplicarlos y guardar." -f $Action, $count)
  }
}

function Test-ExternalEditMode {
  try {
    if (!(Test-Path -LiteralPath $script:EditTargetPath)) { return $false }
    $target = [System.IO.File]::ReadAllText($script:EditTargetPath, $script:Utf8NoBom).Trim()
    return ![string]::IsNullOrWhiteSpace($target)
  } catch {
    return $false
  }
}

function Get-ApplyModeText {
  if (Test-ExternalEditMode) { return "archivo externo" }
  return "partida viva"
}

function Stage-EditorCommand {
  param([string]$Command, [hashtable]$Values)
  if ($null -eq $script:PendingCommands) { $script:PendingCommands = New-Object System.Collections.ArrayList }
  $seq = [guid]::NewGuid().ToString("N")
  $line = New-EditorCommandLine $seq $Command $Values
  [void]$script:PendingCommands.Add([pscustomobject]@{
    Seq = $seq
    Command = $Command
    Values = $Values
    Line = $line
  })
  $script:Dirty = $false
  Register-HistoryState ("Preparado: " + (Format-EditorCommandName $Command)) $(if ($Command.StartsWith("pokemon")) { "Pokemon" } else { "Comando" })
  Update-PendingStatus ("Cambio preparado: " + $Command)
}

function Discard-PendingChanges {
  if ($null -ne $script:PendingCommands) { $script:PendingCommands.Clear() }
  $script:Dirty = $false
  if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = "Cambios pendientes descartados." }
  Update-HistoryViews
}

function Flush-PendingCommandsAndSave {
  Commit-PendingHistoryCheckpoint
  if ($script:Dirty -and $null -ne $script:SelectedPokemon) {
    $values = Get-EditedPokemonValues
    if ($null -ne $values) { Stage-EditorCommand "pokemon_set" $values }
  }
  $seq = [guid]::NewGuid().ToString("N")
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($entry in @($script:PendingCommands)) {
    if ($null -ne $entry.Line -and [string]$entry.Line -ne "") { $lines.Add([string]$entry.Line) }
  }
  $lines.Add((New-EditorCommandLine $seq "save_game" @{}))
  [System.IO.File]::AppendAllText($script:CommandPath, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), $script:Utf8NoBom)
  $count = Get-PendingCommandCount
  $script:LastSavePendingCount = $count
  if ($null -ne $script:PendingCommands) { $script:PendingCommands.Clear() }
  $script:StatusLabel.Text = "Guardando partida con $count cambio(s) pendiente(s)..."
  $script:Dirty = $false
  $script:PendingUntil = [DateTime]::Now.AddMilliseconds(1400)
  Request-PostCommandRefresh $seq
}

function Send-EditorCommand {
  param([string]$Command, [hashtable]$Values)
  if ($Command -eq "save_game") {
    Flush-PendingCommandsAndSave
    return
  }
  Stage-EditorCommand $Command $Values
}

function Send-EditorCommandImmediate {
  param([string]$Command, [hashtable]$Values)
  try {
    $seq = [guid]::NewGuid().ToString("N")
    $line = New-EditorCommandLine $seq $Command $Values
    [System.IO.File]::AppendAllText($script:CommandPath, ($line + [Environment]::NewLine), $script:Utf8NoBom)
    return $seq
  } catch {
    return ""
  }
}

function Write-AliveFile {
  try {
    [System.IO.File]::WriteAllText($script:AlivePath, ([DateTime]::UtcNow.ToString("o")), $script:Utf8NoBom)
  } catch {
  }
}

function Request-PostCommandRefresh {
  param([string]$Seq = "")
  try {
    if ($null -ne $script:PostCommandTimer) {
      $script:PostCommandTimer.Stop()
      $script:PostCommandTimer.Dispose()
      $script:PostCommandTimer = $null
    }
    $script:PostCommandSeq = $Seq
    $script:PostCommandPolls = 0
    $script:PostCommandTimer = New-Object System.Windows.Forms.Timer
    $script:PostCommandTimer.Interval = 650
    $script:PostCommandTimer.Add_Tick({
      try {
        $script:PostCommandPolls++
        $result = Read-JsonFile $script:ResultPath
        $matched = ($script:PostCommandSeq -eq "")
        if ($null -ne $result -and [string]$result.seq -eq $script:PostCommandSeq) { $matched = $true }
        if ($matched -or $script:PostCommandPolls -ge 12) {
          $script:PostCommandTimer.Stop()
          $script:PostCommandTimer.Dispose()
          $script:PostCommandTimer = $null
          $script:Dirty = $false
          $savedCount = [int]$script:LastSavePendingCount
          Refresh-All $true
          $saveLabel = $(if ($savedCount -eq 1) { "Partida guardada (1 cambio aplicado)" } else { "Partida guardada ($savedCount cambios aplicados)" })
          Register-HistoryState $saveLabel "Sistema"
        } else {
          Load-LiveData
        }
      } catch {}
    })
    $script:PostCommandTimer.Start()
  } catch {
  }
}

function Get-NameFromList {
  param($List, [int]$Id)
  if ($null -eq $List) { return "" }
  foreach ($entry in @($List)) {
    if ([int]$entry.id -eq $Id) { return [string]$entry.name }
  }
  return ""
}

function Get-PbsCompatibilityData {
  if ($null -ne $script:PbsCompatibilityCache) { return $script:PbsCompatibilityCache }
  $cache = [pscustomobject]@{
    MoveIdsByInternal = @{}
    SpeciesIdsByInternal = @{}
    MoveIdsBySpeciesId = @{}
  }
  try {
    $pbsDir = Join-Path $script:GameDir "PBS"
    $movesPath = Join-Path $pbsDir "moves.txt"
    if (Test-Path -LiteralPath $movesPath) {
      foreach ($line in [System.IO.File]::ReadLines($movesPath)) {
        if ($line -match "^\s*(\d+),([^,]+),") {
          $cache.MoveIdsByInternal[$matches[2].Trim().ToUpperInvariant()] = [int]$matches[1]
        }
      }
    }
    $pokemonPath = Join-Path $pbsDir "pokemon.txt"
    if (Test-Path -LiteralPath $pokemonPath) {
      $currentId = 0
      foreach ($line in [System.IO.File]::ReadLines($pokemonPath)) {
        if ($line -match "^\s*\[(\d+)\]") {
          $currentId = [int]$matches[1]
        } elseif ($currentId -gt 0 -and $line -match "^\s*InternalName\s*=\s*(.+)$") {
          $cache.SpeciesIdsByInternal[$matches[1].Trim().ToUpperInvariant()] = $currentId
        }
      }
    }
    $tmPath = Join-Path $pbsDir "tm.txt"
    if (Test-Path -LiteralPath $tmPath) {
      $currentMoveId = 0
      foreach ($line in [System.IO.File]::ReadLines($tmPath)) {
        $text = $line.Trim()
        if ($text -eq "" -or $text.StartsWith("#")) { continue }
        if ($text -match "^\[([^\]]+)\]") {
          $key = $matches[1].Trim().ToUpperInvariant()
          $currentMoveId = $(if ($cache.MoveIdsByInternal.ContainsKey($key)) { [int]$cache.MoveIdsByInternal[$key] } else { 0 })
          continue
        }
        if ($currentMoveId -le 0) { continue }
        foreach ($speciesName in $text.Split(",")) {
          $speciesKey = $speciesName.Trim().ToUpperInvariant()
          if ($speciesKey -eq "" -or !$cache.SpeciesIdsByInternal.ContainsKey($speciesKey)) { continue }
          $speciesId = [int]$cache.SpeciesIdsByInternal[$speciesKey]
          if (!$cache.MoveIdsBySpeciesId.ContainsKey($speciesId)) {
            $cache.MoveIdsBySpeciesId[$speciesId] = @{}
          }
          $cache.MoveIdsBySpeciesId[$speciesId][$currentMoveId] = $true
        }
      }
    }
  } catch {
  }
  $script:PbsCompatibilityCache = $cache
  return $cache
}

function Get-PbsCompatibleMoveIds {
  param([int]$SpeciesId)
  if ($SpeciesId -le 0) { return @() }
  $cache = Get-PbsCompatibilityData
  if ($null -eq $cache -or !$cache.MoveIdsBySpeciesId.ContainsKey($SpeciesId)) { return @() }
  return @($cache.MoveIdsBySpeciesId[$SpeciesId].Keys | ForEach-Object { [int]$_ })
}

function Add-PbsSpeciesAbilitySlots {
  param($Cache, [int]$SpeciesId, $AbilityCodes, [string]$HiddenCode)
  if ($null -eq $Cache -or $SpeciesId -le 0) { return }
  $slots = @(-1, -1, -1)
  $codes = @($AbilityCodes)
  for ($i = 0; $i -lt [Math]::Min(2, $codes.Count); $i++) {
    $key = ([string]$codes[$i]).Trim().ToUpperInvariant()
    if ($key -ne "" -and $Cache.IdByCode.ContainsKey($key)) { $slots[$i] = [int]$Cache.IdByCode[$key] }
  }
  $hiddenKey = ([string]$HiddenCode).Trim().ToUpperInvariant()
  if ($hiddenKey -ne "" -and $Cache.IdByCode.ContainsKey($hiddenKey)) { $slots[2] = [int]$Cache.IdByCode[$hiddenKey] }
  $Cache.SpeciesSlots[$SpeciesId] = @($slots)
}

function Get-PbsAbilityData {
  if ($null -ne $script:PbsAbilityCache) { return $script:PbsAbilityCache }
  $cache = [pscustomobject]@{
    ById = @{}
    IdByCode = @{}
    SpeciesSlots = @{}
  }
  try {
    $pbsDir = Join-Path $script:GameDir "PBS"
    $abilitiesPath = Join-Path $pbsDir "abilities.txt"
    if (Test-Path -LiteralPath $abilitiesPath) {
      foreach ($line in [System.IO.File]::ReadLines($abilitiesPath)) {
        $text = $line.Trim()
        if ($text -eq "" -or $text.StartsWith("#")) { continue }
        try {
          $row = $text | ConvertFrom-Csv -Header "id","code","name","description"
          if ($null -eq $row) { continue }
          $id = [int]$row.id
          $code = ([string]$row.code).Trim().ToUpperInvariant()
          $entry = [pscustomobject]@{
            id = $id
            code = $code
            name = [string]$row.name
            description = [string]$row.description
          }
          $cache.ById[$id] = $entry
          if ($code -ne "") { $cache.IdByCode[$code] = $id }
        } catch {
        }
      }
    }
    $pokemonPath = Join-Path $pbsDir "pokemon.txt"
    if (Test-Path -LiteralPath $pokemonPath) {
      $currentId = 0
      $abilityCodes = @()
      $hiddenCode = ""
      foreach ($line in [System.IO.File]::ReadLines($pokemonPath)) {
        $text = $line.Trim()
        if ($text -match "^\[(\d+)\]") {
          Add-PbsSpeciesAbilitySlots $cache $currentId $abilityCodes $hiddenCode
          $currentId = [int]$matches[1]
          $abilityCodes = @()
          $hiddenCode = ""
        } elseif ($currentId -gt 0 -and $text -match "^Abilities\s*=\s*(.+)$") {
          $abilityCodes = @($matches[1].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        } elseif ($currentId -gt 0 -and $text -match "^HiddenAbility\s*=\s*(.+)$") {
          $hiddenCode = $matches[1].Trim()
        }
      }
      Add-PbsSpeciesAbilitySlots $cache $currentId $abilityCodes $hiddenCode
    }
  } catch {
  }
  $script:PbsAbilityCache = $cache
  return $cache
}

function Get-AbilityInfoById {
  param([int]$AbilityId)
  if ($AbilityId -le 0) { return $null }
  $cache = Get-PbsAbilityData
  if ($null -ne $cache -and $cache.ById.ContainsKey($AbilityId)) { return $cache.ById[$AbilityId] }
  $name = Get-EntryName $script:Data.abilities $AbilityId
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }
  return [pscustomobject]@{ id = $AbilityId; code = ""; name = $name; description = "" }
}

function Get-SpeciesAbilityIdByFlag {
  param([int]$SpeciesId, [int]$AbilityFlag)
  if ($SpeciesId -le 0 -or $AbilityFlag -lt 0 -or $AbilityFlag -gt 2) { return 0 }
  $cache = Get-PbsAbilityData
  if ($null -eq $cache -or !$cache.SpeciesSlots.ContainsKey($SpeciesId)) { return 0 }
  $slots = @($cache.SpeciesSlots[$SpeciesId])
  if ($slots.Count -gt $AbilityFlag) { return [int]$slots[$AbilityFlag] }
  return 0
}

function Get-AbilityComboLabel {
  param([string]$Prefix, [int]$AbilityId)
  $info = Get-AbilityInfoById $AbilityId
  if ($null -eq $info -or [string]::IsNullOrWhiteSpace([string]$info.name)) { return $Prefix }
  return ("{0}: {1}" -f $Prefix, [string]$info.name)
}

function Update-AbilityDetails {
  if ($null -eq $script:AbilityDescriptionBox) { return }
  $flag = Get-NamedComboId $script:AbilityCombo
  if ($flag -eq $null -and $null -ne $script:PokeAbilityFlag) { $flag = [int]$script:PokeAbilityFlag.Value }
  if ($flag -eq $null) { $flag = -1 }
  $speciesId = Get-CurrentSpeciesId
  $abilityId = 0
  if ([int]$flag -lt 0) {
    if ($null -ne $script:SelectedPokemon -and $null -ne $script:SelectedPokemon.ability) { $abilityId = [int]$script:SelectedPokemon.ability }
  } else {
    $abilityId = Get-SpeciesAbilityIdByFlag $speciesId ([int]$flag)
  }
  $info = Get-AbilityInfoById $abilityId
  if ($null -eq $info) {
    $script:AbilityDescriptionBox.Text = "Sin descripcion de habilidad."
    return
  }
  $desc = [string]$info.description
  if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "Sin descripcion de habilidad." }
  $script:AbilityDescriptionBox.Text = $desc
  Set-Tip $script:AbilityDescriptionBox (([string]$info.name) + ": " + $desc)
}

function Update-AbilityOptionsForCurrentSelection {
  if ($null -eq $script:AbilityCombo) { return }
  $speciesId = Get-CurrentSpeciesId
  $flag = -1
  if ($null -ne $script:PokeAbilityFlag) { $flag = [int]$script:PokeAbilityFlag.Value }
  $actualName = ""
  if ($null -ne $script:SelectedPokemon -and $null -ne $script:SelectedPokemon.abilityName) { $actualName = [string]$script:SelectedPokemon.abilityName }
  $entries = New-Object System.Collections.ArrayList
  $autoLabel = $(if ([string]::IsNullOrWhiteSpace($actualName)) { "Automatica" } else { "Automatica: $actualName" })
  [void]$entries.Add([pscustomobject]@{ id = -1; name = $autoLabel })
  [void]$entries.Add([pscustomobject]@{ id = 0; name = (Get-AbilityComboLabel "Habilidad 1" (Get-SpeciesAbilityIdByFlag $speciesId 0)) })
  [void]$entries.Add([pscustomobject]@{ id = 1; name = (Get-AbilityComboLabel "Habilidad 2" (Get-SpeciesAbilityIdByFlag $speciesId 1)) })
  [void]$entries.Add([pscustomobject]@{ id = 2; name = (Get-AbilityComboLabel "Oculta" (Get-SpeciesAbilityIdByFlag $speciesId 2)) })
  Populate-NamedCombo $script:AbilityCombo @($entries) $false ""
  Set-NamedComboById $script:AbilityCombo $flag
  Update-AbilityDetails
}

function Format-Pokemon {
  param($Pokemon)
  if ($null -eq $Pokemon) { return "" }
  $prefix = ""
  if ($Pokemon.loc -eq "party") { $prefix = "[Equipo {0}] " -f ([int]$Pokemon.index + 1) }
  if ($Pokemon.loc -eq "box") { $prefix = "[Caja {0}:{1}] " -f ([int]$Pokemon.box + 1), ([int]$Pokemon.slot + 1) }
  return "{0}{1} / {2} Nv.{3} PS {4}/{5}" -f $prefix, $Pokemon.nickname, $Pokemon.speciesName, $Pokemon.level, $Pokemon.hp, $Pokemon.totalhp
}

function New-Label {
  param([string]$Text, [int]$X, [int]$Y, [int]$W = 120, [int]$H = 24)
  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Text
  $label.Location = New-Object System.Drawing.Point($X, $Y)
  $label.Size = New-Object System.Drawing.Size($W, $H)
  $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  return $label
}

function New-TextBox {
  param([int]$X, [int]$Y, [int]$W = 160)
  $box = New-Object System.Windows.Forms.TextBox
  $box.Location = New-Object System.Drawing.Point($X, $Y)
  $box.Size = New-Object System.Drawing.Size($W, 24)
  return $box
}

function New-Number {
  param([int]$X, [int]$Y, [int64]$Min = 0, [int64]$Max = 9999999, [int]$W = 110)
  $num = New-Object System.Windows.Forms.NumericUpDown
  $num.Location = New-Object System.Drawing.Point($X, $Y)
  $num.Size = New-Object System.Drawing.Size($W, 24)
  $num.Minimum = [decimal]$Min
  $num.Maximum = [decimal]$Max
  return $num
}

function Disable-WheelChange {
  param($Control)
  if ($null -eq $Control) { return }
  if ($Control -is [System.Windows.Forms.NumericUpDown]) {
    $Control.Add_MouseWheel({
      $ctrl = $this
      $value = $ctrl.Value
      if ($args.Count -gt 1 -and $args[1] -is [System.Windows.Forms.HandledMouseEventArgs]) { $args[1].Handled = $true }
      [void]$ctrl.BeginInvoke([Action]{ try { $ctrl.Value = $value } catch {} }.GetNewClosure())
    })
  } elseif ($Control -is [System.Windows.Forms.ComboBox]) {
    $Control.Add_MouseWheel({
      $ctrl = $this
      $index = $ctrl.SelectedIndex
      $text = $ctrl.Text
      if ($args.Count -gt 1 -and $args[1] -is [System.Windows.Forms.HandledMouseEventArgs]) { $args[1].Handled = $true }
      [void]$ctrl.BeginInvoke([Action]{
        try {
          if ($index -ge -1 -and $index -lt $ctrl.Items.Count) { $ctrl.SelectedIndex = $index }
          $ctrl.Text = $text
        } catch {}
      }.GetNewClosure())
    })
  } elseif ($Control -is [System.Windows.Forms.CheckedListBox]) {
    $Control.Add_MouseWheel({
      if ($args.Count -gt 1 -and $args[1] -is [System.Windows.Forms.HandledMouseEventArgs]) { $args[1].Handled = $true }
    })
  }
}

function Disable-WheelChangeRecursive {
  param($RootControl)
  if ($null -eq $RootControl) { return }
  Disable-WheelChange $RootControl
  foreach ($child in $RootControl.Controls) {
    Disable-WheelChangeRecursive $child
  }
}

function Set-Tip {
  param($Control, [string]$Text)
  if ($null -ne $Control -and $null -ne $script:ToolTip -and ![string]::IsNullOrWhiteSpace($Text)) {
    $script:ToolTip.SetToolTip($Control, $Text)
  }
}

function New-NavButton {
  param([string]$Text, $TargetTab, [string]$Description)
  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Size = New-Object System.Drawing.Size(112, 30)
  $button.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 4)
  $button.Add_Click({
    if ($script:Dirty) { $script:Dirty = $false }
    $tabs.SelectedTab = $TargetTab
  }.GetNewClosure())
  Set-Tip $button $Description
  return $button
}

function Load-BitmapUnlocked {
  param([string]$Path)
  try {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $img = [System.Drawing.Image]::FromStream($ms)
    $copy = New-Object System.Drawing.Bitmap($img)
    $img.Dispose()
    $ms.Dispose()
    return $copy
  } catch {
    return $null
  }
}

function Get-FirstIconFrame {
  param($Image)
  if ($null -eq $Image) { return $null }
  try {
    if ($Image.Width -gt ($Image.Height * 1.35)) {
      $frameWidth = [Math]::Max(1, [int]($Image.Width / 2))
      $frame = New-Object System.Drawing.Bitmap($frameWidth, $Image.Height)
      $graphics = [System.Drawing.Graphics]::FromImage($frame)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
      $src = New-Object System.Drawing.Rectangle(0, 0, $frameWidth, $Image.Height)
      $dst = New-Object System.Drawing.Rectangle(0, 0, $frameWidth, $Image.Height)
      $graphics.DrawImage($Image, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
      $graphics.Dispose()
      return $frame
    }
  } catch {
    return $Image
  }
  return $Image
}

function Get-PokemonIcon {
  param($Pokemon)
  if ($null -eq $Pokemon) { return $null }
  $species = [int]$Pokemon.species
  $form = [int]$Pokemon.form
  $shiny = [bool]$Pokemon.shiny
  $suffix = $(if ($shiny) { "s" } else { "" })
  $keys = @(
    ("icon{0:D3}{1}_{2}" -f $species, $suffix, $form),
    ("icon{0:D3}_{1}" -f $species, $form),
    ("icon{0:D3}{1}" -f $species, $suffix),
    ("icon{0:D3}" -f $species),
    "icon000"
  )
  foreach ($key in $keys) {
    if ($script:PokemonIconCache.ContainsKey($key)) { return $script:PokemonIconCache[$key] }
    $path = Join-Path (Join-Path $script:GameDir "Graphics\Icons") ($key + ".png")
    $image = Load-BitmapUnlocked $path
    if ($null -ne $image) {
      $frame = Get-FirstIconFrame $image
      if (![object]::ReferenceEquals($frame, $image)) { $image.Dispose() }
      $script:PokemonIconCache[$key] = $frame
      return $frame
    }
  }
  return $null
}

function Get-PokemonIconByValues {
  param([int]$Species, [bool]$Shiny = $false, [int]$Form = 0)
  if ($Species -le 0) { return $null }
  return Get-PokemonIcon ([pscustomobject]@{ species = $Species; shiny = $Shiny; form = $Form })
}

function Get-ItemIcon {
  param([int]$ItemId)
  if ($ItemId -le 0) { return $null }
  $keys = @(
    ("item{0:D3}" -f $ItemId),
    ("item{0}" -f $ItemId),
    "item000"
  )
  foreach ($key in $keys) {
    if ($script:ItemIconCache.ContainsKey($key)) { return $script:ItemIconCache[$key] }
    $path = Join-Path (Join-Path $script:GameDir "Graphics\Icons") ($key + ".png")
    $image = Load-BitmapUnlocked $path
    if ($null -ne $image) {
      $script:ItemIconCache[$key] = $image
      return $image
    }
  }
  return $null
}

function Get-BlankIcon {
  if ($null -eq $script:BlankIcon) {
    $script:BlankIcon = New-Object System.Drawing.Bitmap(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($script:BlankIcon)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.Dispose()
  }
  return $script:BlankIcon
}

function Get-SpriteFrame {
  param([string]$Path, [int]$Index, [int]$FrameWidth, [int]$FrameHeight, [hashtable]$Cache, [string]$KeyPrefix)
  if ($Index -lt 0 -or [string]::IsNullOrWhiteSpace($Path)) { return $null }
  $key = "{0}_{1}" -f $KeyPrefix, $Index
  if ($Cache.ContainsKey($key)) { return $Cache[$key] }
  $sheet = Load-BitmapUnlocked $Path
  if ($null -eq $sheet) { return $null }
  try {
    $maxIndex = [Math]::Floor($sheet.Height / $FrameHeight) - 1
    if ($Index -gt $maxIndex) { return $null }
    $frame = New-Object System.Drawing.Bitmap($FrameWidth, $FrameHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($frame)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $src = New-Object System.Drawing.Rectangle(0, ($Index * $FrameHeight), $FrameWidth, $FrameHeight)
    $dst = New-Object System.Drawing.Rectangle(0, 0, $FrameWidth, $FrameHeight)
    $graphics.DrawImage($sheet, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.Dispose()
    $Cache[$key] = $frame
    return $frame
  } catch {
    return $null
  } finally {
    if ($null -ne $sheet) { $sheet.Dispose() }
  }
}

function Get-TypeIconById {
  param([int]$TypeId)
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") "types_ico.png"
  return Get-SpriteFrame -Path $path -Index $TypeId -FrameWidth 24 -FrameHeight 28 -Cache $script:TypeIconCache -KeyPrefix "type"
}

function Get-CategoryIconById {
  param([int]$CategoryId)
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") "category.png"
  return Get-SpriteFrame -Path $path -Index $CategoryId -FrameWidth 64 -FrameHeight 28 -Cache $script:CategoryIconCache -KeyPrefix "category"
}

function Get-MetricIcon {
  param([string]$Text, [System.Drawing.Color]$Color)
  $key = "metric_" + $Text
  if ($script:MetricIconCache.ContainsKey($key)) { return $script:MetricIconCache[$key] }
  $bitmap = New-Object System.Drawing.Bitmap(28, 18)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush($Color)
  $graphics.FillRectangle($brush, 0, 0, 27, 17)
  $brush.Dispose()
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
  $graphics.DrawRectangle($pen, 0, 0, 27, 17)
  $pen.Dispose()
  $font = New-Object System.Drawing.Font("Segoe UI", 6.5, [System.Drawing.FontStyle]::Bold)
  $format = New-Object System.Drawing.StringFormat
  $format.Alignment = [System.Drawing.StringAlignment]::Center
  $format.LineAlignment = [System.Drawing.StringAlignment]::Center
  $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $rect = New-Object System.Drawing.RectangleF(0, 0, 28, 18)
  $graphics.DrawString($Text, $font, $textBrush, $rect, $format)
  $textBrush.Dispose()
  $font.Dispose()
  $format.Dispose()
  $graphics.Dispose()
  $script:MetricIconCache[$key] = $bitmap
  return $bitmap
}

function Get-BagPocketDefinitions {
  return @(
    [pscustomobject]@{ Id = 0; Name = "Todos"; Icon = 0 },
    [pscustomobject]@{ Id = 1; Name = "Objetos"; Icon = 1 },
    [pscustomobject]@{ Id = 2; Name = "Medicinas"; Icon = 2 },
    [pscustomobject]@{ Id = 3; Name = "Poke Balls"; Icon = 3 },
    [pscustomobject]@{ Id = 4; Name = "MTs"; Icon = 4 },
    [pscustomobject]@{ Id = 5; Name = "Ingredientes"; Icon = 5 },
    [pscustomobject]@{ Id = 6; Name = "Megapiedras"; Icon = 6 },
    [pscustomobject]@{ Id = 7; Name = "Obj. Batallas"; Icon = 7 },
    [pscustomobject]@{ Id = 8; Name = "Obj. Claves"; Icon = 8 }
  )
}

function Get-BagPocketName {
  param([int]$PocketId)
  foreach ($pocket in Get-BagPocketDefinitions) {
    if ([int]$pocket.Id -eq $PocketId) { return [string]$pocket.Name }
  }
  return "Bolsillo $PocketId"
}

function Get-BagPocketIcon {
  param([int]$PocketId)
  if ($PocketId -le 0) { return $null }
  $key = "bagPocket{0}" -f $PocketId
  if ($script:BagPocketIconCache.ContainsKey($key)) { return $script:BagPocketIconCache[$key] }
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Icons") ($key + ".png")
  $image = Load-BitmapUnlocked $path
  if ($null -ne $image) { $script:BagPocketIconCache[$key] = $image }
  return $image
}

function Get-AchievementIcon {
  param([int]$Index, [int]$Status = 2)
  $suffix = $(if ($Status -eq 3) { "c" } else { "" })
  $key = "logro_{0}{1}" -f $Index, $suffix
  if ($script:AchievementIconCache.ContainsKey($key)) { return $script:AchievementIconCache[$key] }
  $base = Join-Path $script:GameDir "Graphics\Pictures\Logros\img"
  $path = Join-Path $base (("{0}{1}.png" -f $Index, $suffix))
  if (!(Test-Path -LiteralPath $path)) { $path = Join-Path $base ("{0}.png" -f $Index) }
  if (!(Test-Path -LiteralPath $path)) { $path = Join-Path $base "hidden.png" }
  $image = Load-BitmapUnlocked $path
  if ($null -ne $image) { $script:AchievementIconCache[$key] = $image }
  return $image
}

function Get-BallIcon {
  param([int]$BallId)
  if ($BallId -lt 0) { $BallId = 0 }
  $key = "ball{0:D2}" -f $BallId
  if ($script:BallIconCache.ContainsKey($key)) { return $script:BallIconCache[$key] }
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") ($key + ".png")
  $image = Load-BitmapUnlocked $path
  if ($null -eq $image) {
    $fallback = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") "ball00.png"
    $image = Load-BitmapUnlocked $fallback
  }
  if ($null -ne $image) { $script:BallIconCache[$key] = $image }
  return $image
}

function Get-BallEntries {
  return @(
    [pscustomobject]@{ id = 0; name = "Poke Ball" },
    [pscustomobject]@{ id = 1; name = "Super Ball" },
    [pscustomobject]@{ id = 2; name = "Safari Ball" },
    [pscustomobject]@{ id = 3; name = "Ultra Ball" },
    [pscustomobject]@{ id = 4; name = "Master Ball" },
    [pscustomobject]@{ id = 5; name = "Malla Ball" },
    [pscustomobject]@{ id = 6; name = "Buceo Ball" },
    [pscustomobject]@{ id = 7; name = "Nido Ball" },
    [pscustomobject]@{ id = 8; name = "Acopio Ball" },
    [pscustomobject]@{ id = 9; name = "Turno Ball" },
    [pscustomobject]@{ id = 10; name = "Lujo Ball" },
    [pscustomobject]@{ id = 11; name = "Honor Ball" },
    [pscustomobject]@{ id = 12; name = "Ocaso Ball" },
    [pscustomobject]@{ id = 13; name = "Sana Ball" },
    [pscustomobject]@{ id = 14; name = "Veloz Ball" },
    [pscustomobject]@{ id = 15; name = "Gloria Ball" },
    [pscustomobject]@{ id = 16; name = "Rapid Ball" },
    [pscustomobject]@{ id = 17; name = "Nivel Ball" },
    [pscustomobject]@{ id = 18; name = "Cebo Ball" },
    [pscustomobject]@{ id = 19; name = "Peso Ball" },
    [pscustomobject]@{ id = 20; name = "Amor Ball" },
    [pscustomobject]@{ id = 21; name = "Amigo Ball" },
    [pscustomobject]@{ id = 22; name = "Luna Ball" },
    [pscustomobject]@{ id = 23; name = "Compet Ball" },
    [pscustomobject]@{ id = 24; name = "Esper Ball" },
    [pscustomobject]@{ id = 25; name = "Poke Ball Casera" },
    [pscustomobject]@{ id = 26; name = "Super Ball Casera" },
    [pscustomobject]@{ id = 27; name = "Ultra Ball Casera" }
  )
}

function Get-EntryName {
  param($Entries, [int]$Id)
  foreach ($entry in @($Entries)) {
    if ([int]$entry.id -eq $Id) { return [string]$entry.name }
  }
  return ""
}

function Get-EntryById {
  param($Entries, [int]$Id)
  foreach ($entry in @($Entries)) {
    if ([int]$entry.id -eq $Id) { return $entry }
  }
  return $null
}

function Get-ObjectProperty {
  param([object]$Object, [string]$Name, [object]$Default = "")
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
  return $prop.Value
}

function Format-MoveMetric {
  param([object]$Move, [string]$Name)
  try {
    $value = [int](Get-ObjectProperty $Move $Name 0)
    if ($value -le 0) { return "-" }
    if ($Name -eq "power" -and $value -eq 1) { return "???" }
    return [string]$value
  } catch {
    return "-"
  }
}

function Format-EditorMoveDetails {
  param([int]$MoveId)
  if ($MoveId -le 0 -or $null -eq $script:Data -or $null -eq $script:Data.moves) { return "Sin movimiento." }
  $move = Get-EntryById $script:Data.moves $MoveId
  if ($null -eq $move) { return "Movimiento desconocido (#$MoveId)." }
  $name = [string](Get-ObjectProperty $move "name" "")
  $type = [string](Get-ObjectProperty $move "typeName" "")
  $category = [string](Get-ObjectProperty $move "categoryName" "")
  $power = Format-MoveMetric $move "power"
  $accuracy = Format-MoveMetric $move "accuracy"
  $pp = Format-MoveMetric $move "pp"
  $description = [string](Get-ObjectProperty $move "description" "")
  return "$name (#$MoveId)`r`nTipo: $type | Clase: $category`r`nPotencia: $power | Precision: $accuracy | PP: $pp`r`n$description"
}

function Add-MoveDetailIconText {
  param($Panel, [int]$X, [int]$Y, [System.Drawing.Image]$Icon, [string]$Text, [int]$Width = 78, [int]$IconWidth = 18)
  $picture = New-Object System.Windows.Forms.PictureBox
  $picture.Location = New-Object System.Drawing.Point($X, $Y)
  $picture.Size = New-Object System.Drawing.Size($IconWidth, 18)
  $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
  $picture.Image = $(if ($null -ne $Icon) { $Icon } else { Get-BlankIcon })
  $label = New-Object System.Windows.Forms.Label
  $label.Location = New-Object System.Drawing.Point(($X + $IconWidth + 4), ($Y - 1))
  $label.Size = New-Object System.Drawing.Size(($Width - $IconWidth - 4), 20)
  $label.Text = $Text
  $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $label.Font = New-Object System.Drawing.Font("Segoe UI", 8)
  $Panel.Controls.Add($picture)
  $Panel.Controls.Add($label)
}

function Show-EditorMoveDetails {
  param([int]$MoveId)
  if ($null -eq $script:MoveDetailsBox) { return }
  if ($script:MoveDetailsBox -is [System.Windows.Forms.TextBox]) {
    $script:MoveDetailsBox.Text = Format-EditorMoveDetails $MoveId
    return
  }
  $panel = $script:MoveDetailsBox
  $panel.SuspendLayout()
  try {
    foreach ($control in @($panel.Controls)) {
      try { $control.Dispose() } catch {}
    }
    $panel.Controls.Clear()
    if ($MoveId -le 0 -or $null -eq $script:Data -or $null -eq $script:Data.moves) {
      $empty = New-Object System.Windows.Forms.Label
      $empty.Text = "Sin movimiento."
      $empty.Dock = [System.Windows.Forms.DockStyle]::Fill
      $empty.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
      $panel.Controls.Add($empty)
      return
    }
    $move = Get-EntryById $script:Data.moves $MoveId
    if ($null -eq $move) {
      $missing = New-Object System.Windows.Forms.Label
      $missing.Text = "Movimiento desconocido (#$MoveId)."
      $missing.Dock = [System.Windows.Forms.DockStyle]::Fill
      $missing.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
      $panel.Controls.Add($missing)
      return
    }
    $name = [string](Get-ObjectProperty $move "name" "")
    $typeId = [int](Get-ObjectProperty $move "type" -1)
    $type = [string](Get-ObjectProperty $move "typeName" "")
    $categoryId = [int](Get-ObjectProperty $move "category" -1)
    $category = [string](Get-ObjectProperty $move "categoryName" "")
    $power = Format-MoveMetric $move "power"
    $accuracy = Format-MoveMetric $move "accuracy"
    $pp = Format-MoveMetric $move "pp"
    $description = [string](Get-ObjectProperty $move "description" "")

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "{0}  #{1}" -f $name, $MoveId
    $title.Location = New-Object System.Drawing.Point(8, 5)
    $title.Size = New-Object System.Drawing.Size(($panel.Width - 16), 20)
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 8.6, [System.Drawing.FontStyle]::Bold)
    $title.AutoEllipsis = $true
    $panel.Controls.Add($title)

    Add-MoveDetailIconText $panel 8 29 (Get-TypeIconById $typeId) $type 116 20
    Add-MoveDetailIconText $panel 132 29 (Get-CategoryIconById $categoryId) $category 126 42
    Add-MoveDetailIconText $panel 8 53 (Get-MetricIcon "POT" ([System.Drawing.Color]::FromArgb(211, 95, 65))) $power 78 28
    Add-MoveDetailIconText $panel 92 53 (Get-MetricIcon "PRE" ([System.Drawing.Color]::FromArgb(79, 137, 204))) $accuracy 78 28
    Add-MoveDetailIconText $panel 176 53 (Get-MetricIcon "PP" ([System.Drawing.Color]::FromArgb(88, 158, 98))) $pp 72 28

    $desc = New-Object System.Windows.Forms.TextBox
    $desc.Text = $description
    $desc.Location = New-Object System.Drawing.Point(8, 72)
    $desc.Size = New-Object System.Drawing.Size(($panel.Width - 16), [Math]::Max(20, ($panel.Height - 78)))
    $desc.Font = New-Object System.Drawing.Font("Segoe UI", 7.6)
    $desc.Multiline = $true
    $desc.ReadOnly = $true
    $desc.WordWrap = $true
    $desc.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $desc.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $desc.BackColor = [System.Drawing.Color]::White
    $panel.Controls.Add($desc)
  } finally {
    $panel.ResumeLayout()
  }
}

function Update-MoveDetailLabel {
  param([int]$Index)
  if ($Index -lt 0 -or $Index -ge $script:MoveDetailLabels.Count) { return }
  $moveId = 0
  if ($Index -lt $script:MoveIds.Count) { $moveId = [int]$script:MoveIds[$Index].Value }
  $script:MoveDetailLabels[$Index].Text = Format-EditorMoveDetails $moveId
}

function Update-AllMoveDetailLabels {
  for ($i = 0; $i -lt $script:MoveDetailLabels.Count; $i++) { Update-MoveDetailLabel $i }
}

function Update-MoveDetailsBox {
  param([int]$Index)
  if ($null -eq $script:MoveDetailsBox) { return }
  $moveId = 0
  if ($Index -ge 0 -and $Index -lt $script:MoveCombos.Count) {
    $comboMoveId = Get-NamedComboId $script:MoveCombos[$Index]
    if ($comboMoveId -ne $null) { $moveId = [int]$comboMoveId }
  }
  if ($Index -ge 0 -and $Index -lt $script:MoveIds.Count) {
    if ($moveId -le 0) { $moveId = [int]$script:MoveIds[$Index].Value }
  }
  Show-EditorMoveDetails $moveId
}

function Get-NatureEffectInfo {
  param([int]$NatureId)
  $upIndex = -1
  $downIndex = -1
  $upStat = ""
  $downStat = ""
  $neutral = $true
  if ($NatureId -ge 0) {
    $upIndex = [int][Math]::Floor($NatureId / 5)
    $downIndex = [int]($NatureId % 5)
    $neutral = ($upIndex -eq $downIndex)
    if ($upIndex -ge 0 -and $upIndex -lt $script:NatureStatNames.Count) { $upStat = [string]$script:NatureStatNames[$upIndex] }
    if ($downIndex -ge 0 -and $downIndex -lt $script:NatureStatNames.Count) { $downStat = [string]$script:NatureStatNames[$downIndex] }
  }
  [pscustomobject]@{
    Neutral = $neutral
    UpStat = $upStat
    DownStat = $downStat
    UpText = $(if ($neutral) { "" } else { "+10% $upStat" })
    DownText = $(if ($neutral) { "" } else { "-10% $downStat" })
  }
}

function Get-NatureIdByName {
  param([string]$Name)
  $text = ([string]$Name).Trim()
  if ($text -eq "" -or $null -eq $script:Data -or $null -eq $script:Data.natures) { return $null }
  foreach ($nature in @($script:Data.natures)) {
    if ([string]::Compare($text, [string]$nature.name, $true) -eq 0) { return [int]$nature.id }
  }
  return $null
}

function New-NamedImageCombo {
  param([int]$X, [int]$Y, [int]$W, [string]$Kind = "text")
  $combo = New-Object System.Windows.Forms.ComboBox
  $combo.Location = New-Object System.Drawing.Point($X, $Y)
  $combo.Size = New-Object System.Drawing.Size($W, 24)
  $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  $combo.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::None
  $combo.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::None
  $combo.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
  $combo.ItemHeight = 22
  $combo.MaxDropDownItems = 9
  $combo.IntegralHeight = $false
  $combo.DropDownHeight = 220
  $combo.DropDownWidth = [Math]::Min(320, [Math]::Max($W, 230))
  $combo.Tag = [pscustomobject]@{
    Kind = $Kind; Ids = @(); Names = @(); Types = @(); Key = "";
    NatureUps = @(); NatureDowns = @(); NatureNeutral = @();
    SourceIds = @(); SourceNames = @(); SourceTypes = @();
    SourceNatureUps = @(); SourceNatureDowns = @(); SourceNatureNeutral = @();
    Filter = ""; Filtering = $false
  }
  $combo.Add_DropDown({
    param($sender, $e)
    $sender.IntegralHeight = $false
    $sender.DropDownHeight = 220
    if ([string]$sender.Tag.Kind -eq "nature") {
      $sender.DropDownWidth = [Math]::Max($sender.Width, 320)
    } elseif ([string]$sender.Tag.Kind -eq "ability") {
      $sender.DropDownWidth = [Math]::Max($sender.Width, 320)
    } else {
      $sender.DropDownWidth = [Math]::Min(340, [Math]::Max($sender.Width, 240))
    }
  })
  $combo.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $ids = @($sender.Tag.Ids)
    $name = [string]$sender.Items[$e.Index]
    $id = 0
    if ($e.Index -lt $ids.Count) { $id = [int]$ids[$e.Index] }
    $selected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)
    $backColor = $(if ($selected) { [System.Drawing.SystemColors]::Highlight } else { [System.Drawing.Color]::White })
    if (!$selected -and [string]$sender.Tag.Kind -eq "move") {
      if ($script:CurrentMoveIds.ContainsKey($id)) {
        $backColor = [System.Drawing.Color]::FromArgb(255, 239, 154)
      } elseif ($script:LearnableMoveIds.ContainsKey($id)) {
        $backColor = [System.Drawing.Color]::FromArgb(196, 245, 198)
      }
    }
    $backBrush = New-Object System.Drawing.SolidBrush($backColor)
    $e.Graphics.FillRectangle($backBrush, $e.Bounds)
    $backBrush.Dispose()
    $x = $e.Bounds.X + 3
    $y = $e.Bounds.Y + 2
    $textX = $x
    if ([string]$sender.Tag.Kind -eq "species") {
      $icon = Get-PokemonIconByValues $id $false 0
      if ($null -ne $icon) { $e.Graphics.DrawImage($icon, $x, $y, 22, 20) }
      $textX = $x + 28
    } elseif ([string]$sender.Tag.Kind -eq "item") {
      $icon = Get-ItemIcon $id
      if ($null -ne $icon) { $e.Graphics.DrawImage($icon, $x, $y, 22, 20) }
      $textX = $x + 28
    } elseif ([string]$sender.Tag.Kind -eq "ball") {
      $icon = Get-BallIcon $id
      if ($null -ne $icon) { $e.Graphics.DrawImage($icon, $x, $y, 22, 20) }
      $textX = $x + 28
    } elseif ([string]$sender.Tag.Kind -eq "move") {
      $types = @($sender.Tag.Types)
      $type = -1
      if ($e.Index -lt $types.Count) { $type = [int]$types[$e.Index] }
      $typeIcon = Get-TypeIconById $type
      if ($null -ne $typeIcon) {
        $e.Graphics.DrawImage($typeIcon, $x + 2, $y, 20, 22)
      } else {
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 120, 120))
        $e.Graphics.FillRectangle($brush, $x + 3, $y + 4, 18, 14)
        $brush.Dispose()
      }
      $textX = $x + 30
    }
    if ([string]$sender.Tag.Kind -eq "nature") {
      $foreColor = $(if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::Black })
      $upTexts = @($sender.Tag.NatureUps)
      $downTexts = @($sender.Tag.NatureDowns)
      $neutralValues = @($sender.Tag.NatureNeutral)
      $upText = ""
      $downText = ""
      $neutralNature = $true
      if ($e.Index -lt $upTexts.Count) { $upText = [string]$upTexts[$e.Index] }
      if ($e.Index -lt $downTexts.Count) { $downText = [string]$downTexts[$e.Index] }
      if ($e.Index -lt $neutralValues.Count) { $neutralNature = [bool]$neutralValues[$e.Index] }
      $flags = [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
      if ($e.Bounds.Width -lt 210) {
        $compactRect = New-Object System.Drawing.Rectangle($textX, $e.Bounds.Y, ($e.Bounds.Width - ($textX - $e.Bounds.X) - 4), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $name, $sender.Font, $compactRect, $foreColor, $flags)
        $e.DrawFocusRectangle()
        return
      }
      $effectX = $e.Bounds.X + [Math]::Min(112, [Math]::Max(92, [int]($e.Bounds.Width * 0.36)))
      $nameRect = New-Object System.Drawing.Rectangle($textX, $e.Bounds.Y, [Math]::Max(44, ($effectX - $textX - 4)), $e.Bounds.Height)
      [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $name, $sender.Font, $nameRect, $foreColor, $flags)
      if ($neutralNature) {
        $neutralRect = New-Object System.Drawing.Rectangle($effectX, $e.Bounds.Y, [Math]::Max(40, ($e.Bounds.Right - $effectX - 4)), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, "neutral", $sender.Font, $neutralRect, [System.Drawing.Color]::DimGray, $flags)
      } else {
        $upRect = New-Object System.Drawing.Rectangle($effectX, $e.Bounds.Y, 72, $e.Bounds.Height)
        $downRect = New-Object System.Drawing.Rectangle(($effectX + 74), $e.Bounds.Y, [Math]::Max(70, ($e.Bounds.Right - $effectX - 78)), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $upText, $sender.Font, $upRect, [System.Drawing.Color]::FromArgb(190, 35, 35), $flags)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $downText, $sender.Font, $downRect, [System.Drawing.Color]::FromArgb(35, 95, 190), $flags)
      }
      $e.DrawFocusRectangle()
      return
    }
    $foreColor = $(if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::Black })
    $rect = New-Object System.Drawing.Rectangle($textX, $e.Bounds.Y, ($e.Bounds.Width - ($textX - $e.Bounds.X) - 4), $e.Bounds.Height)
    $flags = [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $name, $sender.Font, $rect, $foreColor, $flags)
    $e.DrawFocusRectangle()
  })
  $combo.Add_TextUpdate({
    param($sender, $e)
    Set-NamedComboFilter $sender $sender.Text
  })
  return $combo
}

function Set-NamedComboFilter {
  param($Combo, [string]$FilterText)
  if ($null -eq $Combo -or $null -eq $Combo.Tag) { return }
  if ($Combo.Tag.Filtering) { return }
  $Combo.Tag.Filtering = $true
  try {
    $text = [string]$FilterText
    $selectionStart = $Combo.SelectionStart
    if ([string]$Combo.Tag.Filter -eq $text -and $Combo.Items.Count -gt 0) { return }
    $sourceIds = @($Combo.Tag.SourceIds)
    $sourceNames = @($Combo.Tag.SourceNames)
    $sourceTypes = @($Combo.Tag.SourceTypes)
    $sourceNatureUps = @($Combo.Tag.SourceNatureUps)
    $sourceNatureDowns = @($Combo.Tag.SourceNatureDowns)
    $sourceNatureNeutral = @($Combo.Tag.SourceNatureNeutral)
    $ids = New-Object System.Collections.ArrayList
    $names = New-Object System.Collections.ArrayList
    $types = New-Object System.Collections.ArrayList
    $natureUps = New-Object System.Collections.ArrayList
    $natureDowns = New-Object System.Collections.ArrayList
    $natureNeutral = New-Object System.Collections.ArrayList
    $Combo.BeginUpdate()
    try {
      $Combo.Items.Clear()
      for ($i = 0; $i -lt $sourceNames.Count; $i++) {
        $name = [string]$sourceNames[$i]
        $idText = $(if ($i -lt $sourceIds.Count) { [string]$sourceIds[$i] } else { "" })
        $upText = $(if ($i -lt $sourceNatureUps.Count) { [string]$sourceNatureUps[$i] } else { "" })
        $downText = $(if ($i -lt $sourceNatureDowns.Count) { [string]$sourceNatureDowns[$i] } else { "" })
        if ($text -ne "" -and
          $name.IndexOf($text, [System.StringComparison]::CurrentCultureIgnoreCase) -lt 0 -and
          $idText.IndexOf($text, [System.StringComparison]::CurrentCultureIgnoreCase) -lt 0 -and
          $upText.IndexOf($text, [System.StringComparison]::CurrentCultureIgnoreCase) -lt 0 -and
          $downText.IndexOf($text, [System.StringComparison]::CurrentCultureIgnoreCase) -lt 0) {
          continue
        }
        [void]$ids.Add([int]$sourceIds[$i])
        [void]$names.Add($name)
        [void]$types.Add($(if ($i -lt $sourceTypes.Count) { [int]$sourceTypes[$i] } else { -1 }))
        [void]$natureUps.Add($upText)
        [void]$natureDowns.Add($downText)
        [void]$natureNeutral.Add($(if ($i -lt $sourceNatureNeutral.Count) { [bool]$sourceNatureNeutral[$i] } else { $true }))
        [void]$Combo.Items.Add($name)
      }
      $Combo.Tag.Ids = @($ids)
      $Combo.Tag.Names = @($names)
      $Combo.Tag.Types = @($types)
      $Combo.Tag.NatureUps = @($natureUps)
      $Combo.Tag.NatureDowns = @($natureDowns)
      $Combo.Tag.NatureNeutral = @($natureNeutral)
      $Combo.Tag.Filter = $text
    } finally {
      $Combo.EndUpdate()
    }
    if ($Combo.Text -ne $text) { $Combo.Text = $text }
    $Combo.SelectionStart = [Math]::Min($selectionStart, $Combo.Text.Length)
    $Combo.SelectionLength = 0
    if (!$Combo.DroppedDown -and $Combo.Focused -and $Combo.IsHandleCreated) {
      [void]$Combo.BeginInvoke([System.Action]{
        try {
          if (!$Combo.IsDisposed -and $Combo.Focused -and !$Combo.DroppedDown) { $Combo.DroppedDown = $true }
        } catch {}
      })
    }
  } finally {
    $Combo.Tag.Filtering = $false
  }
}

function Populate-NamedCombo {
  param($Combo, $Entries, [bool]$IncludeNone = $false, [string]$NoneText = "Ninguno")
  if ($null -eq $Combo) { return }
  $key = ""
  $orderedEntries = @($Entries)
  if ($null -ne $Combo.Tag -and [string]$Combo.Tag.Kind -eq "move") {
    $orderedEntries = @($Entries) | Sort-Object `
      @{ Expression = {
        $id = [int]$_.id
        if ($script:CurrentMoveIds.ContainsKey($id)) { 0 }
        elseif ($script:LearnableMoveIds.ContainsKey($id)) { 1 }
        else { 2 }
      }; Ascending = $true },
      @{ Expression = { [string]$_.name }; Ascending = $true },
      @{ Expression = { [int]$_.id }; Ascending = $true }
    $learnKey = ((@($script:LearnableMoveIds.Keys) | Sort-Object) -join ",")
    $currentKey = ((@($script:CurrentMoveIds.Keys) | Sort-Object) -join ",")
    $key += "current:" + $currentKey + ";learn:" + $learnKey + ";"
  }
  foreach ($entry in @($orderedEntries)) { $key += ([string]$entry.id + ":" + [string]$entry.name + ";") }
  if ($IncludeNone) { $key = "none;" + $key }
  if ($null -ne $Combo.Tag -and [string]$Combo.Tag.Key -eq $key) { return }
  $oldId = Get-NamedComboId $Combo
  $ids = New-Object System.Collections.ArrayList
  $names = New-Object System.Collections.ArrayList
  $types = New-Object System.Collections.ArrayList
  $natureUps = New-Object System.Collections.ArrayList
  $natureDowns = New-Object System.Collections.ArrayList
  $natureNeutral = New-Object System.Collections.ArrayList
  $Combo.BeginUpdate()
  $Combo.Items.Clear()
  if ($IncludeNone) {
    [void]$ids.Add(0)
    [void]$names.Add($NoneText)
    [void]$types.Add(-1)
    [void]$natureUps.Add("")
    [void]$natureDowns.Add("")
    [void]$natureNeutral.Add($true)
    [void]$Combo.Items.Add($NoneText)
  }
  foreach ($entry in @($orderedEntries)) {
    $id = [int]$entry.id
    $name = [string]$entry.name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $natureInfo = $null
    if ($null -ne $Combo.Tag -and [string]$Combo.Tag.Kind -eq "nature") {
      $natureInfo = Get-NatureEffectInfo $id
    }
    [void]$ids.Add($id)
    [void]$names.Add($name)
    [void]$types.Add($(if ($null -ne $entry.type) { [int]$entry.type } else { -1 }))
    [void]$natureUps.Add($(if ($null -ne $natureInfo) { [string]$natureInfo.UpText } else { "" }))
    [void]$natureDowns.Add($(if ($null -ne $natureInfo) { [string]$natureInfo.DownText } else { "" }))
    [void]$natureNeutral.Add($(if ($null -ne $natureInfo) { [bool]$natureInfo.Neutral } else { $true }))
    [void]$Combo.Items.Add($name)
  }
  $Combo.Tag = [pscustomobject]@{
    Kind = $Combo.Tag.Kind; Ids = @($ids); Names = @($names); Types = @($types); Key = $key;
    NatureUps = @($natureUps); NatureDowns = @($natureDowns); NatureNeutral = @($natureNeutral);
    SourceIds = @($ids); SourceNames = @($names); SourceTypes = @($types);
    SourceNatureUps = @($natureUps); SourceNatureDowns = @($natureDowns); SourceNatureNeutral = @($natureNeutral);
    Filter = ""; Filtering = $false
  }
  $Combo.EndUpdate()
  if ($oldId -ne $null) { Set-NamedComboById $Combo $oldId }
}

function Set-NamedComboById {
  param($Combo, [int]$Id)
  if ($null -eq $Combo -or $null -eq $Combo.Tag) { return }
  if ([string]$Combo.Tag.Filter -ne "") { Set-NamedComboFilter $Combo "" }
  $ids = @($Combo.Tag.Ids)
  for ($i = 0; $i -lt $ids.Count; $i++) {
    if ([int]$ids[$i] -eq $Id) {
      $Combo.SelectedIndex = $i
      return
    }
  }
  $name = ""
  if ([string]$Combo.Tag.Kind -eq "species" -and $null -ne $script:Data) {
    $name = Get-EntryName $script:Data.species $Id
  } elseif ([string]$Combo.Tag.Kind -eq "move" -and $null -ne $script:Data) {
    $name = Get-EntryName $script:Data.moves $Id
  } elseif ([string]$Combo.Tag.Kind -eq "item" -and $null -ne $script:Data) {
    $name = Get-EntryName $script:Data.items $Id
  } elseif ([string]$Combo.Tag.Kind -eq "ball") {
    $name = "Ball desconocida"
  }
  $Combo.SelectedIndex = -1
  $Combo.Text = $name
}

function Get-NamedComboId {
  param($Combo)
  if ($null -eq $Combo -or $null -eq $Combo.Tag) { return $null }
  $ids = @($Combo.Tag.Ids)
  if ($Combo.SelectedIndex -ge 0 -and $Combo.SelectedIndex -lt $ids.Count) {
    return [int]$ids[$Combo.SelectedIndex]
  }
  $text = $Combo.Text.Trim()
  $names = @($Combo.Tag.Names)
  for ($i = 0; $i -lt $names.Count; $i++) {
    if ([string]::Compare($text, [string]$names[$i], $true) -eq 0) {
      return [int]$ids[$i]
    }
  }
  return $null
}

function Update-NatureEffectDisplay {
  if ($null -eq $script:NatureUpLabel -or $null -eq $script:NatureDownLabel) { return }
  $natureId = Get-NamedComboId $script:NatureCombo
  if ($natureId -eq $null) { $natureId = -1 }
  if ([int]$natureId -lt 0 -and $null -ne $script:SelectedPokemon) {
    $rawNature = Get-ObjectProperty $script:SelectedPokemon "nature" $null
    if ($rawNature -ne $null -and [string]$rawNature -ne "") {
      try { $natureId = [int]$rawNature } catch {}
    }
  }
  if ([int]$natureId -lt 0 -and $null -ne $script:SelectedPokemon) {
    $byPokemonName = Get-NatureIdByName ([string](Get-ObjectProperty $script:SelectedPokemon "natureName" ""))
    if ($byPokemonName -ne $null) { $natureId = [int]$byPokemonName }
  }
  if ([int]$natureId -lt 0 -and $null -ne $script:NatureCombo) {
    $byComboName = Get-NatureIdByName ([string]$script:NatureCombo.Text)
    if ($byComboName -ne $null) { $natureId = [int]$byComboName }
  }
  $info = Get-NatureEffectInfo ([int]$natureId)
  if ($info.Neutral -and $null -ne $script:NatureCombo -and [string]$script:NatureCombo.Text -ne "Natural") {
    $byVisibleName = Get-NatureIdByName ([string]$script:NatureCombo.Text)
    if ($byVisibleName -ne $null -and [int]$byVisibleName -ne [int]$natureId) {
      $natureId = [int]$byVisibleName
      $info = Get-NatureEffectInfo ([int]$natureId)
    }
  }
  if ($info.Neutral) {
    $script:NatureUpLabel.ForeColor = [System.Drawing.Color]::DimGray
    $script:NatureUpLabel.Text = "Neutral"
    $script:NatureDownLabel.Text = ""
    Set-Tip $script:NatureUpLabel "Esta naturaleza no sube ni baja estadisticas."
    Set-Tip $script:NatureDownLabel ""
    return
  }
  $script:NatureUpLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 35, 35)
  $script:NatureDownLabel.ForeColor = [System.Drawing.Color]::FromArgb(35, 95, 190)
  $script:NatureUpLabel.Text = [string]$info.UpText
  $script:NatureDownLabel.Text = [string]$info.DownText
  Set-Tip $script:NatureUpLabel ("Sube " + [string]$info.UpText)
  Set-Tip $script:NatureDownLabel ("Baja " + [string]$info.DownText)
}

function Set-RandomNature {
  $natureId = Get-Random -Minimum 0 -Maximum 25
  Set-NumberValue $script:PokeNatureFlag $natureId
  Set-NamedComboById $script:NatureCombo $natureId
  Update-NatureEffectDisplay
  Mark-Dirty
}

function Sync-IdFromCombo {
  param($Combo, $NumberControl, [int]$Min = 0)
  if ($script:LoadingUi -or $null -eq $Combo -or $null -eq $NumberControl) { return }
  $id = Get-NamedComboId $Combo
  if ($id -eq $null -or $id -lt $Min) { return }
  Set-NumberValue $NumberControl $id
  Mark-Dirty
}

function Get-CurrentSpeciesId {
  $id = Get-NamedComboId $script:SpeciesCombo
  if ($id -ne $null -and $id -gt 0) { return [int]$id }
  if ($null -ne $script:PokeSpecies) { return [int]$script:PokeSpecies.Value }
  return 1
}

function Update-PokemonPreviewFromInputs {
  if ($null -eq $script:PokePreview) { return }
  $species = Get-CurrentSpeciesId
  $form = 0
  if ($null -ne $script:PokeForm) { $form = [int]$script:PokeForm.Value }
  $shiny = ($null -ne $script:PokeShiny -and $script:PokeShiny.Checked)
  $script:PokePreview.Image = Get-PokemonIconByValues $species $shiny $form
  if ($null -ne $script:SpeciesCombo) {
    $script:PokeSpeciesName.Text = [string]$script:SpeciesCombo.Text
  }
}

function Update-BallPreview {
  if ($null -eq $script:PokeBallPreview -or $null -eq $script:PokeBallUsed) { return }
  $script:PokeBallPreview.Image = Get-BallIcon ([int]$script:PokeBallUsed.Value)
}

function Populate-EditorNamedControls {
  if ($null -eq $script:Data) { return }
  Populate-NamedCombo $script:SpeciesCombo $script:Data.species $false ""
  Populate-NamedCombo $script:CreateSpeciesCombo $script:Data.species $false ""
  Populate-NamedCombo $script:ItemCombo $script:Data.items $true "Sin objeto"
  Populate-NamedCombo $script:PokeBallCombo (Get-BallEntries) $false ""
  Populate-NamedCombo $script:StatusCombo $script:Data.statuses $false ""
  $natureEntries = New-Object System.Collections.ArrayList
  [void]$natureEntries.Add([pscustomobject]@{ id = -1; name = "Natural" })
  foreach ($nature in @($script:Data.natures)) { [void]$natureEntries.Add($nature) }
  Populate-NamedCombo $script:NatureCombo @($natureEntries) $false ""
  $abilityEntries = @(
    [pscustomobject]@{ id = -1; name = "Automatica" },
    [pscustomobject]@{ id = 0; name = "Habilidad 1" },
    [pscustomobject]@{ id = 1; name = "Habilidad 2" },
    [pscustomobject]@{ id = 2; name = "Habilidad oculta" }
  )
  Populate-NamedCombo $script:AbilityCombo $abilityEntries $false ""
  $genderEntries = @(
    [pscustomobject]@{ id = -1; name = "Automatico" },
    [pscustomobject]@{ id = 0; name = "Macho" },
    [pscustomobject]@{ id = 1; name = "Hembra" }
  )
  Populate-NamedCombo $script:GenderCombo $genderEntries $false ""
  foreach ($combo in @($script:MoveCombos)) {
    Populate-NamedCombo $combo $script:Data.moves $true "Sin movimiento"
  }
}

function Get-BaseStatColor {
  param([int]$Value)
  if ($Value -ge 120) { return [System.Drawing.Color]::FromArgb(145, 235, 145) }
  if ($Value -ge 90) { return [System.Drawing.Color]::FromArgb(206, 245, 160) }
  if ($Value -ge 60) { return [System.Drawing.Color]::FromArgb(255, 235, 153) }
  if ($Value -ge 40) { return [System.Drawing.Color]::FromArgb(255, 197, 143) }
  return [System.Drawing.Color]::FromArgb(255, 167, 167)
}

function Get-BaseStatsForDisplay {
  param($Pokemon)
  $base = @()
  if ($null -ne $Pokemon -and $null -ne $Pokemon.baseStats) {
    $base = @($Pokemon.baseStats)
  }
  while ($base.Count -lt 6) { $base += 0 }
  return @([int]$base[0], [int]$base[1], [int]$base[2], [int]$base[3], [int]$base[4], [int]$base[5])
}

function Get-ActualStatsForDisplay {
  param($Pokemon)
  if ($null -eq $Pokemon) { return @(0, 0, 0, 0, 0, 0) }
  $stats = $Pokemon.stats
  return @(
    [int]$Pokemon.totalhp,
    [int]$stats.attack,
    [int]$stats.defense,
    [int]$stats.spatk,
    [int]$stats.spdef,
    [int]$stats.speed
  )
}

function Update-StatsDisplay {
  param($Pokemon)
  if ($null -eq $Pokemon) { return }
  $base = Get-BaseStatsForDisplay $Pokemon
  $actual = Get-ActualStatsForDisplay $Pokemon
  for ($i = 0; $i -lt 6; $i++) {
    $color = Get-BaseStatColor ([int]$base[$i])
    if ($script:BaseStatLabels.Count -gt $i -and $null -ne $script:BaseStatLabels[$i]) {
      $script:BaseStatLabels[$i].Text = [string][int]$base[$i]
      $script:BaseStatLabels[$i].BackColor = $color
    }
    if ($script:ActualStatLabels.Count -gt $i -and $null -ne $script:ActualStatLabels[$i]) {
      $script:ActualStatLabels[$i].Text = [string][int]$actual[$i]
    }
  }
}

function Style-PokemonGrid {
  param($Grid)
  if ($null -eq $Grid) { return }
  $Grid.RowTemplate.Height = 54
  $Grid.ColumnHeadersHeight = 28
  $Grid.EnableHeadersVisualStyles = $false
  $Grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
  $Grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
  $Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(74, 144, 226)
  $Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
  if ($Grid.Columns.Contains("Icono")) {
    $Grid.Columns["Icono"].HeaderText = ""
    $Grid.Columns["Icono"].Width = 56
    $Grid.Columns["Icono"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
    if ($Grid.Columns["Icono"] -is [System.Windows.Forms.DataGridViewImageColumn]) {
      $Grid.Columns["Icono"].ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
    } else {
      $Grid.Columns["Icono"].Visible = $false
    }
  }
  if ($Grid.Columns.Contains("Slot")) { $Grid.Columns["Slot"].Width = 42; $Grid.Columns["Slot"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None }
  if ($Grid.Columns.Contains("Nivel")) { $Grid.Columns["Nivel"].Width = 55; $Grid.Columns["Nivel"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None }
  if ($Grid.Columns.Contains("Estado")) { $Grid.Columns["Estado"].Width = 60; $Grid.Columns["Estado"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None }
  if ($Grid.Columns.Contains("Shiny")) { $Grid.Columns["Shiny"].Width = 58; $Grid.Columns["Shiny"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None }
}

function Test-SameSlotTag {
  param($A, $B)
  if ($null -eq $A -or $null -eq $B) { return $false }
  if ([string]$A.Loc -ne [string]$B.Loc) { return $false }
  if ([string]$A.Loc -eq "party") { return [int]$A.Index -eq [int]$B.Index }
  if ([string]$A.Loc -eq "box") { return ([int]$A.Box -eq [int]$B.Box -and [int]$A.Slot -eq [int]$B.Slot) }
  return $false
}

function Get-RawStatIndex {
  param([int]$DisplayIndex)
  if ($DisplayIndex -ge 0 -and $DisplayIndex -lt $script:StatDisplayToRaw.Count) {
    return [int]$script:StatDisplayToRaw[$DisplayIndex]
  }
  return $DisplayIndex
}

function Get-DisplayStatValue {
  param($Values, [int]$DisplayIndex)
  $items = @($Values)
  $rawIndex = Get-RawStatIndex $DisplayIndex
  if ($items.Count -gt $rawIndex) { return [int]$items[$rawIndex] }
  if ($items.Count -gt $DisplayIndex) { return [int]$items[$DisplayIndex] }
  return 0
}

function Add-EditorStatValues {
  param([hashtable]$Values)
  for ($displayIndex = 0; $displayIndex -lt 6; $displayIndex++) {
    $rawIndex = Get-RawStatIndex $displayIndex
    $Values["iv$rawIndex"] = [int]$script:IvNums[$displayIndex].Value
    $Values["ev$rawIndex"] = [int]$script:EvNums[$displayIndex].Value
  }
}

function Get-PokemonSlotTip {
  param($Pokemon, [string]$Loc, [int]$Index = -1, [int]$Box = -1, [int]$Slot = -1)
  if ($null -eq $Pokemon) {
    $where = $(if ($Loc -eq "party") { "Party slot " + ($Index + 1) } else { "Box " + ($Box + 1) + ", slot " + ($Slot + 1) })
    return $where + ": empty"
  }
  $gender = ""
  if ($null -ne $Pokemon.genderflag) {
    if ([int]$Pokemon.genderflag -eq 0) { $gender = " (M)" }
    elseif ([int]$Pokemon.genderflag -eq 1) { $gender = " (F)" }
  }
  $ivs = @($Pokemon.iv)
  $ivText = ""
  if ($ivs.Count -ge 6) {
    $ivDisplay = @()
    for ($i = 0; $i -lt 6; $i++) { $ivDisplay += (Get-DisplayStatValue $ivs $i) }
    $ivText = "IVs: {0} HP / {1} Atk / {2} Def / {3} SpA / {4} SpD / {5} Spe" -f $ivDisplay[0], $ivDisplay[1], $ivDisplay[2], $ivDisplay[3], $ivDisplay[4], $ivDisplay[5]
  }
  $moves = @($Pokemon.moves) | ForEach-Object { if ($null -ne $_ -and [string]$_.name -ne "") { "- " + [string]$_.name } }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add(("{0}{1}" -f $Pokemon.speciesName, $gender))
  if ($ivText -ne "") { $lines.Add($ivText) }
  if ([string]$Pokemon.abilityName -ne "") { $lines.Add("Ability: " + [string]$Pokemon.abilityName) }
  $lines.Add("Level: " + [string]$Pokemon.level)
  if ([string]$Pokemon.natureName -ne "") { $lines.Add([string]$Pokemon.natureName + " Nature") }
  foreach ($move in $moves) { $lines.Add($move) }
  return ($lines -join [Environment]::NewLine)
}

function Select-SlotPokemon {
  param($Tag, [bool]$SwitchToEditor = $false)
  if ($null -eq $Tag) { return }
  if ($script:Dirty) { $script:Dirty = $false }
  $script:SelectedSlotTag = $Tag
  if ($Tag.Loc -eq "party" -and $null -ne $script:PartyGrid -and $script:PartyGrid.Rows.Count -gt $Tag.Index) {
    try { $script:PartyGrid.CurrentCell = $script:PartyGrid.Rows[$Tag.Index].Cells[0] } catch {}
  } elseif ($Tag.Loc -eq "box" -and $null -ne $script:PCGrid -and $script:PCGrid.Rows.Count -gt $Tag.Slot) {
    try { $script:PCGrid.CurrentCell = $script:PCGrid.Rows[$Tag.Slot].Cells[0] } catch {}
  }
  if ($Tag.Empty) {
    $script:StatusLabel.Text = $Tag.ToolTip
    Refresh-PartyTab
    Refresh-PCTab
    return
  }
  $pokemon = Find-PokemonEntry $Tag.Loc $Tag.Index $Tag.Box $Tag.Slot
  if ($null -eq $pokemon) {
    $script:StatusLabel.Text = "No hay Pokemon en ese hueco."
    return
  }
  $script:SelectedPokemon = $pokemon
  $script:LoadingUi = $true
  if ($Tag.Loc -eq "party") {
    $script:PokemonSource.SelectedIndex = 0
  } elseif ($Tag.Loc -eq "box") {
    $script:PokemonSource.SelectedIndex = 1
    if ($script:PokemonBox.Items.Count -gt $Tag.Box) { $script:PokemonBox.SelectedIndex = $Tag.Box }
  }
  $script:LoadingUi = $false
  Fill-PokemonFields $pokemon
  $script:StatusLabel.Text = $Tag.ToolTip
  if ($SwitchToEditor) { $tabs.SelectedTab = $pokemonTab }
  Refresh-PartyTab
  Refresh-PCTab
}

function Invoke-SlotMove {
  param($SourceTag, $TargetTag)
  if ($null -eq $SourceTag -or $null -eq $TargetTag) { return }
  if ($SourceTag.Empty) { return }
  if (Test-SameSlotTag $SourceTag $TargetTag) { return }
  Apply-LocalSlotMove $SourceTag $TargetTag
  if (!$TargetTag.Empty) {
    Send-EditorCommand "pokemon_swap" @{
      loc = [string]$SourceTag.Loc
      index = [int]$SourceTag.Index
      box = [int]$SourceTag.Box
      slot = [int]$SourceTag.Slot
      destLoc = [string]$TargetTag.Loc
      destIndex = [int]$TargetTag.Index
      destBox = [int]$TargetTag.Box
      destSlot = [int]$TargetTag.Slot
    }
    return
  }
  $values = @{
    loc = [string]$SourceTag.Loc
    index = [int]$SourceTag.Index
    box = [int]$SourceTag.Box
    slot = [int]$SourceTag.Slot
    destLoc = [string]$TargetTag.Loc
    destIndex = [int]$TargetTag.Index
    destBox = [int]$TargetTag.Box
    destSlot = [int]$TargetTag.Slot
    replace = $false
  }
  Send-EditorCommand "pokemon_move" $values
}

function Invoke-DraftDrop {
  param($TargetTag)
  if ($null -eq $TargetTag) { return }
  $values = $script:DraggedDraftValues
  if ($null -eq $values) { $values = Get-EditedPokemonValues }
  if ($null -eq $values) { return }
  $values["destLoc"] = [string]$TargetTag.Loc
  $values["destIndex"] = [int]$TargetTag.Index
  $values["destBox"] = [int]$TargetTag.Box
  $values["destSlot"] = [int]$TargetTag.Slot
  $values["replace"] = !$TargetTag.Empty
  $source = [pscustomobject]@{
    Empty = $false
    Loc = [string]$values["loc"]
    Index = [int]$values["index"]
    Box = [int]$values["box"]
    Slot = [int]$values["slot"]
  }
  if (Test-SameSlotTag $source $TargetTag) {
    Apply-LocalDraftDrop $values $TargetTag
    Send-EditorCommand "pokemon_set" $values
  } else {
    Apply-LocalDraftDrop $values $TargetTag
    Send-EditorCommand "pokemon_place_edited" $values
  }
}

function Invoke-SlotCloneTo {
  param($SourceTag, $TargetTag)
  if ($null -eq $SourceTag -or $null -eq $TargetTag -or $SourceTag.Empty) { return }
  $replace = !$TargetTag.Empty
  if ($replace) {
    $result = [System.Windows.Forms.MessageBox]::Show("Ese hueco ya tiene un Pokemon. Reemplazarlo con una copia?", "Set Pokemon", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  }
  Send-EditorCommand "pokemon_clone" @{
    loc = [string]$SourceTag.Loc
    index = [int]$SourceTag.Index
    box = [int]$SourceTag.Box
    slot = [int]$SourceTag.Slot
    destLoc = [string]$TargetTag.Loc
    destIndex = [int]$TargetTag.Index
    destBox = [int]$TargetTag.Box
    destSlot = [int]$TargetTag.Slot
    replace = $replace
  }
}

function Invoke-ShinyMoveTo {
  param($TargetTag)
  $SourceTag = $script:SelectedSlotTag
  if ($null -eq $SourceTag -or $null -eq $TargetTag -or $SourceTag.Empty -or $TargetTag.Empty) { return }
  if (Test-SameSlotTag $SourceTag $TargetTag) { return }
  $source = Find-PokemonEntry $SourceTag.Loc $SourceTag.Index $SourceTag.Box $SourceTag.Slot
  $target = Find-PokemonEntry $TargetTag.Loc $TargetTag.Index $TargetTag.Box $TargetTag.Slot
  if ($null -eq $source -or $null -eq $target) { return }
  if (![bool]$source.shiny) {
    [void][System.Windows.Forms.MessageBox]::Show("El Pokemon seleccionado no es shiny.", "Mover shiny", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    return
  }
  if ([bool]$target.shiny) {
    [void][System.Windows.Forms.MessageBox]::Show("El Pokemon destino ya es shiny.", "Mover shiny", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    return
  }
  $result = [System.Windows.Forms.MessageBox]::Show(("Mover el shiny de {0} a {1}?" -f $source.nickname, $target.nickname), "Mover shiny", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  Set-ObjectProperty $source "shiny" $false
  Set-ObjectProperty $source "shinyflag" $false
  Set-ObjectProperty $target "shiny" $true
  Set-ObjectProperty $target "shinyflag" $true
  Send-EditorCommand "pokemon_set" @{ loc = [string]$SourceTag.Loc; index = [int]$SourceTag.Index; box = [int]$SourceTag.Box; slot = [int]$SourceTag.Slot; shiny = $false }
  Send-EditorCommand "pokemon_set" @{ loc = [string]$TargetTag.Loc; index = [int]$TargetTag.Index; box = [int]$TargetTag.Box; slot = [int]$TargetTag.Slot; shiny = $true }
  if ($null -ne $script:SelectedPokemon -and (Test-SameSlotTag $SourceTag $script:SelectedSlotTag)) {
    $script:PokeShiny.Checked = [bool]$source.shiny
    Update-PokemonPreviewFromInputs
  }
  Refresh-PokemonSlotViews
  Update-PendingStatus "Shiny movido. Guarda partida para aplicarlo al juego."
}

function Ensure-SlotContextMenu {
  if ($null -ne $script:SlotContextMenu) { return $script:SlotContextMenu }
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $view = New-Object System.Windows.Forms.ToolStripMenuItem("View")
  $set = New-Object System.Windows.Forms.ToolStripMenuItem("Set")
  $moveShiny = New-Object System.Windows.Forms.ToolStripMenuItem("Mover shiny aqui")
  $delete = New-Object System.Windows.Forms.ToolStripMenuItem("Delete")
  $view.Add_Click({ Select-SlotPokemon $script:SlotMenuTag $true })
  $set.Add_Click({
    if ($null -ne $script:SelectedPokemon) {
      Invoke-DraftDrop $script:SlotMenuTag
    }
  })
  $moveShiny.Add_Click({ Invoke-ShinyMoveTo $script:SlotMenuTag })
  $delete.Add_Click({
    $tag = $script:SlotMenuTag
    if ($null -eq $tag -or $tag.Empty) { return }
    $result = [System.Windows.Forms.MessageBox]::Show("Esto borrara el Pokemon seleccionado.", "Delete Pokemon", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
      Send-EditorCommand "pokemon_delete" @{ loc = [string]$tag.Loc; index = [int]$tag.Index; box = [int]$tag.Box; slot = [int]$tag.Slot }
    }
  })
  [void]$menu.Items.Add($view)
  [void]$menu.Items.Add($set)
  [void]$menu.Items.Add($moveShiny)
  [void]$menu.Items.Add($delete)
  $script:SlotContextMenu = $menu
  return $menu
}

function New-SlotPictureBox {
  $box = New-Object System.Windows.Forms.PictureBox
  $box.Size = New-Object System.Drawing.Size(68, 56)
  $box.Margin = New-Object System.Windows.Forms.Padding(0)
  $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $box.BackColor = [System.Drawing.Color]::FromArgb(124, 202, 126)
  $box.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
  $box.AllowDrop = $true
  $box.Add_MouseDown({
    param($sender, $e)
    $tag = $sender.Tag
    if ($null -eq $tag) { return }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
      $script:SlotMenuTag = $tag
      $menu = Ensure-SlotContextMenu
      $menu.Items[0].Enabled = !$tag.Empty
      $menu.Items[1].Enabled = ($null -ne $script:SelectedPokemon)
      $sourcePokemon = $script:SelectedPokemon
      $targetPokemon = $(if ($tag.Empty) { $null } else { Find-PokemonEntry $tag.Loc $tag.Index $tag.Box $tag.Slot })
      $menu.Items[2].Enabled = (!$tag.Empty -and $null -ne $sourcePokemon -and $null -ne $targetPokemon -and [bool]$sourcePokemon.shiny -and ![bool]$targetPokemon.shiny -and !(Test-SameSlotTag $script:SelectedSlotTag $tag))
      $menu.Items[3].Enabled = !$tag.Empty
      $menu.Show($sender, $e.Location)
      return
    }
    Select-SlotPokemon $tag $false
    if (!$tag.Empty) {
      $script:PendingDragTag = $tag
      $script:PendingDragPoint = $e.Location
    }
  })
  $box.Add_MouseMove({
    param($sender, $e)
    if ($null -eq $script:PendingDragTag -or $null -eq $script:PendingDragPoint) { return }
    if (($e.Button -band [System.Windows.Forms.MouseButtons]::Left) -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $dx = [Math]::Abs($e.X - $script:PendingDragPoint.X)
    $dy = [Math]::Abs($e.Y - $script:PendingDragPoint.Y)
    $dragSize = [System.Windows.Forms.SystemInformation]::DragSize
    if ($dx -lt [int]($dragSize.Width / 2) -and $dy -lt [int]($dragSize.Height / 2)) { return }
    $script:DraggedSlotTag = $script:PendingDragTag
    $script:DraggedDraftValues = $null
    $script:PendingDragTag = $null
    $script:PendingDragPoint = $null
    [void]$sender.DoDragDrop("pokemon-slot", [System.Windows.Forms.DragDropEffects]::Move)
    $script:DraggedSlotTag = $null
  })
  $box.Add_MouseUp({
    $script:PendingDragTag = $null
    $script:PendingDragPoint = $null
  })
  $box.Add_DoubleClick({
    param($sender, $e)
    $tag = $sender.Tag
    if ($null -eq $tag -or $tag.Empty) { return }
    Select-SlotPokemon $tag $true
  })
  $box.Add_DragEnter({
    param($sender, $e)
    if ($null -ne $script:DraggedDraftValues) {
      $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    } elseif ($null -ne $script:DraggedSlotTag) {
      $e.Effect = [System.Windows.Forms.DragDropEffects]::Move
    } else {
      $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
  })
  $box.Add_DragDrop({
    param($sender, $e)
    if ($null -ne $script:DraggedDraftValues) {
      Invoke-DraftDrop $sender.Tag
    } else {
      Invoke-SlotMove $script:DraggedSlotTag $sender.Tag
    }
    $script:DraggedSlotTag = $null
    $script:DraggedDraftValues = $null
  })
  $box.Add_GiveFeedback({
    param($sender, $e)
    $e.UseDefaultCursors = $true
  })
  return $box
}

function Set-SlotPicture {
  param($PictureBox, $Pokemon, [string]$Loc, [int]$Index = -1, [int]$Box = -1, [int]$Slot = -1)
  if ($null -eq $PictureBox) { return }
  $empty = ($null -eq $Pokemon)
  $PictureBox.Image = $(if ($empty) { $null } else { Get-PokemonIcon $Pokemon })
  $tag = [pscustomobject]@{
    Empty = $empty
    Loc = $Loc
    Index = $Index
    Box = $Box
    Slot = $Slot
    ToolTip = ""
  }
  $isSelected = Test-SameSlotTag $script:SelectedSlotTag $tag
  $PictureBox.BackColor = $(if ($isSelected) { [System.Drawing.Color]::FromArgb(96, 168, 180) } elseif ($empty) { [System.Drawing.Color]::FromArgb(139, 214, 142) } else { [System.Drawing.Color]::FromArgb(114, 194, 130) })
  $PictureBox.BorderStyle = $(if ($isSelected) { [System.Windows.Forms.BorderStyle]::Fixed3D } else { [System.Windows.Forms.BorderStyle]::FixedSingle })
  $tip = Get-PokemonSlotTip $Pokemon $Loc $Index $Box $Slot
  $tag.ToolTip = $tip
  $PictureBox.Tag = [pscustomobject]@{
    Empty = $empty
    Loc = $Loc
    Index = $Index
    Box = $Box
    Slot = $Slot
    ToolTip = $tip
  }
  Set-Tip $PictureBox $tip
}

function Update-SpeciesPreview {
  param($PictureBox, $NumberControl)
  if ($null -eq $PictureBox -or $null -eq $NumberControl) { return }
  $pseudo = [pscustomobject]@{ species = [int]$NumberControl.Value; form = 0; shiny = $false }
  $PictureBox.Image = Get-PokemonIcon $pseudo
  $name = ""
  if ($null -ne $script:Data) { $name = Get-NameFromList $script:Data.species ([int]$NumberControl.Value) }
  Set-Tip $PictureBox ("Vista previa de especie {0}: {1}" -f ([int]$NumberControl.Value), $name)
}


function Mark-Dirty {
  if (!$script:LoadingUi -and !$script:HistoryRestoring) {
    $script:Dirty = $true
    if ($null -ne $script:StatusLabel) {
      $script:StatusLabel.Text = "Cambios locales pendientes. Nada se aplica ni se guarda hasta Archivo > Guardar partida."
    }
    Request-HistoryCheckpoint "Pokemon modificado" "Pokemon"
  }
}

function Register-DirtyControl {
  param($Control)
  if ($null -eq $Control) { return }
  if ($Control -is [System.Windows.Forms.TextBox]) {
    $Control.Add_TextChanged({ Mark-Dirty })
  } elseif ($Control -is [System.Windows.Forms.NumericUpDown]) {
    $Control.Add_ValueChanged({ Mark-Dirty })
  } elseif ($Control -is [System.Windows.Forms.ComboBox]) {
    $Control.Add_SelectedIndexChanged({ Mark-Dirty })
    $Control.Add_TextChanged({ Mark-Dirty })
  } elseif ($Control -is [System.Windows.Forms.CheckBox]) {
    $Control.Add_CheckedChanged({ Mark-Dirty })
  } elseif ($Control -is [System.Windows.Forms.CheckedListBox]) {
    $Control.Add_ItemCheck({ if (!$script:LoadingUi -and !$script:HistoryRestoring) { $script:Dirty = $true; Request-HistoryCheckpoint "Cambio local" "Campo" } })
  }
}

function Get-ActiveLeafControl {
  if ($null -eq $form) { return $null }
  $ctrl = $form.ActiveControl
  while ($null -ne $ctrl -and $ctrl -is [System.Windows.Forms.ContainerControl] -and $null -ne $ctrl.ActiveControl) {
    $ctrl = $ctrl.ActiveControl
  }
  return $ctrl
}

function Test-UserEditing {
  $ctrl = Get-ActiveLeafControl
  if ($null -eq $ctrl) { return $false }
  return (
    $ctrl -is [System.Windows.Forms.TextBox] -or
    $ctrl -is [System.Windows.Forms.NumericUpDown] -or
    $ctrl -is [System.Windows.Forms.ComboBox] -or
    $ctrl -is [System.Windows.Forms.CheckBox] -or
    $ctrl -is [System.Windows.Forms.CheckedListBox] -or
    $ctrl -is [System.Windows.Forms.DataGridView]
  )
}

function Load-LiveData {
  $script:Data = Read-JsonFile $script:DataPath
  $script:State = Read-JsonFile $script:StatePath
  [void](Update-StateBagCache)
  $result = Read-JsonFile $script:ResultPath
  if ($null -ne $result) {
    $script:StatusLabel.Text = ("Ultimo resultado: {0} - {1}" -f ($(if ($result.ok) { "OK" } else { "ERROR" }), $result.message))
  } elseif ($null -eq $script:State) {
    $script:StatusLabel.Text = "Esperando datos del juego. Abre/carga una partida y pulsa F7 desde el juego."
  } else {
    $script:StatusLabel.Text = "Datos cargados: " + $script:State.generatedAt
  }
}

function Refresh-TrainerTab {
  if ($null -eq $script:State -or $null -eq $script:State.trainer -or !$script:State.trainer.loaded) { return }
  $script:LoadingUi = $true
  $t = $script:State.trainer
  $script:TrainerName.Text = [string]$t.name
  $script:TrainerMoney.Value = [decimal][Math]::Max(0, [Math]::Min([int64]$script:TrainerMoney.Maximum, [int64]$t.money))
  $script:TrainerId.Value = [decimal][Math]::Max(0, [Math]::Min([int64]$script:TrainerId.Maximum, [int64]$t.id))
  $script:TrainerType.Value = [decimal][int]$t.trainertype
  $script:TrainerOutfit.Value = [decimal][int]$t.outfit
  $script:TrainerLanguage.Value = [decimal][int]$t.language
  $script:TrainerPokedex.Checked = [bool]$t.pokedex
  $script:TrainerPokegear.Checked = [bool]$t.pokegear
  $script:TrainerNuzlocke.Checked = [bool]$script:State.global.nuzlocke
  if ($null -ne $form) {
    $form.Text = "SebiHeX | $($t.name) [Pokemon Z]"
  }
  $script:Badges.Items.Clear()
  foreach ($badge in @($t.badges)) {
    $idx = [int]$badge.index
    [void]$script:Badges.Items.Add(("Medalla {0}" -f ($idx + 1)), [bool]$badge.value)
  }
  $script:TrainerSummary.Text = "ID publico: $($t.publicID) | ID secreto: $($t.secretID) | Medallas: $($t.numbadges) | Pokemon: $($t.pokemonCount)"
  $script:LoadingUi = $false
}

function Get-SelectedPokemonList {
  if ($script:PokemonSource.SelectedIndex -eq 0) {
    return @($script:State.party)
  }
  $boxIndex = [Math]::Max(0, $script:PokemonBox.SelectedIndex)
  if ($null -eq $script:State.storage -or $null -eq $script:State.storage.boxes) { return @() }
  $box = @($script:State.storage.boxes)[$boxIndex]
  if ($null -eq $box) { return @() }
  return @($box.pokemon)
}

function Find-PokemonEntry {
  param([string]$Loc, [int]$Index = -1, [int]$Box = -1, [int]$Slot = -1)
  if ($null -eq $script:State) { return $null }
  if ($Loc -eq "party") {
    foreach ($pokemon in @($script:State.party)) {
      if ([int]$pokemon.index -eq $Index) { return $pokemon }
    }
  } elseif ($Loc -eq "box") {
    if ($null -eq $script:State.storage -or $null -eq $script:State.storage.boxes) { return $null }
    $boxInfo = @($script:State.storage.boxes)[$Box]
    if ($null -eq $boxInfo) { return $null }
    foreach ($pokemon in @($boxInfo.pokemon)) {
      if ([int]$pokemon.slot -eq $Slot) { return $pokemon }
    }
  }
  return $null
}

function Open-PokemonEditor {
  param([string]$Loc, [int]$Index = -1, [int]$Box = -1, [int]$Slot = -1)
  if ($script:Dirty) { $script:Dirty = $false }
  $pokemon = Find-PokemonEntry $Loc $Index $Box $Slot
  if ($null -eq $pokemon) {
    $script:StatusLabel.Text = "No hay Pokemon en ese hueco."
    return
  }
  $script:SelectedPokemon = $pokemon
  $script:LoadingUi = $true
  if ($Loc -eq "party") {
    $script:PokemonSource.SelectedIndex = 0
  } elseif ($Loc -eq "box") {
    $script:PokemonSource.SelectedIndex = 1
    if ($script:PokemonBox.Items.Count -gt $Box) { $script:PokemonBox.SelectedIndex = $Box }
  }
  $script:LoadingUi = $false
  Fill-PokemonFields $pokemon
  $tabs.SelectedTab = $pokemonTab
}

function Refresh-PokemonList {
  if ($null -eq $script:State) { return }
  $script:LoadingUi = $true
  $script:PokemonBox.Items.Clear()
  if ($null -ne $script:State.storage -and $null -ne $script:State.storage.boxes) {
    foreach ($box in @($script:State.storage.boxes)) {
      [void]$script:PokemonBox.Items.Add(("{0}. {1} ({2})" -f ([int]$box.index + 1), $box.name, $box.count))
    }
  }
  if ($script:PokemonBox.Items.Count -gt 0 -and $script:PokemonBox.SelectedIndex -lt 0) {
    $script:PokemonBox.SelectedIndex = [int]$script:State.storage.currentBox
  }
  $script:PokemonBox.Enabled = ($script:PokemonSource.SelectedIndex -eq 1)
  if ($null -ne $script:BoxName -and $script:PokemonBox.SelectedIndex -ge 0 -and $null -ne $script:State.storage.boxes) {
    $boxInfo = @($script:State.storage.boxes)[$script:PokemonBox.SelectedIndex]
    if ($null -ne $boxInfo) { $script:BoxName.Text = [string]$boxInfo.name }
  }
  if ($null -ne $script:DestBox -and $script:PokemonBox.SelectedIndex -ge 0) {
    Set-NumberValue $script:DestBox ([int]$script:PokemonBox.SelectedIndex + 1)
  }
  $list = Get-SelectedPokemonList
  $script:PokemonList.Items.Clear()
  foreach ($pokemon in $list) {
    [void]$script:PokemonList.Items.Add((Format-Pokemon $pokemon))
  }
  $script:LoadingUi = $false
  if ($script:PokemonList.Items.Count -gt 0 -and $script:PokemonList.SelectedIndex -lt 0) {
    $script:PokemonList.SelectedIndex = 0
    Select-PokemonByIndex 0
  }
}

function Refresh-PartyTab {
  if ($null -eq $script:State -or $null -eq $script:PartyGrid) { return }
  $rows = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt 6; $i++) {
    $pokemon = Find-PokemonEntry "party" $i
    [void]$rows.Add([pscustomobject]@{
      Icono = $(Get-PokemonIcon $pokemon)
      Slot = $i + 1
      Nombre = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.nickname })
      Especie = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.speciesName })
      Nivel = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.level })
      PS = $(if ($null -eq $pokemon) { "" } else { "{0}/{1}" -f $pokemon.hp, $pokemon.totalhp })
      Objeto = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.itemName })
      Estado = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.status })
      Shiny = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.shiny })
      Loc = "party"
      Index = $i
      Box = -1
      SlotIndex = -1
    })
  }
  $script:PartyGrid.DataSource = $rows
  foreach ($colName in @("Loc", "Index", "Box", "SlotIndex")) {
    if ($script:PartyGrid.Columns.Contains($colName)) { $script:PartyGrid.Columns[$colName].Visible = $false }
  }
  Style-PokemonGrid $script:PartyGrid
  if ($null -ne $script:PartySlots -and $script:PartySlots.Count -ge 6) {
    for ($i = 0; $i -lt 6; $i++) {
      Set-SlotPicture $script:PartySlots[$i] (Find-PokemonEntry "party" $i) "party" $i -1 -1
    }
  }
  if ($null -ne $script:HexPartySlots -and $script:HexPartySlots.Count -ge 6) {
    for ($i = 0; $i -lt 6; $i++) {
      Set-SlotPicture $script:HexPartySlots[$i] (Find-PokemonEntry "party" $i) "party" $i -1 -1
    }
  }
  if ($null -ne $script:PartyCreatePreview) {
    Update-SpeciesPreview $script:PartyCreatePreview $script:PartyCreateSpecies
  }
}

function Refresh-PCTab {
  if ($null -eq $script:State -or $null -eq $script:PCGrid) { return }
  if ($null -eq $script:State.storage -or $null -eq $script:State.storage.boxes) { return }
  $script:LoadingUi = $true
  $current = [Math]::Max(0, $script:PCBox.SelectedIndex)
  $script:PCBox.Items.Clear()
  foreach ($box in @($script:State.storage.boxes)) {
    [void]$script:PCBox.Items.Add(("{0}. {1} ({2})" -f ([int]$box.index + 1), $box.name, $box.count))
  }
  if ($script:PCBox.Items.Count -gt 0) {
    if ($current -lt 0 -or $current -ge $script:PCBox.Items.Count) { $current = [int]$script:State.storage.currentBox }
    if ($current -lt 0 -or $current -ge $script:PCBox.Items.Count) { $current = 0 }
    $script:PCBox.SelectedIndex = $current
  }
  $boxInfo = @($script:State.storage.boxes)[$script:PCBox.SelectedIndex]
  $script:LoadingUi = $false
  if ($null -eq $boxInfo) { return }
  if ($null -ne $script:SelectedSlotTag -and $script:SelectedSlotTag.Loc -eq "box" -and [int]$script:SelectedSlotTag.Box -ne [int]$boxInfo.index) {
    $script:SelectedSlotTag = $null
  }
  $rows = New-Object System.Collections.ArrayList
  $length = [int]$boxInfo.length
  for ($slot = 0; $slot -lt $length; $slot++) {
    $pokemon = $null
    foreach ($p in @($boxInfo.pokemon)) {
      if ([int]$p.slot -eq $slot) { $pokemon = $p; break }
    }
    [void]$rows.Add([pscustomobject]@{
      Icono = $(Get-PokemonIcon $pokemon)
      Slot = $slot + 1
      Nombre = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.nickname })
      Especie = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.speciesName })
      Nivel = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.level })
      PS = $(if ($null -eq $pokemon) { "" } else { "{0}/{1}" -f $pokemon.hp, $pokemon.totalhp })
      Objeto = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.itemName })
      Shiny = $(if ($null -eq $pokemon) { "" } else { [string]$pokemon.shiny })
      Loc = "box"
      Index = $slot
      Box = [int]$boxInfo.index
      SlotIndex = $slot
    })
  }
  $script:PCGrid.DataSource = $rows
  foreach ($colName in @("Loc", "Index", "Box", "SlotIndex")) {
    if ($script:PCGrid.Columns.Contains($colName)) { $script:PCGrid.Columns[$colName].Visible = $false }
  }
  Style-PokemonGrid $script:PCGrid
  if ($null -ne $script:PCSlots -and $script:PCSlots.Count -gt 0) {
    $visibleSlots = [Math]::Min($script:PCSlots.Count, $length)
    for ($slot = 0; $slot -lt $visibleSlots; $slot++) {
      Set-SlotPicture $script:PCSlots[$slot] (Find-PokemonEntry "box" -1 ([int]$boxInfo.index) $slot) "box" -1 ([int]$boxInfo.index) $slot
    }
    for ($slot = $visibleSlots; $slot -lt $script:PCSlots.Count; $slot++) {
      Set-SlotPicture $script:PCSlots[$slot] $null "box" -1 ([int]$boxInfo.index) $slot
    }
  }
  if ($null -ne $script:HexBoxSlots -and $script:HexBoxSlots.Count -gt 0) {
    $visibleSlots = [Math]::Min($script:HexBoxSlots.Count, $length)
    for ($slot = 0; $slot -lt $visibleSlots; $slot++) {
      Set-SlotPicture $script:HexBoxSlots[$slot] (Find-PokemonEntry "box" -1 ([int]$boxInfo.index) $slot) "box" -1 ([int]$boxInfo.index) $slot
    }
    for ($slot = $visibleSlots; $slot -lt $script:HexBoxSlots.Count; $slot++) {
      Set-SlotPicture $script:HexBoxSlots[$slot] $null "box" -1 ([int]$boxInfo.index) $slot
    }
  }
  if ($null -ne $script:HexBoxSelector) {
    $script:LoadingUi = $true
    $script:HexBoxSelector.Items.Clear()
    foreach ($box in @($script:State.storage.boxes)) {
      [void]$script:HexBoxSelector.Items.Add(("{0}" -f $box.name))
    }
    if ($script:HexBoxSelector.Items.Count -gt 0) { $script:HexBoxSelector.SelectedIndex = $script:PCBox.SelectedIndex }
    $script:LoadingUi = $false
  }
  if ($null -ne $script:PCCreatePreview) {
    Update-SpeciesPreview $script:PCCreatePreview $script:PCCreateSpecies
  }
  if ($null -ne $script:PCBoxName) {
    $script:LoadingUi = $true
    $script:PCBoxName.Text = [string]$boxInfo.name
    $script:LoadingUi = $false
  }
}

function Select-PokemonByIndex {
  param([int]$Index)
  if ($script:Dirty) { $script:Dirty = $false }
  $list = Get-SelectedPokemonList
  if ($Index -lt 0 -or $Index -ge $list.Count) { return }
  $script:SelectedPokemon = $list[$Index]
  Fill-PokemonFields $script:SelectedPokemon
}

function Set-NumberValue {
  param($Control, [int64]$Value)
  $v = [Math]::Max([int64]$Control.Minimum, [Math]::Min([int64]$Control.Maximum, $Value))
  $Control.Value = [decimal]$v
}

function Fill-PokemonFields {
  param($Pokemon)
  if ($null -eq $Pokemon) { return }
  $script:LoadingUi = $true
  $script:PokemonLoc.Text = if ($Pokemon.loc -eq "party") { "Equipo indice $($Pokemon.index)" } else { "Caja $([int]$Pokemon.box + 1), slot $([int]$Pokemon.slot + 1)" }
  Set-NumberValue $script:PokeSpecies ([int]$Pokemon.species)
  Set-NamedComboById $script:SpeciesCombo ([int]$Pokemon.species)
  $script:PokeSpeciesName.Text = [string]$Pokemon.speciesName
  $script:PokeNick.Text = [string]$Pokemon.nickname
  Set-NumberValue $script:PokeLevel ([int]$Pokemon.level)
  Set-NumberValue $script:PokeExp ([int64]$Pokemon.exp)
  Set-NumberValue $script:PokeHp ([int]$Pokemon.hp)
  $script:PokeTotalHp.Text = "/ $($Pokemon.totalhp)"
  Set-NumberValue $script:PokeStatus ([int]$Pokemon.status)
  Set-NamedComboById $script:StatusCombo ([int]$Pokemon.status)
  Set-NumberValue $script:PokeStatusCount ([int]$Pokemon.statusCount)
  Set-NumberValue $script:PokeHappiness ([int]$Pokemon.happiness)
  Set-NumberValue $script:PokeItem ([int]$Pokemon.item)
  Set-NamedComboById $script:ItemCombo ([int]$Pokemon.item)
  $script:PokeItemName.Text = [string]$Pokemon.itemName
  $forcedNature = $(if ($null -eq $Pokemon.natureflag) { -1 } else { [int]$Pokemon.natureflag })
  $visibleNature = $forcedNature
  if ([int]$visibleNature -lt 0) {
    $rawNature = Get-ObjectProperty $Pokemon "nature" $null
    if ($rawNature -ne $null -and [string]$rawNature -ne "") {
      try { $visibleNature = [int]$rawNature } catch {}
    }
  }
  if ([int]$visibleNature -lt 0) {
    $byNatureName = Get-NatureIdByName ([string](Get-ObjectProperty $Pokemon "natureName" ""))
    if ($byNatureName -ne $null) { $visibleNature = [int]$byNatureName }
  }
  Set-NumberValue $script:PokeNatureFlag $forcedNature
  Set-NamedComboById $script:NatureCombo $visibleNature
  $script:PokeNatureName.Text = [string]$Pokemon.natureName
  Set-NumberValue $script:PokeAbilityFlag ($(if ($null -eq $Pokemon.abilityflag) { -1 } else { [int]$Pokemon.abilityflag }))
  $script:PokeAbilityName.Text = [string]$Pokemon.abilityName
  Update-AbilityOptionsForCurrentSelection
  Set-NumberValue $script:PokeGenderFlag ($(if ($null -eq $Pokemon.genderflag) { -1 } else { [int]$Pokemon.genderflag }))
  Set-NamedComboById $script:GenderCombo ($(if ($null -eq $Pokemon.genderflag) { -1 } else { [int]$Pokemon.genderflag }))
  Set-NumberValue $script:PokeEggSteps ([int]$Pokemon.eggsteps)
  Set-NumberValue $script:PokeForm ([int]$Pokemon.form)
  Set-NumberValue $script:PokePokerus ([int]$Pokemon.pokerus)
  $script:PokeShiny.Checked = [bool]$Pokemon.shiny
  $script:PokeOt.Text = [string]$Pokemon.ot
  Set-NumberValue $script:PokeOtGender ([int]$Pokemon.otgender)
  Set-NumberValue $script:PokeTrainerId ([int64]$Pokemon.trainerID)
  Set-NumberValue $script:PokePersonalId ([int64]$Pokemon.personalID)
  Set-NumberValue $script:PokeLanguage ([int]$Pokemon.language)
  Set-NumberValue $script:PokeBallUsed ([int]$Pokemon.ballused)
  Set-NamedComboById $script:PokeBallCombo ([int]$Pokemon.ballused)
  Update-BallPreview
  Set-NumberValue $script:PokeObtainMode ([int]$Pokemon.obtainMode)
  Set-NumberValue $script:PokeObtainLevel ([int]$Pokemon.obtainLevel)
  Set-NumberValue $script:PokeObtainMap ([int]$Pokemon.obtainMap)
  $script:PokeObtainText.Text = [string]$Pokemon.obtainText
  Set-NumberValue $script:PokeHatchedMap ([int]$Pokemon.hatchedMap)
  Set-NumberValue $script:PokeMarkings ([int]$Pokemon.markings)
  $script:PokeExpShare.Checked = [bool]$Pokemon.expshare
  $contest = $Pokemon.contest
  Set-NumberValue $script:PokeCool ([int]$contest.cool)
  Set-NumberValue $script:PokeBeauty ([int]$contest.beauty)
  Set-NumberValue $script:PokeCute ([int]$contest.cute)
  Set-NumberValue $script:PokeSmart ([int]$contest.smart)
  Set-NumberValue $script:PokeTough ([int]$contest.tough)
  Set-NumberValue $script:PokeSheen ([int]$contest.sheen)
  Set-NumberValue $script:PokeTimeReceived ([int64]$Pokemon.timeReceived)
  Set-NumberValue $script:PokeTimeEggHatched ([int64]$Pokemon.timeEggHatched)
  $script:PokeFirstMoves.Text = (@($Pokemon.firstmoves) -join ",")
  $script:PokeRibbons.Text = (@($Pokemon.ribbons) -join ",")
  $moves = @($Pokemon.moves)
  $script:CurrentMoveIds = @{}
  $learnedSource = @()
  if ($Pokemon.PSObject.Properties["learnedMoves"] -and $null -ne $Pokemon.learnedMoves) {
    $learnedSource = @($Pokemon.learnedMoves)
  } else {
    $learnedSource = @($Pokemon.learnableMoves)
  }
  foreach ($moveId in @($learnedSource)) {
    if ([int]$moveId -gt 0) { $script:CurrentMoveIds[[int]$moveId] = $true }
  }
  foreach ($move in @($moves)) {
    if ($null -ne $move -and [int]$move.id -gt 0) { $script:CurrentMoveIds[[int]$move.id] = $true }
  }
  $script:LearnableMoveIds = @{}
  $compatibleSource = @()
  if ($null -ne $Pokemon.learnableMoves -and @($Pokemon.learnableMoves).Count -gt 0) {
    $compatibleSource = @($Pokemon.learnableMoves)
  } elseif ($Pokemon.PSObject.Properties["learnedMoves"]) {
    $compatibleSource = @(Get-PbsCompatibleMoveIds ([int]$Pokemon.species))
  }
  foreach ($moveId in @($compatibleSource)) {
      $id = [int]$moveId
      if ($id -gt 0 -and !$script:CurrentMoveIds.ContainsKey($id)) { $script:LearnableMoveIds[$id] = $true }
  }
  if ($null -ne $script:Data -and $null -ne $script:Data.moves) {
    foreach ($combo in @($script:MoveCombos)) {
      Populate-NamedCombo $combo $script:Data.moves $true "Sin movimiento"
    }
  }
  $ivs = @($Pokemon.iv)
  $evs = @($Pokemon.ev)
  for ($i = 0; $i -lt 6; $i++) {
    Set-NumberValue $script:IvNums[$i] (Get-DisplayStatValue $ivs $i)
    Set-NumberValue $script:EvNums[$i] (Get-DisplayStatValue $evs $i)
  }
  Update-StatsDisplay $Pokemon
  for ($i = 0; $i -lt 4; $i++) {
    $m = $moves[$i]
    Set-NumberValue $script:MoveIds[$i] ([int]$m.id)
    if ($script:MoveCombos.Count -gt $i) { Set-NamedComboById $script:MoveCombos[$i] ([int]$m.id) }
    Set-NumberValue $script:MovePps[$i] ([int]$m.pp)
    Set-NumberValue $script:MovePpUps[$i] ([int]$m.ppup)
    $script:MoveNames[$i].Text = [string]$m.name
  }
  Update-MoveDetailsBox 0
  $script:PokeMeta.Text = "OT: $($Pokemon.ot) | TID: $($Pokemon.trainerID) | PID: $($Pokemon.personalID) | Huevo: $($Pokemon.isEgg)"
  if ($null -ne $script:PokePreview) {
    Update-PokemonPreviewFromInputs
    Set-Tip $script:PokePreview ("Pokemon seleccionado: {0} / {1} Nv.{2}" -f $Pokemon.nickname, $Pokemon.speciesName, $Pokemon.level)
  }
  Update-NatureEffectDisplay
  $script:LoadingUi = $false
}

function Refresh-BagTab {
  if ($null -eq $script:State) { return }
  $bagEntries = @(Update-StateBagCache)
  $qtyById = @{}
  $bagById = @{}
  foreach ($item in @($bagEntries)) {
    $qtyById[[int]$item.id] = [int]$item.quantity
    $bagById[[int]$item.id] = $item
  }
  $filter = ""
  if ($null -ne $script:BagSearch) { $filter = $script:BagSearch.Text.ToLowerInvariant() }
  $ownedOnly = ($null -ne $script:BagOwnedOnly -and $script:BagOwnedOnly.Checked)
  $rows = New-Object System.Collections.ArrayList
  $ownedIds = @{}
  foreach ($item in @($bagEntries | Sort-Object { [int]$_.pocket }, { [int]$_.slot }, { [int]$_.id })) {
    $id = [int]$item.id
    if ($id -le 0) { continue }
    $ownedIds[$id] = $true
    $qty = [int]$item.quantity
    $name = [string]$item.name
    if ($filter -ne "" -and $name.ToLowerInvariant().IndexOf($filter) -lt 0 -and ([string]$id).IndexOf($filter) -lt 0) { continue }
    [void]$rows.Add([pscustomobject]@{
      Icono = (Get-ItemIcon $id)
      ID = $id
      Objeto = $name
      Bolsillo = (Get-BagPocketName ([int]$item.pocket))
      Cantidad = $qty
    })
  }
  if (!$ownedOnly -and $null -ne $script:Data -and $null -ne $script:Data.items) {
    foreach ($item in @($script:Data.items)) {
      $id = [int]$item.id
      if ($id -le 0 -or $ownedIds.ContainsKey($id)) { continue }
      $name = [string]$item.name
      if ($filter -ne "" -and $name.ToLowerInvariant().IndexOf($filter) -lt 0 -and ([string]$id).IndexOf($filter) -lt 0) { continue }
      [void]$rows.Add([pscustomobject]@{
        Icono = (Get-ItemIcon $id)
        ID = $id
        Objeto = $name
        Bolsillo = (Get-BagPocketName ([int]$item.pocket))
        Cantidad = 0
      })
    }
  }
  $script:BagGrid.DataSource = $rows
  if ($script:BagGrid.Columns.Contains("Icono")) {
    $script:BagGrid.Columns["Icono"].Width = 42
    $script:BagGrid.Columns["Icono"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
    if ($script:BagGrid.Columns["Icono"] -is [System.Windows.Forms.DataGridViewImageColumn]) {
      $script:BagGrid.Columns["Icono"].ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
    }
  }
  if ($script:BagGrid.Columns.Contains("ID")) { $script:BagGrid.Columns["ID"].Visible = $false }
  if ($script:BagGrid.Columns.Contains("Cantidad")) {
    $script:BagGrid.Columns["Cantidad"].Width = 80
    $script:BagGrid.Columns["Cantidad"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
  }
}

function Refresh-WorldTab {
  if ($null -eq $script:State) { return }
  $script:SwitchList.Text = (@($script:State.switches.on) -join ", ")
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($var in @($script:State.variables.values)) {
    $lines.Add(("{0} = {1} ({2})" -f $var.id, $var.value, $var.type))
  }
  $script:VariableList.Text = ($lines -join [Environment]::NewLine)
}

function Refresh-RawTab {
  if (Test-Path -LiteralPath $script:StatePath) {
    $script:RawState.Text = [System.IO.File]::ReadAllText($script:StatePath, $script:Utf8NoBom)
  }
}

function Show-InventoryEditor {
  Load-LiveData
  [void](Update-StateBagCache)
  if ($null -eq $script:State -or $null -eq $script:Data) {
    [void][System.Windows.Forms.MessageBox]::Show("Primero carga una partida y usa Actualizar.", "Editor de objetos")
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Editor de objetos"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(590, 545)
  $dlg.MinimumSize = New-Object System.Drawing.Size(560, 500)
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }

  $search = New-TextBox 12 12 190
  $owned = New-Object System.Windows.Forms.CheckBox
  $owned.Text = "Solo mochila"
  $owned.Checked = $true
  $owned.Location = New-Object System.Drawing.Point(214, 14)
  $owned.Size = New-Object System.Drawing.Size(140, 22)
  $inventoryStatus = New-Object System.Windows.Forms.Label
  $inventoryStatus.Text = "Cargando bolsa..."
  $inventoryStatus.Location = New-Object System.Drawing.Point(360, 14)
  $inventoryStatus.Size = New-Object System.Drawing.Size(200, 22)
  $inventoryStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
  $pocketTabs = New-Object System.Windows.Forms.TabControl
  $pocketTabs.Location = New-Object System.Drawing.Point(12, 42)
  $pocketTabs.Size = New-Object System.Drawing.Size(548, 32)
  $pocketTabs.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
  $pocketImages = New-Object System.Windows.Forms.ImageList
  $pocketImages.ImageSize = New-Object System.Drawing.Size(20, 20)
  $pocketImages.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
  $pocketTabs.ImageList = $pocketImages
  $pocketDefs = Get-BagPocketDefinitions
  foreach ($pocket in $pocketDefs) {
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = [string]$pocket.Name
    $page.Tag = [int]$pocket.Id
    $icon = Get-BagPocketIcon ([int]$pocket.Icon)
    if ($null -ne $icon) {
      $page.ImageIndex = $pocketImages.Images.Count
      [void]$pocketImages.Images.Add($icon)
    }
    [void]$pocketTabs.TabPages.Add($page)
  }
  $grid = New-Object System.Windows.Forms.DataGridView
  $grid.Location = New-Object System.Drawing.Point(12, 76)
  $grid.Size = New-Object System.Drawing.Size(548, 340)
  $grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
  $grid.ReadOnly = $false
  $grid.AutoGenerateColumns = $false
  $grid.AllowUserToAddRows = $false
  $grid.RowHeadersVisible = $false
  $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
  $grid.MultiSelect = $false
  $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
  $grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
  $grid.RowTemplate.Height = 30
  $idCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $idCol.Name = "ID"
  $idCol.HeaderText = "ID"
  $idCol.Visible = $false
  $iconCol = New-Object System.Windows.Forms.DataGridViewImageColumn
  $iconCol.Name = "Icono"
  $iconCol.HeaderText = ""
  $iconCol.Width = 42
  $iconCol.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
  $iconCol.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
  $iconCol.DefaultCellStyle.NullValue = Get-BlankIcon
  $itemCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $itemCol.Name = "Objeto"
  $itemCol.HeaderText = "Objeto"
  $itemCol.ReadOnly = $true
  $itemCol.FillWeight = 170
  $pocketCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $pocketCol.Name = "Bolsillo"
  $pocketCol.HeaderText = "Bolsillo"
  $pocketCol.FillWeight = 82
  $pocketIdCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $pocketIdCol.Name = "Pocket"
  $pocketIdCol.HeaderText = "Pocket"
  $pocketIdCol.Visible = $false
  $countCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $countCol.Name = "Cantidad"
  $countCol.HeaderText = "Cantidad"
  $countCol.FillWeight = 50
  [void]$grid.Columns.Add($idCol)
  [void]$grid.Columns.Add($iconCol)
  [void]$grid.Columns.Add($itemCol)
  [void]$grid.Columns.Add($pocketCol)
  [void]$grid.Columns.Add($pocketIdCol)
  [void]$grid.Columns.Add($countCol)
  $qty = New-Number 172 430 0 999 58
  $sort = New-Object System.Windows.Forms.Button
  $sort.Text = "Actualizar"
  $sort.Location = New-Object System.Drawing.Point(12, 428)
  $sort.Size = New-Object System.Drawing.Size(86, 26)
  Set-Tip $sort "Recarga la bolsa desde el snapshot vivo del juego."
  $giveAll = New-Object System.Windows.Forms.Button
  $giveAll.Text = "Dar 999"
  $giveAll.Location = New-Object System.Drawing.Point(12, 460)
  $giveAll.Size = New-Object System.Drawing.Size(86, 26)
  $save = New-Object System.Windows.Forms.Button
  $save.Text = "Aplicar"
  $save.Location = New-Object System.Drawing.Point(470, 428)
  $save.Size = New-Object System.Drawing.Size(90, 26)
  $save.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "Cerrar"
  $cancel.Location = New-Object System.Drawing.Point(470, 460)
  $cancel.Size = New-Object System.Drawing.Size(90, 26)
  $cancel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
  $countLabel = New-Label "Cantidad:" 112 430 60
  $dlg.Controls.AddRange(@($search, $owned, $inventoryStatus, $pocketTabs, $grid, $countLabel, $qty, $sort, $giveAll, $save, $cancel))
  $itemByName = @{}
  $itemPocketByName = @{}
  $itemDataById = @{}
  foreach ($item in @($script:Data.items)) {
    $id = [int]$item.id
    if ($id -gt 0) { $itemDataById[$id] = $item }
  }
  $inventoryState = [pscustomobject]@{ Loading = $false; BagEntryCount = 0; MissingBag = $false }
  $reloadBagEntriesFromFile = {
    if (!(Test-Path -LiteralPath $script:StatePath)) { return @() }
    $liveBagEntries = @(Get-BagEntriesFromStateFile $script:StatePath)
    if ($liveBagEntries.Count -gt 0) {
      Set-ObjectProperty $script:State "bag" @($liveBagEntries)
      $script:LastKnownBagEntries = @($liveBagEntries)
    }
    return @($liveBagEntries)
  }.GetNewClosure()
  $getBagEntries = {
    $bagEntries = @(Get-ValidBagEntries -Bag $script:State.bag)
    if ($bagEntries.Count -eq 0) { $bagEntries = @(& $reloadBagEntriesFromFile) }
    if ($bagEntries.Count -eq 0 -and @($script:LastKnownBagEntries).Count -gt 0) { $bagEntries = @($script:LastKnownBagEntries) }
    return @(Get-ValidBagEntries -Bag $bagEntries)
  }.GetNewClosure()

  $refreshInventory = {
    $inventoryState.Loading = $true
    $bagEntries = @(& $getBagEntries)
    $inventoryState.BagEntryCount = $bagEntries.Count
    $inventoryState.MissingBag = ($bagEntries.Count -eq 0)
    $rows = New-Object System.Collections.ArrayList
    $filter = $search.Text.ToLowerInvariant()
    $activePocket = 0
    if ($pocketTabs.SelectedTab -ne $null) { $activePocket = [int]$pocketTabs.SelectedTab.Tag }
    $itemByName.Clear()
    $itemPocketByName.Clear()
    foreach ($item in @($script:Data.items)) {
      $pocket = [int]$item.pocket
      if ($activePocket -ne 0 -and $pocket -ne $activePocket) { continue }
      $name = [string]$item.name
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      $itemByName[$name] = [int]$item.id
      $itemPocketByName[$name] = $pocket
    }
    $ownedIds = @{}
    foreach ($item in @($bagEntries | Sort-Object { [int]$_.pocket }, { [int]$_.slot }, { [int]$_.id })) {
      $id = [int]$item.id
      if ($id -le 0) { continue }
      $pocket = [int]$item.pocket
      $dataItem = $null
      if ($itemDataById.ContainsKey($id)) {
        $dataItem = $itemDataById[$id]
        if ($pocket -le 0) { $pocket = [int]$dataItem.pocket }
      }
      if ($activePocket -ne 0 -and $pocket -ne $activePocket) { continue }
      $ownedIds[$id] = $true
      $count = [int]$item.quantity
      if ($owned.Checked -and $count -le 0) { continue }
      $name = [string]$item.name
      if ($null -ne $dataItem -and ![string]::IsNullOrWhiteSpace([string]$dataItem.name)) { $name = [string]$dataItem.name }
      if ([string]::IsNullOrWhiteSpace($name)) { $name = "Objeto $id" }
      if (!$itemByName.ContainsKey($name)) {
        $itemByName[$name] = $id
        $itemPocketByName[$name] = $pocket
      }
      if ($filter -ne "" -and $name.ToLowerInvariant().IndexOf($filter) -lt 0 -and ([string]$id).IndexOf($filter) -lt 0) { continue }
      [void]$rows.Add([pscustomobject]@{ ID = $id; Icono = (Get-ItemIcon $id); Objeto = $name; Bolsillo = (Get-BagPocketName $pocket); Pocket = $pocket; Cantidad = $count })
    }
    if (!$owned.Checked) {
      foreach ($item in @($script:Data.items)) {
        $id = [int]$item.id
        if ($id -le 0 -or $ownedIds.ContainsKey($id)) { continue }
        $pocket = [int]$item.pocket
        if ($activePocket -ne 0 -and $pocket -ne $activePocket) { continue }
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($filter -ne "" -and $name.ToLowerInvariant().IndexOf($filter) -lt 0 -and ([string]$id).IndexOf($filter) -lt 0) { continue }
        [void]$rows.Add([pscustomobject]@{ ID = $id; Icono = (Get-ItemIcon $id); Objeto = $name; Bolsillo = (Get-BagPocketName $pocket); Pocket = $pocket; Cantidad = 0 })
      }
    }
    if (!$owned.Checked -and $activePocket -ne 0) {
      for ($i = 0; $i -lt 12; $i++) {
        [void]$rows.Add([pscustomobject]@{ ID = 0; Icono = (Get-BlankIcon); Objeto = ""; Bolsillo = (Get-BagPocketName $activePocket); Pocket = $activePocket; Cantidad = 0 })
      }
    }
    $grid.DataSource = $null
    $grid.Rows.Clear()
    foreach ($row in @($rows)) {
      $rowIndex = $grid.Rows.Add($row.ID, $row.Icono, $row.Objeto, $row.Bolsillo, $row.Pocket, $row.Cantidad)
      $grid.Rows[$rowIndex].Tag = $row
    }
    $shownCount = @($rows).Count
    if ($inventoryState.MissingBag) {
      $inventoryStatus.Text = "Bolsa no leida. Reintentando..."
    } elseif ($shownCount -eq 0) {
      $inventoryStatus.Text = "Sin objetos en este bolsillo/filtro"
    } else {
      $inventoryStatus.Text = ("{0} objeto(s) mostrado(s) de {1} en mochila" -f $shownCount, $inventoryState.BagEntryCount)
    }
    $inventoryState.Loading = $false
  }.GetNewClosure()

  $getGridRowData = {
    param($GridRow)
    if ($null -eq $GridRow) { return $null }
    if ($null -ne $GridRow.Tag) { return $GridRow.Tag }
    $id = 0
    $pocket = -1
    $count = 0
    try { $id = [int]$GridRow.Cells["ID"].Value } catch {}
    try { $pocket = [int]$GridRow.Cells["Pocket"].Value } catch {}
    try { $count = [int]$GridRow.Cells["Cantidad"].Value } catch {}
    return [pscustomobject]@{
      ID = $id
      Icono = $GridRow.Cells["Icono"].Value
      Objeto = [string]$GridRow.Cells["Objeto"].Value
      Bolsillo = [string]$GridRow.Cells["Bolsillo"].Value
      Pocket = $pocket
      Cantidad = $count
    }
  }.GetNewClosure()

  $applySelected = {
    if ($null -eq $grid.CurrentRow) { return }
    $row = & $getGridRowData $grid.CurrentRow
    if ($null -eq $row) { return }
    $id = [int]$row.ID
    if ($id -le 0 -and $itemByName.ContainsKey([string]$row.Objeto)) { $id = [int]$itemByName[[string]$row.Objeto] }
    if ($id -le 0) { return }
    $pocket = $(if ($null -ne $row.Pocket) { [int]$row.Pocket } elseif ($itemPocketByName.ContainsKey([string]$row.Objeto)) { [int]$itemPocketByName[[string]$row.Objeto] } else { -1 })
    Set-LocalBagQuantity $id ([int]$qty.Value) $pocket
    Send-EditorCommand "set_item_qty" @{ item = $id; qty = [int]$qty.Value }
    & $refreshInventory
  }.GetNewClosure()

  $applyGridRow = {
    param($row)
    if ($inventoryState.Loading -or $null -eq $row) { return }
    $itemName = [string]$row.Objeto
    if ([string]::IsNullOrWhiteSpace($itemName) -or !$itemByName.ContainsKey($itemName)) { return }
    $id = [int]$itemByName[$itemName]
    $count = 0
    try { $count = [Math]::Max(0, [int]$row.Cantidad) } catch { $count = 1 }
    if ($count -le 0 -and [int]$row.ID -le 0) { $count = 1; $row.Cantidad = 1 }
    $pocket = $(if ($itemPocketByName.ContainsKey($itemName)) { [int]$itemPocketByName[$itemName] } else { [int]$row.Pocket })
    $row.ID = $id
    $row.Icono = Get-ItemIcon $id
    $row.Pocket = $pocket
    $row.Bolsillo = Get-BagPocketName $pocket
    Set-LocalBagQuantity $id $count $pocket
    Send-EditorCommand "set_item_qty" @{ item = $id; qty = $count }
    $grid.Invalidate()
  }.GetNewClosure()

  $grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
  }.GetNewClosure())
  $grid.Add_CellValueChanged({
    param($sender, $e)
    if ($inventoryState.Loading -or $e.RowIndex -lt 0) { return }
    if ($e.ColumnIndex -lt 0) { return }
    $name = $grid.Columns[$e.ColumnIndex].Name
    if ($name -ne "Cantidad") { return }
    $row = & $getGridRowData $grid.Rows[$e.RowIndex]
    if ($null -eq $row) { return }
    try { $row.Cantidad = [int]$grid.Rows[$e.RowIndex].Cells["Cantidad"].Value } catch {}
    & $applyGridRow $row
    $inventoryState.Loading = $true
    try {
      $grid.Rows[$e.RowIndex].Tag = $row
      $grid.Rows[$e.RowIndex].Cells["ID"].Value = $row.ID
      $grid.Rows[$e.RowIndex].Cells["Icono"].Value = $row.Icono
      $grid.Rows[$e.RowIndex].Cells["Bolsillo"].Value = $row.Bolsillo
      $grid.Rows[$e.RowIndex].Cells["Pocket"].Value = $row.Pocket
      $grid.Rows[$e.RowIndex].Cells["Cantidad"].Value = $row.Cantidad
    } finally {
      $inventoryState.Loading = $false
    }
  }.GetNewClosure())
  $grid.Add_DataError({ param($sender, $e) $e.ThrowException = $false }.GetNewClosure())
  $grid.Add_SelectionChanged({
    if ($null -eq $grid.CurrentRow) { return }
    $row = & $getGridRowData $grid.CurrentRow
    if ($null -ne $row) {
      try { Set-NumberValue $qty ([int]$row.Cantidad) } catch { Set-NumberValue $qty 0 }
    }
  }.GetNewClosure())
  $search.Add_TextChanged({ if (!$inventoryState.Loading) { & $refreshInventory } }.GetNewClosure())
  $owned.Add_CheckedChanged({ if (!$inventoryState.Loading) { & $refreshInventory } }.GetNewClosure())
  $pocketTabs.Add_SelectedIndexChanged({ if (!$inventoryState.Loading) { & $refreshInventory } }.GetNewClosure())
  $sort.Add_Click({ [void](& $reloadBagEntriesFromFile); & $refreshInventory }.GetNewClosure())
  $giveAll.Add_Click({ Set-NumberValue $qty 999; & $applySelected }.GetNewClosure())
  $save.Add_Click($applySelected)
  $cancel.Add_Click({ $dlg.Close() }.GetNewClosure())
  $retryTimer = New-Object System.Windows.Forms.Timer
  $retryTimer.Interval = 700
  $retryAttempts = [ref]0
  $retryTimer.Add_Tick({
    if ($dlg.IsDisposed) {
      $retryTimer.Stop()
      $retryTimer.Dispose()
      return
    }
    if ($inventoryState.BagEntryCount -gt 0) {
      $retryTimer.Stop()
      return
    }
    $retryAttempts.Value++
    [void](& $reloadBagEntriesFromFile)
    & $refreshInventory
    if ($retryAttempts.Value -ge 20) {
      $retryTimer.Stop()
      $inventoryStatus.Text = "0 objetos. Pulsa Actualizar o revisa state.json."
    }
  }.GetNewClosure())
  $dlg.Add_FormClosed({
    try {
      $retryTimer.Stop()
      $retryTimer.Dispose()
    } catch {}
  }.GetNewClosure())
  if (@(& $getBagEntries).Count -eq 0) { [void](& $reloadBagEntriesFromFile) }
  & $refreshInventory
  if ($inventoryState.BagEntryCount -eq 0) { $retryTimer.Start() }
  [void]$dlg.Show($form)
}

function Show-AchievementsEditor {
  if ($null -eq $script:State -or $null -eq $script:State.achievements) {
    [void][System.Windows.Forms.MessageBox]::Show("El snapshot actual no contiene logros. Abre el menu de logros en el juego o usa Actualizar para regenerar datos.", "Editor de logros")
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Editor de logros"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(760, 520)
  $dlg.MinimumSize = New-Object System.Drawing.Size(700, 430)
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }

  $grid = New-Object System.Windows.Forms.DataGridView
  $grid.Location = New-Object System.Drawing.Point(12, 12)
  $grid.Size = New-Object System.Drawing.Size(720, 398)
  $grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
  $grid.AutoGenerateColumns = $false
  $grid.AllowUserToAddRows = $false
  $grid.RowHeadersVisible = $false
  $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
  $grid.MultiSelect = $false
  $grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
  $grid.RowTemplate.Height = 54
  $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

  $iconCol = New-Object System.Windows.Forms.DataGridViewImageColumn
  $iconCol.Name = "Icono"
  $iconCol.HeaderText = ""
  $iconCol.DataPropertyName = "Icono"
  $iconCol.Width = 58
  $iconCol.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
  $iconCol.ImageLayout = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
  $nameCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $nameCol.Name = "Nombre"
  $nameCol.HeaderText = "Logro"
  $nameCol.DataPropertyName = "Nombre"
  $nameCol.ReadOnly = $true
  $nameCol.FillWeight = 90
  $descCol = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $descCol.Name = "Descripcion"
  $descCol.HeaderText = "Descripcion"
  $descCol.DataPropertyName = "Descripcion"
  $descCol.ReadOnly = $true
  $descCol.FillWeight = 210
  $statusCol = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
  $statusCol.Name = "Estado"
  $statusCol.HeaderText = "Estado"
  $statusCol.DataPropertyName = "Estado"
  $statusCol.DisplayStyle = [System.Windows.Forms.DataGridViewComboBoxDisplayStyle]::ComboBox
  $statusCol.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $statusCol.FillWeight = 70
  [void]$statusCol.Items.Add("Oculto")
  [void]$statusCol.Items.Add("Activo")
  [void]$statusCol.Items.Add("Completado")
  [void]$grid.Columns.Add($iconCol)
  [void]$grid.Columns.Add($nameCol)
  [void]$grid.Columns.Add($descCol)
  [void]$grid.Columns.Add($statusCol)
  $dlg.Controls.Add($grid)

  $completeAll = New-Object System.Windows.Forms.Button
  $completeAll.Text = "Completar todos"
  $completeAll.Location = New-Object System.Drawing.Point(12, 426)
  $completeAll.Size = New-Object System.Drawing.Size(126, 28)
  $completeAll.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
  $activeAll = New-Object System.Windows.Forms.Button
  $activeAll.Text = "Activar todos"
  $activeAll.Location = New-Object System.Drawing.Point(148, 426)
  $activeAll.Size = New-Object System.Drawing.Size(112, 28)
  $activeAll.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
  $hiddenAll = New-Object System.Windows.Forms.Button
  $hiddenAll.Text = "Ocultar todos"
  $hiddenAll.Location = New-Object System.Drawing.Point(270, 426)
  $hiddenAll.Size = New-Object System.Drawing.Size(112, 28)
  $hiddenAll.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
  $close = New-Object System.Windows.Forms.Button
  $close.Text = "Cerrar"
  $close.Location = New-Object System.Drawing.Point(642, 426)
  $close.Size = New-Object System.Drawing.Size(90, 28)
  $close.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
  $dlg.Controls.AddRange(@($completeAll, $activeAll, $hiddenAll, $close))

  $statusByName = @{ "Oculto" = 1; "Activo" = 2; "Completado" = 3 }
  $achState = [pscustomobject]@{ Loading = $false }

  $refreshAchievements = {
    $achState.Loading = $true
    $rows = New-Object System.Collections.ArrayList
    foreach ($achievement in @($script:State.achievements)) {
      $status = [int]$achievement.status
      [void]$rows.Add([pscustomobject]@{
        Index = [int]$achievement.index
        Icono = (Get-AchievementIcon ([int]$achievement.index) $status)
        Nombre = [string]$achievement.name
        Descripcion = [string]$achievement.description
        Estado = (Get-AchievementStatusName $status)
      })
    }
    $grid.DataSource = $rows
    $achState.Loading = $false
  }.GetNewClosure()

  $applyAchievementRow = {
    param($row)
    if ($achState.Loading -or $null -eq $row) { return }
    $statusName = [string]$row.Estado
    if (!$statusByName.ContainsKey($statusName)) { return }
    $status = [int]$statusByName[$statusName]
    Set-LocalAchievementStatus ([int]$row.Index) $status
    $row.Icono = Get-AchievementIcon ([int]$row.Index) $status
    Send-EditorCommand "achievement_set" @{ index = [int]$row.Index; status = $status }
    $grid.Invalidate()
  }.GetNewClosure()

  $setAll = {
    param([int]$Status)
    $achState.Loading = $true
    try {
      foreach ($achievement in @($script:State.achievements)) {
        Set-LocalAchievementStatus ([int]$achievement.index) $Status
        Send-EditorCommand "achievement_set" @{ index = [int]$achievement.index; status = $Status }
      }
    } finally {
      $achState.Loading = $false
    }
    & $refreshAchievements
  }.GetNewClosure()

  $grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
  }.GetNewClosure())
  $grid.Add_CellValueChanged({
    param($sender, $e)
    if ($achState.Loading -or $e.RowIndex -lt 0) { return }
    if ($e.ColumnIndex -lt 0 -or $grid.Columns[$e.ColumnIndex].Name -ne "Estado") { return }
    & $applyAchievementRow $grid.Rows[$e.RowIndex].DataBoundItem
  }.GetNewClosure())
  $grid.Add_DataError({ param($sender, $e) $e.ThrowException = $false }.GetNewClosure())
  $completeAll.Add_Click({ & $setAll 3 }.GetNewClosure())
  $activeAll.Add_Click({ & $setAll 2 }.GetNewClosure())
  $hiddenAll.Add_Click({ & $setAll 1 }.GetNewClosure())
  $close.Add_Click({ $dlg.Close() })
  & $refreshAchievements
  [void]$dlg.Show($form)
}

function Show-PokedexEditor {
  if ($null -eq $script:Data -or $null -eq $script:Data.species) {
    [void][System.Windows.Forms.MessageBox]::Show("Primero carga una partida y usa Actualizar.", "Editor de Pokedex")
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Editor de Pokedex"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(610, 440)
  $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }

  $find = New-TextBox 14 18 160
  $list = New-Object System.Windows.Forms.ListBox
  $list.Location = New-Object System.Drawing.Point(14, 48)
  $list.Size = New-Object System.Drawing.Size(170, 318)
  $list.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
  $list.ItemHeight = 28
  $list.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $e.DrawBackground()
    $text = [string]$sender.Items[$e.Index]
    $id = 0
    if ($text -match '^\s*(\d+)') { $id = [int]$matches[1] }
    $icon = Get-PokemonIconByValues $id $false 0
    if ($null -ne $icon) { $e.Graphics.DrawImage($icon, $e.Bounds.X + 2, $e.Bounds.Y + 2, 24, 24) }
    $selected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)
    $fore = $(if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::Black })
    $brush = New-Object System.Drawing.SolidBrush($fore)
    $rect = New-Object System.Drawing.RectangleF([single]($e.Bounds.X + 30), [single]($e.Bounds.Y + 6), [single]($e.Bounds.Width - 32), [single]20)
    $e.Graphics.DrawString($text, $sender.Font, $brush, $rect)
    $brush.Dispose()
    $e.DrawFocusRectangle()
  })
  $seenMale = New-Object System.Windows.Forms.CheckBox
  $seenMale.Text = "Macho"
  $seenMale.Checked = $true
  $seenMale.Location = New-Object System.Drawing.Point(220, 86)
  $seenFemale = New-Object System.Windows.Forms.CheckBox
  $seenFemale.Text = "Hembra"
  $seenFemale.Location = New-Object System.Drawing.Point(220, 112)
  $seenShiny = New-Object System.Windows.Forms.CheckBox
  $seenShiny.Text = "Shiny macho"
  $seenShiny.Checked = $true
  $seenShiny.Location = New-Object System.Drawing.Point(220, 138)
  $seenShinyFemale = New-Object System.Windows.Forms.CheckBox
  $seenShinyFemale.Text = "Shiny hembra"
  $seenShinyFemale.Location = New-Object System.Drawing.Point(220, 164)
  $national = New-Object System.Windows.Forms.CheckBox
  $national.Text = "Pokedex nacional"
  $national.Checked = $true
  $national.Location = New-Object System.Drawing.Point(206, 346)
  $status = New-Object System.Windows.Forms.ComboBox
  $status.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
  $status.Items.AddRange(@("Vista", "Capturada"))
  $status.SelectedIndex = 1
  $status.Location = New-Object System.Drawing.Point(206, 48)
  $status.Size = New-Object System.Drawing.Size(132, 24)
  $saveCurrent = New-Object System.Windows.Forms.Button
  $saveCurrent.Text = "Editar entrada"
  $saveCurrent.Location = New-Object System.Drawing.Point(352, 18)
  $saveCurrent.Size = New-Object System.Drawing.Size(130, 26)
  $saveAll = New-Object System.Windows.Forms.Button
  $saveAll.Text = "Editar todas"
  $saveAll.Location = New-Object System.Drawing.Point(352, 50)
  $saveAll.Size = New-Object System.Drawing.Size(130, 26)
  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "Cerrar"
  $cancel.Location = New-Object System.Drawing.Point(392, 346)
  $cancel.Size = New-Object System.Drawing.Size(86, 28)
  $saveChanges = New-Object System.Windows.Forms.Button
  $saveChanges.Text = "Aplicar cambios"
  $saveChanges.Location = New-Object System.Drawing.Point(486, 346)
  $saveChanges.Size = New-Object System.Drawing.Size(104, 28)
  $formsBox = New-Object System.Windows.Forms.GroupBox
  $formsBox.Text = "Formas:"
  $formsBox.Location = New-Object System.Drawing.Point(358, 94)
  $formsBox.Size = New-Object System.Drawing.Size(100, 236)
  $shinyFormsBox = New-Object System.Windows.Forms.GroupBox
  $shinyFormsBox.Text = "Formas shiny:"
  $shinyFormsBox.Location = New-Object System.Drawing.Point(470, 94)
  $shinyFormsBox.Size = New-Object System.Drawing.Size(110, 236)
  $dlg.Controls.AddRange(@($find, $list, $status, $seenMale, $seenFemale, $seenShiny, $seenShinyFemale, $national, $saveCurrent, $saveAll, $cancel, $saveChanges, $formsBox, $shinyFormsBox))

  $refreshDex = {
    $list.Items.Clear()
    $filter = $find.Text.ToLowerInvariant()
    foreach ($species in @($script:Data.species)) {
      $id = [int]$species.id
      if ($id -le 0) { continue }
      $name = [string]$species.name
      if ($filter -ne "" -and $name.ToLowerInvariant().IndexOf($filter) -lt 0 -and ([string]$id).IndexOf($filter) -lt 0) { continue }
      [void]$list.Items.Add(("{0:D3} - {1}" -f $id, $name))
    }
    if ($list.Items.Count -gt 0 -and $list.SelectedIndex -lt 0) { $list.SelectedIndex = 0 }
  }.GetNewClosure()

  $applyDex = {
    if ($list.SelectedItem -eq $null) { return }
    $id = [int](([string]$list.SelectedItem).Split("-")[0].Trim())
    $owned = ($status.SelectedIndex -eq 1)
    Send-EditorCommand "pokedex_set" @{ species = $id; seen = $true; owned = $owned }
  }.GetNewClosure()

  $find.Add_TextChanged($refreshDex)
  $saveCurrent.Add_Click($applyDex)
  $saveChanges.Add_Click($applyDex)
  $saveAll.Add_Click({
    $owned = ($status.SelectedIndex -eq 1)
    Send-EditorCommand "pokedex_set" @{ species = 1; seen = $true; owned = $owned; all = $true }
  }.GetNewClosure())
  $cancel.Add_Click({ $dlg.Close() }.GetNewClosure())
  & $refreshDex
  [void]$dlg.Show($form)
}

function Show-RawDataWindow {
  Refresh-RawTab
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Datos de bloque"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(720, 520)
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }
  $box = New-Object System.Windows.Forms.TextBox
  $box.Multiline = $true
  $box.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
  $box.WordWrap = $false
  $box.Dock = [System.Windows.Forms.DockStyle]::Fill
  $box.Text = $script:RawState.Text
  $dlg.Controls.Add($box)
  [void]$dlg.Show($form)
}

function Show-SwitchesWindow {
  if ($null -eq $script:State) {
    [void][System.Windows.Forms.MessageBox]::Show("Primero carga una partida y usa Actualizar.", "Switches")
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Switches y variables"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(650, 430)
  $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }
  $dlg.Controls.Add((New-Label "Switch" 18 18 60))
  $sid = New-Number 78 16 1 9999 80
  $svalue = New-Object System.Windows.Forms.CheckBox
  $svalue.Text = "Activado"
  $svalue.Location = New-Object System.Drawing.Point(170, 18)
  $applyS = New-Object System.Windows.Forms.Button
  $applyS.Text = "Aplicar switch"
  $applyS.Location = New-Object System.Drawing.Point(270, 14)
  $applyS.Size = New-Object System.Drawing.Size(120, 28)
  $applyS.Add_Click({ Send-EditorCommand "switch_set" @{ id = [int]$sid.Value; value = $svalue.Checked } }.GetNewClosure())
  $dlg.Controls.Add((New-Label "Variable" 18 58 60))
  $vid = New-Number 78 56 1 9999 80
  $vvalue = New-TextBox 170 56 170
  $applyV = New-Object System.Windows.Forms.Button
  $applyV.Text = "Aplicar variable"
  $applyV.Location = New-Object System.Drawing.Point(352, 54)
  $applyV.Size = New-Object System.Drawing.Size(120, 28)
  $applyV.Add_Click({ Send-EditorCommand "variable_set" @{ id = [int]$vid.Value; value = $vvalue.Text } }.GetNewClosure())
  $switches = New-Object System.Windows.Forms.TextBox
  $switches.Multiline = $true
  $switches.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $switches.Location = New-Object System.Drawing.Point(18, 128)
  $switches.Size = New-Object System.Drawing.Size(280, 230)
  $switches.Text = (@($script:State.switches.on) -join ", ")
  $variables = New-Object System.Windows.Forms.TextBox
  $variables.Multiline = $true
  $variables.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $variables.Location = New-Object System.Drawing.Point(320, 128)
  $variables.Size = New-Object System.Drawing.Size(290, 230)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($var in @($script:State.variables.values)) { $lines.Add(("{0} = {1} ({2})" -f $var.id, $var.value, $var.type)) }
  $variables.Text = ($lines -join [Environment]::NewLine)
  $dlg.Controls.AddRange(@($sid, $svalue, $applyS, $vid, $vvalue, $applyV, (New-Label "Switches activados" 18 102 150), (New-Label "Variables con valor" 320 102 150), $switches, $variables))
  [void]$dlg.Show($form)
}

function Show-TrainerInfoWindow {
  if ($null -eq $script:State -or $null -eq $script:State.trainer) {
    [void][System.Windows.Forms.MessageBox]::Show("Primero carga una partida y usa Actualizar.", "Datos del entrenador")
    return
  }
  $t = $script:State.trainer
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Datos del entrenador"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(540, 390)
  $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }
  $dlg.Controls.Add((New-Label "Nombre" 24 24 80))
  $name = New-TextBox 116 22 160
  $name.Text = [string]$t.name
  $dlg.Controls.Add((New-Label "Dinero" 24 62 80))
  $money = New-Number 116 60 0 9999999 110
  Set-NumberValue $money ([int64]$t.money)
  $dlg.Controls.Add((New-Label "ID completo" 24 100 90))
  $tid = New-Number 116 98 0 2147483647 110
  Set-NumberValue $tid ([int64]$t.id)
  $pokedex = New-Object System.Windows.Forms.CheckBox
  $pokedex.Text = "Pokedex obtenida"
  $pokedex.Checked = [bool]$t.pokedex
  $pokedex.Location = New-Object System.Drawing.Point(300, 24)
  $pokegear = New-Object System.Windows.Forms.CheckBox
  $pokegear.Text = "Pokegear obtenido"
  $pokegear.Checked = [bool]$t.pokegear
  $pokegear.Location = New-Object System.Drawing.Point(300, 56)
  $apply = New-Object System.Windows.Forms.Button
  $apply.Text = "Aplicar"
  $apply.Location = New-Object System.Drawing.Point(376, 300)
  $apply.Size = New-Object System.Drawing.Size(110, 30)
  $apply.Add_Click({
    Send-EditorCommand "trainer_set" @{ name = $name.Text; money = [int]$money.Value; id = [int]$tid.Value; pokedex = $pokedex.Checked; pokegear = $pokegear.Checked }
  }.GetNewClosure())
  $dlg.Controls.AddRange(@($name, $money, $tid, $pokedex, $pokegear, $apply))
  [void]$dlg.Show($form)
}

function Show-BoxLayoutWindow {
  if ($null -eq $script:State -or $null -eq $script:State.storage) {
    [void][System.Windows.Forms.MessageBox]::Show("Primero carga una partida y usa Actualizar.", "Diseno de cajas")
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Diseno de cajas"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(520, 390)
  $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }
  $list = New-Object System.Windows.Forms.ListBox
  $list.Location = New-Object System.Drawing.Point(16, 18)
  $list.Size = New-Object System.Drawing.Size(150, 300)
  foreach ($box in @($script:State.storage.boxes)) { [void]$list.Items.Add(("{0}. {1}" -f ([int]$box.index + 1), $box.name)) }
  $dlg.Controls.Add((New-Label "Nombre de caja" 190 28 120))
  $name = New-TextBox 190 58 220
  $preview = New-Object System.Windows.Forms.Panel
  $preview.Location = New-Object System.Drawing.Point(190, 98)
  $preview.Size = New-Object System.Drawing.Size(280, 160)
  $preview.BackColor = [System.Drawing.Color]::FromArgb(139, 214, 142)
  $save = New-Object System.Windows.Forms.Button
  $save.Text = "Aplicar nombre"
  $save.Location = New-Object System.Drawing.Point(340, 288)
  $save.Size = New-Object System.Drawing.Size(130, 30)
  $list.Add_SelectedIndexChanged({
    if ($list.SelectedIndex -lt 0) { return }
    $box = @($script:State.storage.boxes)[$list.SelectedIndex]
    if ($null -ne $box) { $name.Text = [string]$box.name }
  }.GetNewClosure())
  $save.Add_Click({
    if ($list.SelectedIndex -lt 0) { return }
    Send-EditorCommand "box_set" @{ box = [int]$list.SelectedIndex; name = $name.Text }
  }.GetNewClosure())
  if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
  $dlg.Controls.AddRange(@($list, $name, $preview, $save))
  [void]$dlg.Show($form)
}

function Refresh-All {
  param([bool]$Force = $false)
  Load-LiveData
  if (!$Force -and (($script:Dirty) -or (Get-PendingCommandCount -gt 0) -or (Test-UserEditing) -or ([DateTime]::Now -lt $script:PendingUntil))) {
    if ($script:Dirty -or (Get-PendingCommandCount -gt 0)) {
      Update-PendingStatus "Hay cambios sin guardar"
    }
    return
  }
  Refresh-EditorViewsFromState $true
}

function Add-SelectedPokemonValues {
  param([hashtable]$Values)
  if ($null -eq $script:SelectedPokemon) { return $null }
  $Values["loc"] = [string]$script:SelectedPokemon.loc
  $Values["index"] = [int]$script:SelectedPokemon.index
  $Values["box"] = [int]$script:SelectedPokemon.box
  $Values["slot"] = [int]$script:SelectedPokemon.slot
  return $Values
}

function Add-DestinationValues {
  param([hashtable]$Values)
  $Values["destLoc"] = $(if ($script:DestLoc.SelectedIndex -eq 0) { "party" } else { "box" })
  $Values["destIndex"] = ([int]$script:DestPartyIndex.Value) - 1
  $Values["destBox"] = ([int]$script:DestBox.Value) - 1
  $Values["destSlot"] = ([int]$script:DestSlot.Value) - 1
  $Values["replace"] = $script:ReplaceSlot.Checked
  return $Values
}

function Get-EditedPokemonValues {
  if ($null -eq $script:SelectedPokemon) { return $null }
  $values = @{
    loc = $script:SelectedPokemon.loc
    index = [int]$script:SelectedPokemon.index
    box = [int]$script:SelectedPokemon.box
    slot = [int]$script:SelectedPokemon.slot
    species = [int]$script:PokeSpecies.Value
    nickname = $script:PokeNick.Text
    level = [int]$script:PokeLevel.Value
    exp = [int64]$script:PokeExp.Value
    hp = [int]$script:PokeHp.Value
    status = [int]$script:PokeStatus.Value
    statusCount = [int]$script:PokeStatusCount.Value
    happiness = [int]$script:PokeHappiness.Value
    item = [int]$script:PokeItem.Value
    natureflag = [int]$script:PokeNatureFlag.Value
    abilityflag = [int]$script:PokeAbilityFlag.Value
    genderflag = [int]$script:PokeGenderFlag.Value
    eggsteps = [int]$script:PokeEggSteps.Value
    form = [int]$script:PokeForm.Value
    pokerus = [int]$script:PokePokerus.Value
    shiny = $script:PokeShiny.Checked
    ot = $script:PokeOt.Text
    otgender = [int]$script:PokeOtGender.Value
    trainerID = [int64]$script:PokeTrainerId.Value
    personalID = [int64]$script:PokePersonalId.Value
    language = [int]$script:PokeLanguage.Value
    ballused = [int]$script:PokeBallUsed.Value
    obtainMode = [int]$script:PokeObtainMode.Value
    obtainLevel = [int]$script:PokeObtainLevel.Value
    obtainMap = [int]$script:PokeObtainMap.Value
    obtainText = $script:PokeObtainText.Text
    hatchedMap = [int]$script:PokeHatchedMap.Value
    markings = [int]$script:PokeMarkings.Value
    expshare = $script:PokeExpShare.Checked
    cool = [int]$script:PokeCool.Value
    beauty = [int]$script:PokeBeauty.Value
    cute = [int]$script:PokeCute.Value
    smart = [int]$script:PokeSmart.Value
    tough = [int]$script:PokeTough.Value
    sheen = [int]$script:PokeSheen.Value
    timeReceived = [int64]$script:PokeTimeReceived.Value
    timeEggHatched = [int64]$script:PokeTimeEggHatched.Value
    firstmoves = $script:PokeFirstMoves.Text
    ribbons = $script:PokeRibbons.Text
  }
  Add-EditorStatValues $values
  for ($i = 0; $i -lt 4; $i++) {
    $values["move$i"] = [int]$script:MoveIds[$i].Value
    $values["move${i}pp"] = [int]$script:MovePps[$i].Value
    $values["move${i}ppup"] = [int]$script:MovePpUps[$i].Value
  }
  return $values
}

function Set-ObjectProperty {
  param($Object, [string]$Name, $Value)
  if ($null -eq $Object) { return }
  if ($Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
  }
}

function Copy-JsonObject {
  param($Object)
  if ($null -eq $Object) { return $null }
  return (($Object | ConvertTo-Json -Depth 64 -Compress) | ConvertFrom-Json)
}

function Set-LocalBagQuantity {
  param([int]$ItemId, [int]$Quantity, [int]$Pocket = -1)
  if ($null -eq $script:State -or $ItemId -le 0) { return }
  if ($null -eq $script:State.bag) { Set-ObjectProperty $script:State "bag" @() }
  $items = @()
  $found = $false
  foreach ($entry in @($script:State.bag)) {
    if ([int]$entry.id -eq $ItemId) {
      $found = $true
      if ($Quantity -gt 0) {
        Set-ObjectProperty $entry "quantity" $Quantity
        if ($Pocket -gt 0) { Set-ObjectProperty $entry "pocket" $Pocket }
        $items += $entry
      }
    } else {
      $items += $entry
    }
  }
  if (!$found -and $Quantity -gt 0) {
    $name = Get-EntryName $script:Data.items $ItemId
    if ($Pocket -le 0 -and $null -ne $script:Data -and $null -ne $script:Data.items) {
      foreach ($item in @($script:Data.items)) {
        if ([int]$item.id -eq $ItemId) { $Pocket = [int]$item.pocket; break }
      }
    }
    if ($Pocket -le 0) { $Pocket = 1 }
    $slot = 0
    foreach ($entry in $items) {
      if ([int]$entry.pocket -eq $Pocket -and [int]$entry.slot -ge $slot) { $slot = [int]$entry.slot + 1 }
    }
    $items += [pscustomobject]@{
      pocket = $Pocket
      slot = $slot
      id = $ItemId
      name = $name
      quantity = $Quantity
    }
  }
  Set-ObjectProperty $script:State "bag" @($items | Sort-Object { [int]$_.pocket }, { [int]$_.slot }, { [int]$_.id })
}

function Get-AchievementStatusName {
  param([int]$Status)
  switch ($Status) {
    1 { return "Oculto" }
    3 { return "Completado" }
    default { return "Activo" }
  }
}

function Set-LocalAchievementStatus {
  param([int]$Index, [int]$Status)
  if ($null -eq $script:State -or $null -eq $script:State.achievements) { return }
  foreach ($achievement in @($script:State.achievements)) {
    if ([int]$achievement.index -eq $Index) {
      Set-ObjectProperty $achievement "status" $Status
      Set-ObjectProperty $achievement "statusName" (Get-AchievementStatusName $Status)
      return
    }
  }
}

function Apply-LocalPokemonValues {
  param($Pokemon, [hashtable]$Values)
  if ($null -eq $Pokemon -or $null -eq $Values) { return $Pokemon }
  $species = [int]$Values["species"]
  $item = [int]$Values["item"]
  $nature = [int]$Values["natureflag"]
  $status = [int]$Values["status"]
  Set-ObjectProperty $Pokemon "species" $species
  Set-ObjectProperty $Pokemon "speciesName" (Get-EntryName $script:Data.species $species)
  Set-ObjectProperty $Pokemon "nickname" ([string]$Values["nickname"])
  Set-ObjectProperty $Pokemon "level" ([int]$Values["level"])
  Set-ObjectProperty $Pokemon "exp" ([int64]$Values["exp"])
  Set-ObjectProperty $Pokemon "hp" ([int]$Values["hp"])
  Set-ObjectProperty $Pokemon "status" $status
  Set-ObjectProperty $Pokemon "statusCount" ([int]$Values["statusCount"])
  Set-ObjectProperty $Pokemon "happiness" ([int]$Values["happiness"])
  Set-ObjectProperty $Pokemon "item" $item
  Set-ObjectProperty $Pokemon "itemName" (Get-EntryName $script:Data.items $item)
  Set-ObjectProperty $Pokemon "natureflag" ($(if ($nature -lt 0) { $null } else { $nature }))
  Set-ObjectProperty $Pokemon "natureName" ($(if ($nature -lt 0) { "Natural" } else { Get-EntryName $script:Data.natures $nature }))
  Set-ObjectProperty $Pokemon "abilityflag" ([int]$Values["abilityflag"])
  Set-ObjectProperty $Pokemon "genderflag" ([int]$Values["genderflag"])
  Set-ObjectProperty $Pokemon "eggsteps" ([int]$Values["eggsteps"])
  Set-ObjectProperty $Pokemon "form" ([int]$Values["form"])
  Set-ObjectProperty $Pokemon "pokerus" ([int]$Values["pokerus"])
  Set-ObjectProperty $Pokemon "shiny" ([bool]$Values["shiny"])
  Set-ObjectProperty $Pokemon "shinyflag" ([bool]$Values["shiny"])
  Set-ObjectProperty $Pokemon "ot" ([string]$Values["ot"])
  Set-ObjectProperty $Pokemon "otgender" ([int]$Values["otgender"])
  Set-ObjectProperty $Pokemon "trainerID" ([int64]$Values["trainerID"])
  Set-ObjectProperty $Pokemon "personalID" ([int64]$Values["personalID"])
  Set-ObjectProperty $Pokemon "language" ([int]$Values["language"])
  Set-ObjectProperty $Pokemon "ballused" ([int]$Values["ballused"])
  Set-ObjectProperty $Pokemon "obtainMode" ([int]$Values["obtainMode"])
  Set-ObjectProperty $Pokemon "obtainLevel" ([int]$Values["obtainLevel"])
  Set-ObjectProperty $Pokemon "obtainMap" ([int]$Values["obtainMap"])
  Set-ObjectProperty $Pokemon "obtainText" ([string]$Values["obtainText"])
  Set-ObjectProperty $Pokemon "hatchedMap" ([int]$Values["hatchedMap"])
  Set-ObjectProperty $Pokemon "markings" ([int]$Values["markings"])
  Set-ObjectProperty $Pokemon "expshare" ([bool]$Values["expshare"])
  $ivs = @()
  $evs = @()
  for ($i = 0; $i -lt 6; $i++) {
    $ivs += [int]$Values["iv$i"]
    $evs += [int]$Values["ev$i"]
  }
  Set-ObjectProperty $Pokemon "iv" @($ivs)
  Set-ObjectProperty $Pokemon "ev" @($evs)
  $moves = @()
  for ($i = 0; $i -lt 4; $i++) {
    $moveId = [int]$Values["move$i"]
    $moves += [pscustomobject]@{
      slot = $i
      id = $moveId
      name = $(if ($moveId -le 0) { "" } else { Get-EntryName $script:Data.moves $moveId })
      pp = [int]$Values["move${i}pp"]
      ppup = [int]$Values["move${i}ppup"]
      totalpp = [int]$Values["move${i}pp"]
    }
  }
  Set-ObjectProperty $Pokemon "moves" @($moves)
  return $Pokemon
}

function New-LocalPokemonFromValues {
  param([hashtable]$Values)
  $source = Find-PokemonEntry ([string]$Values["loc"]) ([int]$Values["index"]) ([int]$Values["box"]) ([int]$Values["slot"])
  if ($null -ne $source) {
    return Apply-LocalPokemonValues (Copy-JsonObject $source) $Values
  }
  $pokemon = [pscustomobject]@{
    stats = [pscustomobject]@{ hp = 0; attack = 0; defense = 0; spatk = 0; spdef = 0; speed = 0 }
    totalhp = [int]$Values["hp"]
    baseStats = @(0,0,0,0,0,0)
    contest = [pscustomobject]@{ cool = 0; beauty = 0; cute = 0; smart = 0; tough = 0; sheen = 0 }
    firstmoves = @()
    ribbons = @()
  }
  return Apply-LocalPokemonValues $pokemon $Values
}

function Set-LocalPokemonLocation {
  param($Pokemon, $Tag)
  if ($null -eq $Pokemon -or $null -eq $Tag) { return }
  Set-ObjectProperty $Pokemon "loc" ([string]$Tag.Loc)
  Set-ObjectProperty $Pokemon "index" ([int]$Tag.Index)
  Set-ObjectProperty $Pokemon "box" ($(if ($Tag.Loc -eq "box") { [int]$Tag.Box } else { $null }))
  Set-ObjectProperty $Pokemon "slot" ($(if ($Tag.Loc -eq "box") { [int]$Tag.Slot } else { $null }))
}

function Remove-LocalPokemonAt {
  param($Tag)
  if ($null -eq $script:State -or $null -eq $Tag) { return }
  if ($Tag.Loc -eq "party") {
    $items = @()
    foreach ($p in @($script:State.party)) {
      if ([int]$p.index -ne [int]$Tag.Index) { $items += $p }
    }
    Set-ObjectProperty $script:State "party" @($items)
  } elseif ($Tag.Loc -eq "box" -and $null -ne $script:State.storage -and $null -ne $script:State.storage.boxes) {
    $boxInfo = @($script:State.storage.boxes)[[int]$Tag.Box]
    if ($null -eq $boxInfo) { return }
    $items = @()
    foreach ($p in @($boxInfo.pokemon)) {
      if ([int]$p.slot -ne [int]$Tag.Slot) { $items += $p }
    }
    Set-ObjectProperty $boxInfo "pokemon" @($items)
    Set-ObjectProperty $boxInfo "count" @($items).Count
  }
}

function Set-LocalPokemonAt {
  param($Tag, $Pokemon)
  if ($null -eq $script:State -or $null -eq $Tag -or $null -eq $Pokemon) { return }
  Set-LocalPokemonLocation $Pokemon $Tag
  if ($Tag.Loc -eq "party") {
    $items = @()
    $placed = $false
    foreach ($p in @($script:State.party)) {
      if ([int]$p.index -eq [int]$Tag.Index) {
        $items += $Pokemon
        $placed = $true
      } else {
        $items += $p
      }
    }
    if (!$placed) { $items += $Pokemon }
    Set-ObjectProperty $script:State "party" @($items)
  } elseif ($Tag.Loc -eq "box" -and $null -ne $script:State.storage -and $null -ne $script:State.storage.boxes) {
    $boxInfo = @($script:State.storage.boxes)[[int]$Tag.Box]
    if ($null -eq $boxInfo) { return }
    $items = @()
    $placed = $false
    foreach ($p in @($boxInfo.pokemon)) {
      if ([int]$p.slot -eq [int]$Tag.Slot) {
        $items += $Pokemon
        $placed = $true
      } else {
        $items += $p
      }
    }
    if (!$placed) { $items += $Pokemon }
    Set-ObjectProperty $boxInfo "pokemon" @($items | Sort-Object { [int]$_.slot })
    Set-ObjectProperty $boxInfo "count" @($items).Count
  }
}

function Refresh-PokemonSlotViews {
  Refresh-PartyTab
  Refresh-PCTab
  Refresh-PokemonList
}

function Apply-LocalSlotMove {
  param($SourceTag, $TargetTag)
  if ($null -eq $SourceTag -or $null -eq $TargetTag -or $SourceTag.Empty) { return }
  $source = Copy-JsonObject (Find-PokemonEntry $SourceTag.Loc $SourceTag.Index $SourceTag.Box $SourceTag.Slot)
  if ($null -eq $source) { return }
  $target = Copy-JsonObject (Find-PokemonEntry $TargetTag.Loc $TargetTag.Index $TargetTag.Box $TargetTag.Slot)
  Remove-LocalPokemonAt $SourceTag
  if ($null -ne $target) {
    Set-LocalPokemonAt $SourceTag $target
  }
  Set-LocalPokemonAt $TargetTag $source
  Refresh-PokemonSlotViews
}

function Apply-LocalDraftDrop {
  param([hashtable]$Values, $TargetTag)
  if ($null -eq $Values -or $null -eq $TargetTag) { return }
  $copy = New-LocalPokemonFromValues $Values
  if ($null -eq $copy) { return }
  Set-LocalPokemonAt $TargetTag $copy
  $script:SelectedPokemon = $copy
  $script:SelectedSlotTag = $TargetTag
  Refresh-PokemonSlotViews
}

function ConvertTo-Hashtable {
  param($Object)
  if ($null -eq $Object) { return $null }
  if ($Object -is [hashtable]) {
    $clone = @{}
    foreach ($key in $Object.Keys) { $clone[$key] = $Object[$key] }
    return $clone
  }
  $hash = @{}
  foreach ($prop in @($Object.PSObject.Properties)) {
    $hash[$prop.Name] = $prop.Value
  }
  return $hash
}

function Format-EditorCommandName {
  param([string]$Command)
  switch ($Command) {
    "pokemon_set" { return "Pokemon editado" }
    "pokemon_place_edited" { return "Pokemon colocado desde editor" }
    "pokemon_move" { return "Pokemon movido" }
    "pokemon_swap" { return "Pokemon intercambiados" }
    "pokemon_clone" { return "Pokemon clonado" }
    "pokemon_delete" { return "Pokemon borrado" }
    "heal_party" { return "Equipo curado" }
    "trainer_set" { return "Entrenador editado" }
    "set_item_qty" { return "Objeto editado" }
    "box_set" { return "Caja editada" }
    "pokedex_set" { return "Pokedex editada" }
    "achievement_set" { return "Logro editado" }
    "switch_set" { return "Switch editado" }
    "variable_set" { return "Variable editada" }
    default { return $Command }
  }
}

function Get-HistoryPokemonSummaryFromValues {
  param($Values)
  $hash = ConvertTo-Hashtable $Values
  if ($null -eq $hash -or !$hash.ContainsKey("species")) { return "" }
  $species = [int]$hash["species"]
  $speciesName = Get-EntryName $script:Data.species $species
  if ([string]::IsNullOrWhiteSpace($speciesName)) { $speciesName = "Especie $species" }
  $nick = ""
  if ($hash.ContainsKey("nickname")) { $nick = [string]$hash["nickname"] }
  if ([string]::IsNullOrWhiteSpace($nick) -or $nick -eq $speciesName) { return $speciesName }
  return ("{0} ({1})" -f $nick, $speciesName)
}

function Get-HistoryPokemonSummaryFromPokemon {
  param($Pokemon)
  if ($null -eq $Pokemon) { return "" }
  $speciesName = [string]$Pokemon.speciesName
  if ([string]::IsNullOrWhiteSpace($speciesName) -and $null -ne $Pokemon.species) {
    $speciesName = Get-EntryName $script:Data.species ([int]$Pokemon.species)
  }
  if ([string]::IsNullOrWhiteSpace($speciesName)) { $speciesName = "Pokemon" }
  $nick = [string]$Pokemon.nickname
  if ([string]::IsNullOrWhiteSpace($nick) -or $nick -eq $speciesName) { return $speciesName }
  return ("{0} ({1})" -f $nick, $speciesName)
}

function Get-HistoryLocationText {
  param($Tag, $Values)
  $loc = ""
  $index = -1
  $box = -1
  $slot = -1
  if ($null -ne $Tag) {
    $loc = [string]$Tag.Loc
    $index = [int]$Tag.Index
    $box = [int]$Tag.Box
    $slot = [int]$Tag.Slot
  } else {
    $hash = ConvertTo-Hashtable $Values
    if ($null -ne $hash) {
      if ($hash.ContainsKey("loc")) { $loc = [string]$hash["loc"] }
      if ($hash.ContainsKey("index")) { $index = [int]$hash["index"] }
      if ($hash.ContainsKey("box")) { $box = [int]$hash["box"] }
      if ($hash.ContainsKey("slot")) { $slot = [int]$hash["slot"] }
    }
  }
  if ($loc -eq "party") { return ("Equipo slot {0}" -f ($index + 1)) }
  if ($loc -eq "box") { return ("Caja {0}, slot {1}" -f ($box + 1), ($slot + 1)) }
  return ""
}

function Get-CurrentDirtyPokemonValues {
  if (!$script:Dirty -or $null -eq $script:SelectedPokemon) { return $null }
  try {
    $values = Get-EditedPokemonValues
    if ($null -eq $values) { return $null }
    return Copy-JsonObject $values
  } catch {
    return $null
  }
}

function Copy-PendingCommands {
  $items = New-Object System.Collections.ArrayList
  foreach ($entry in @($script:PendingCommands)) {
    [void]$items.Add((Copy-JsonObject $entry))
  }
  return $items
}

function Get-EditorSnapshot {
  param([string]$Label, [string]$Category = "General")
  $dirtyValues = Get-CurrentDirtyPokemonValues
  $pokemonSummary = ""
  $locationText = ""
  if ($null -ne $dirtyValues) {
    $pokemonSummary = Get-HistoryPokemonSummaryFromValues $dirtyValues
    $locationText = Get-HistoryLocationText $script:SelectedSlotTag $dirtyValues
  } elseif ($Category -eq "Pokemon" -and $null -ne $script:SelectedPokemon) {
    $pokemonSummary = Get-HistoryPokemonSummaryFromPokemon $script:SelectedPokemon
    $locationText = Get-HistoryLocationText $script:SelectedSlotTag $null
  }
  return [pscustomobject]@{
    Label = $Label
    Category = $Category
    Time = (Get-Date)
    State = (Copy-JsonObject $script:State)
    PendingCommands = (Copy-PendingCommands)
    Dirty = [bool]$script:Dirty
    DirtyValues = $dirtyValues
    SelectedSlotTag = (Copy-JsonObject $script:SelectedSlotTag)
    SelectedPokemonSummary = $pokemonSummary
    SelectedLocationText = $locationText
    PCBoxIndex = $(if ($null -ne $script:PCBox) { [int]$script:PCBox.SelectedIndex } else { -1 })
    HexBoxIndex = $(if ($null -ne $script:HexBoxSelector) { [int]$script:HexBoxSelector.SelectedIndex } else { -1 })
    PokemonSourceIndex = $(if ($null -ne $script:PokemonSource) { [int]$script:PokemonSource.SelectedIndex } else { -1 })
    PokemonBoxIndex = $(if ($null -ne $script:PokemonBox) { [int]$script:PokemonBox.SelectedIndex } else { -1 })
    SelectedTabName = $(if ($null -ne $tabs -and $null -ne $tabs.SelectedTab) { [string]$tabs.SelectedTab.Text } else { "" })
  }
}

function Update-HistoryViews {
  if ($null -ne $script:HistoryListBox) {
    $script:HistoryListUpdating = $true
    try {
      $script:HistoryListBox.Items.Clear()
      for ($i = 0; $i -lt $script:HistoryStates.Count; $i++) {
        $state = $script:HistoryStates[$i]
        $prefix = $(if ($i -eq $script:HistoryIndex) { "> " } else { "  " })
        $time = ""
        try { $time = ([datetime]$state.Time).ToString("HH:mm:ss") } catch { $time = "" }
        $extra = ""
        if (![string]::IsNullOrWhiteSpace([string]$state.SelectedPokemonSummary)) {
          $extra = " - " + [string]$state.SelectedPokemonSummary
        }
        $pendingCount = @($state.PendingCommands | Where-Object { $null -ne $_ }).Count
        if ($pendingCount -gt 0) { $extra += (" - pendientes: {0}" -f $pendingCount) }
        [void]$script:HistoryListBox.Items.Add(("{0}{1:000}  {2}  {3}{4}" -f $prefix, $i, $time, [string]$state.Label, $extra))
      }
      if ($script:HistoryIndex -ge 0 -and $script:HistoryIndex -lt $script:HistoryListBox.Items.Count) {
        $script:HistoryListBox.SelectedIndex = $script:HistoryIndex
      }
    } finally {
      $script:HistoryListUpdating = $false
    }
  }
  if ($null -ne $script:ModifiedPokemonList) {
    $script:HistoryListUpdating = $true
    try {
      $script:ModifiedPokemonList.Items.Clear()
      $script:ModifiedPokemonHistoryIndexes = @()
      for ($i = 0; $i -lt $script:HistoryStates.Count; $i++) {
        $state = $script:HistoryStates[$i]
        $summary = [string]$state.SelectedPokemonSummary
        if ([string]::IsNullOrWhiteSpace($summary)) { continue }
        $where = [string]$state.SelectedLocationText
        $text = $(if ([string]::IsNullOrWhiteSpace($where)) { $summary } else { "{0} - {1}" -f $summary, $where })
        [void]$script:ModifiedPokemonList.Items.Add(("{0:000}  {1}" -f $i, $text))
        $script:ModifiedPokemonHistoryIndexes += $i
      }
    } finally {
      $script:HistoryListUpdating = $false
    }
  }
}

function Register-HistoryState {
  param([string]$Label, [string]$Category = "General")
  if ($script:HistoryRestoring -or $null -eq $script:State) { return }
  if ([string]::IsNullOrWhiteSpace($Label)) { $Label = "Cambio" }
  if ($script:HistoryIndex -ge 0 -and $script:HistoryIndex -lt ($script:HistoryStates.Count - 1)) {
    for ($i = $script:HistoryStates.Count - 1; $i -gt $script:HistoryIndex; $i--) {
      $script:HistoryStates.RemoveAt($i)
    }
  }
  [void]$script:HistoryStates.Add((Get-EditorSnapshot $Label $Category))
  while ($script:HistoryStates.Count -gt 120) {
    $script:HistoryStates.RemoveAt(0)
  }
  $script:HistoryIndex = $script:HistoryStates.Count - 1
  Update-HistoryViews
}

function Request-HistoryCheckpoint {
  param([string]$Label, [string]$Category = "General")
  if ($script:HistoryRestoring -or $script:LoadingUi -or $null -eq $script:State) { return }
  $script:HistoryPendingLabel = $Label
  $script:HistoryPendingCategory = $Category
  if ($null -eq $script:HistoryTimer) {
    $script:HistoryTimer = New-Object System.Windows.Forms.Timer
    $script:HistoryTimer.Interval = 650
    $script:HistoryTimer.Add_Tick({
      $script:HistoryTimer.Stop()
      Register-HistoryState $script:HistoryPendingLabel $script:HistoryPendingCategory
    })
  }
  $script:HistoryTimer.Stop()
  $script:HistoryTimer.Start()
}

function Commit-PendingHistoryCheckpoint {
  if ($null -ne $script:HistoryTimer -and $script:HistoryTimer.Enabled) {
    $script:HistoryTimer.Stop()
    Register-HistoryState $script:HistoryPendingLabel $script:HistoryPendingCategory
  }
}

function Reset-History {
  if ($null -ne $script:HistoryTimer) { $script:HistoryTimer.Stop() }
  if ($null -ne $script:HistoryStates) { $script:HistoryStates.Clear() }
  $script:HistoryIndex = -1
  Update-HistoryViews
}

function Refresh-EditorViewsFromState {
  param([bool]$UseFileRaw = $false)
  Populate-EditorNamedControls
  Refresh-TrainerTab
  Refresh-PartyTab
  Refresh-PokemonList
  Refresh-PCTab
  $bagTabActive = $false
  try { $bagTabActive = ($null -ne $tabs -and $null -ne $bagTab -and $tabs.SelectedTab -eq $bagTab) } catch {}
  if ($bagTabActive) { Refresh-BagTab }
  Refresh-WorldTab
  $rawTabActive = $false
  try { $rawTabActive = ($null -ne $tabs -and $null -ne $rawTab -and $tabs.SelectedTab -eq $rawTab) } catch {}
  if ($rawTabActive) {
    if ($UseFileRaw) {
      Refresh-RawTab
    } elseif ($null -ne $script:RawState) {
      try {
        $script:RawState.Text = ($script:State | ConvertTo-Json -Depth 64)
      } catch {
        Refresh-RawTab
      }
    }
  }
  if ($null -ne $script:CreatePreview) { Update-SpeciesPreview $script:CreatePreview $script:CreateSpecies }
}

function Restore-HistoryState {
  param([int]$Index)
  if ($Index -lt 0 -or $Index -ge $script:HistoryStates.Count) { return }
  $snapshot = $script:HistoryStates[$Index]
  $script:HistoryRestoring = $true
  try {
    $script:State = Copy-JsonObject $snapshot.State
    if ($null -eq $script:PendingCommands) { $script:PendingCommands = New-Object System.Collections.ArrayList }
    $script:PendingCommands.Clear()
    foreach ($entry in @($snapshot.PendingCommands)) {
      [void]$script:PendingCommands.Add((Copy-JsonObject $entry))
    }
    $script:Dirty = [bool]$snapshot.Dirty
    $script:SelectedSlotTag = Copy-JsonObject $snapshot.SelectedSlotTag
    $script:HistoryIndex = $Index
    $oldLoading = $script:LoadingUi
    $script:LoadingUi = $true
    try {
      if ($null -ne $script:PCBox -and [int]$snapshot.PCBoxIndex -ge 0 -and [int]$snapshot.PCBoxIndex -lt $script:PCBox.Items.Count) {
        $script:PCBox.SelectedIndex = [int]$snapshot.PCBoxIndex
      }
      if ($null -ne $script:PokemonSource -and [int]$snapshot.PokemonSourceIndex -ge 0 -and [int]$snapshot.PokemonSourceIndex -lt $script:PokemonSource.Items.Count) {
        $script:PokemonSource.SelectedIndex = [int]$snapshot.PokemonSourceIndex
      }
      if ($null -ne $script:PokemonBox -and [int]$snapshot.PokemonBoxIndex -ge 0 -and [int]$snapshot.PokemonBoxIndex -lt $script:PokemonBox.Items.Count) {
        $script:PokemonBox.SelectedIndex = [int]$snapshot.PokemonBoxIndex
      }
    } finally {
      $script:LoadingUi = $oldLoading
    }
    Refresh-EditorViewsFromState $false

    $dirtyValues = ConvertTo-Hashtable $snapshot.DirtyValues
    if ($null -ne $dirtyValues) {
      $draft = New-LocalPokemonFromValues $dirtyValues
      if ($null -ne $draft) {
        $script:SelectedPokemon = $draft
        Fill-PokemonFields $draft
      }
    } elseif ($null -ne $script:SelectedSlotTag -and !$script:SelectedSlotTag.Empty) {
      Select-SlotPokemon $script:SelectedSlotTag $false
    }
    $script:Dirty = [bool]$snapshot.Dirty
    if ($null -ne $tabs -and [string]$snapshot.SelectedTabName -ne "") {
      foreach ($tab in @($tabs.TabPages)) {
        if ([string]$tab.Text -eq [string]$snapshot.SelectedTabName) {
          $tabs.SelectedTab = $tab
          break
        }
      }
    }
    Update-HistoryViews
    if ($script:Dirty -or (Get-PendingCommandCount -gt 0)) {
      Update-PendingStatus ("Estado restaurado: " + [string]$snapshot.Label)
    } elseif ($null -ne $script:StatusLabel) {
      $script:StatusLabel.Text = "Estado restaurado: " + [string]$snapshot.Label
    }
  } finally {
    $script:HistoryRestoring = $false
  }
}

function Undo-History {
  Commit-PendingHistoryCheckpoint
  if ($script:HistoryIndex -gt 0) {
    Restore-HistoryState ($script:HistoryIndex - 1)
  } elseif ($null -ne $script:StatusLabel) {
    $script:StatusLabel.Text = "No hay cambios anteriores en el historial."
  }
}

function Redo-History {
  Commit-PendingHistoryCheckpoint
  if ($script:HistoryIndex -ge 0 -and $script:HistoryIndex -lt ($script:HistoryStates.Count - 1)) {
    Restore-HistoryState ($script:HistoryIndex + 1)
  } elseif ($null -ne $script:StatusLabel) {
    $script:StatusLabel.Text = "No hay cambios posteriores en el historial."
  }
}

function Invoke-HistoryShortcut {
  param([string]$Action)
  $now = [DateTime]::Now
  if ($script:LastHistoryShortcutAction -eq $Action -and ($now - $script:LastHistoryShortcutTime).TotalMilliseconds -lt 120) { return }
  $script:LastHistoryShortcutAction = $Action
  $script:LastHistoryShortcutTime = $now
  if ($Action -eq "undo") {
    Undo-History
  } elseif ($Action -eq "redo") {
    Redo-History
  }
}

function Show-HistoryWindow {
  if ($null -ne $script:HistoryWindow -and !$script:HistoryWindow.IsDisposed) {
    $script:HistoryWindow.Activate()
    return
  }
  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = "Historial de acciones"
  $dlg.StartPosition = "CenterParent"
  $dlg.Size = New-Object System.Drawing.Size(680, 500)
  $dlg.MinimumSize = New-Object System.Drawing.Size(620, 420)
  if ($null -ne $script:GameIcon) { $dlg.Icon = $script:GameIcon }

  $historyTabs = New-Object System.Windows.Forms.TabControl
  $historyTabs.Location = New-Object System.Drawing.Point(12, 12)
  $historyTabs.Size = New-Object System.Drawing.Size(640, 362)
  $historyTabs.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
  $allPage = New-Object System.Windows.Forms.TabPage
  $allPage.Text = "Todos los cambios"
  $pokemonPage = New-Object System.Windows.Forms.TabPage
  $pokemonPage.Text = "Pokemon modificados"

  $history = New-Object System.Windows.Forms.ListBox
  $history.Dock = [System.Windows.Forms.DockStyle]::Fill
  $modified = New-Object System.Windows.Forms.ListBox
  $modified.Dock = [System.Windows.Forms.DockStyle]::Fill
  $allPage.Controls.Add($history)
  $pokemonPage.Controls.Add($modified)
  [void]$historyTabs.TabPages.Add($allPage)
  [void]$historyTabs.TabPages.Add($pokemonPage)

  $details = New-Object System.Windows.Forms.Label
  $details.Text = "Selecciona una fila para verla. Doble clic o Restaurar vuelve a ese estado local."
  $details.Location = New-Object System.Drawing.Point(12, 382)
  $details.Size = New-Object System.Drawing.Size(640, 24)
  $details.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

  $undo = New-Object System.Windows.Forms.Button
  $undo.Text = "Deshacer"
  $undo.Location = New-Object System.Drawing.Point(12, 414)
  $undo.Size = New-Object System.Drawing.Size(90, 28)
  $redo = New-Object System.Windows.Forms.Button
  $redo.Text = "Rehacer"
  $redo.Location = New-Object System.Drawing.Point(110, 414)
  $redo.Size = New-Object System.Drawing.Size(90, 28)
  $restore = New-Object System.Windows.Forms.Button
  $restore.Text = "Restaurar"
  $restore.Location = New-Object System.Drawing.Point(208, 414)
  $restore.Size = New-Object System.Drawing.Size(96, 28)
  $close = New-Object System.Windows.Forms.Button
  $close.Text = "Cerrar"
  $close.Location = New-Object System.Drawing.Point(562, 414)
  $close.Size = New-Object System.Drawing.Size(90, 28)
  $close.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

  $getSelectedHistoryIndex = {
    if ($historyTabs.SelectedTab -eq $pokemonPage) {
      if ($modified.SelectedIndex -lt 0 -or $modified.SelectedIndex -ge $script:ModifiedPokemonHistoryIndexes.Count) { return -1 }
      return [int]$script:ModifiedPokemonHistoryIndexes[$modified.SelectedIndex]
    }
    return [int]$history.SelectedIndex
  }.GetNewClosure()

  $updateDetails = {
    $idx = & $getSelectedHistoryIndex
    if ($idx -lt 0 -or $idx -ge $script:HistoryStates.Count) {
      $details.Text = "Selecciona una fila para verla. Doble clic o Restaurar vuelve a ese estado local."
      return
    }
    $state = $script:HistoryStates[$idx]
    $when = ""
    try { $when = ([datetime]$state.Time).ToString("HH:mm:ss") } catch { $when = "" }
    $pokemon = [string]$state.SelectedPokemonSummary
    $pendingCount = @($state.PendingCommands | Where-Object { $null -ne $_ }).Count
    $suffix = $(if ([string]::IsNullOrWhiteSpace($pokemon)) { "" } else { " - " + $pokemon })
    $details.Text = ("{0:000}  {1}  {2}{3}  Pendientes: {4}" -f $idx, $when, [string]$state.Label, $suffix, $pendingCount)
  }.GetNewClosure()

  $restoreSelected = {
    $idx = & $getSelectedHistoryIndex
    if ($idx -lt 0) { return }
    Restore-HistoryState $idx
  }.GetNewClosure()

  $history.Add_SelectedIndexChanged({
    if ($script:HistoryListUpdating -or $script:HistoryRestoring) { return }
    & $updateDetails
  }.GetNewClosure())
  $modified.Add_SelectedIndexChanged({
    if ($script:HistoryListUpdating -or $script:HistoryRestoring) { return }
    & $updateDetails
  }.GetNewClosure())
  $historyTabs.Add_SelectedIndexChanged({ & $updateDetails }.GetNewClosure())
  $history.Add_DoubleClick($restoreSelected)
  $modified.Add_DoubleClick($restoreSelected)
  $undo.Add_Click({ Undo-History })
  $redo.Add_Click({ Redo-History })
  $restore.Add_Click($restoreSelected)
  $close.Add_Click({ $dlg.Close() })
  $dlg.Add_FormClosed({
    if ($script:HistoryWindow -eq $dlg) {
      $script:HistoryWindow = $null
      $script:HistoryListBox = $null
      $script:ModifiedPokemonList = $null
    }
  }.GetNewClosure())

  $dlg.Controls.AddRange(@($historyTabs, $details, $undo, $redo, $restore, $close))
  $script:HistoryWindow = $dlg
  $script:HistoryListBox = $history
  $script:ModifiedPokemonList = $modified
  Update-HistoryViews
  [void]$dlg.Show($form)
  [void]$dlg.BeginInvoke([System.Action]{
    try {
      if ($null -eq $script:HistoryWindow -or $script:HistoryWindow.IsDisposed) { return }
      Commit-PendingHistoryCheckpoint
      Update-HistoryViews
    } catch {
      if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = "No se pudo actualizar el historial: " + $_.Exception.Message }
    }
  })
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "SebiHeX | Pokemon Z"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(870, 470)
$form.MinimumSize = New-Object System.Drawing.Size(860, 450)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 248)
if ($null -ne $script:GameIcon) {
  $form.Icon = $script:GameIcon
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount = 3
$root.Margin = New-Object System.Windows.Forms.Padding(0)
$root.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 0)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$form.Controls.Add($root)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = [System.Windows.Forms.DockStyle]::Fill
$top.Height = 26
$top.Padding = New-Object System.Windows.Forms.Padding(0)
$root.Controls.Add($top, 0, 0)

$title = New-Object System.Windows.Forms.Label
$title.Text = "SebiLink Save Editor"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(14, 12)
$title.Size = New-Object System.Drawing.Size(260, 32)
$top.Controls.Add($title)

$refresh = New-Object System.Windows.Forms.Button
$refresh.Text = "Actualizar"
$refresh.Location = New-Object System.Drawing.Point(286, 14)
$refresh.Size = New-Object System.Drawing.Size(100, 30)
$refresh.Add_Click({ Discard-PendingChanges; Refresh-All $true })
Set-Tip $refresh "Recarga los datos vivos del juego. Descarta cambios locales no aplicados."
$top.Controls.Add($refresh)

$save = New-Object System.Windows.Forms.Button
$save.Text = "Guardar partida"
$save.Location = New-Object System.Drawing.Point(394, 14)
$save.Size = New-Object System.Drawing.Size(120, 30)
$save.Add_Click({ Send-EditorCommand "save_game" @{} })
Set-Tip $save "Pide al juego que guarde la partida actual."
$top.Controls.Add($save)

$heal = New-Object System.Windows.Forms.Button
$heal.Text = "Curar equipo"
$heal.Location = New-Object System.Drawing.Point(522, 14)
$heal.Size = New-Object System.Drawing.Size(110, 30)
$heal.Add_Click({ Send-EditorCommand "heal_party" @{} })
Set-Tip $heal "Cura PS, PP y estados del equipo."
$top.Controls.Add($heal)

$script:AutoRefresh = New-Object System.Windows.Forms.CheckBox
$script:AutoRefresh.Text = "Auto"
$script:AutoRefresh.Checked = Get-SebiSettingBool -Path $script:IniPath -Name 'save_editor_auto_refresh' -Default $false
$script:AutoRefresh.Add_CheckedChanged({
  Set-SebiSetting -Path $script:IniPath -Name 'save_editor_auto_refresh' -Value ([string]$script:AutoRefresh.Checked).ToLowerInvariant()
})
$script:AutoRefresh.Location = New-Object System.Drawing.Point(642, 18)
$script:AutoRefresh.Size = New-Object System.Drawing.Size(65, 24)
Set-Tip $script:AutoRefresh "Desactivado: el editor carga al abrir o al pulsar Refresh."
$top.Controls.Add($script:AutoRefresh)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Esperando datos..."
$script:StatusLabel.Location = New-Object System.Drawing.Point(715, 12)
$script:StatusLabel.Size = New-Object System.Drawing.Size(365, 34)
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$top.Controls.Add($script:StatusLabel)

foreach ($ctrl in @($title, $refresh, $save, $heal, $script:AutoRefresh, $script:StatusLabel)) {
  $ctrl.Visible = $false
}

$menuStrip = New-Object System.Windows.Forms.MenuStrip
$menuStrip.Dock = [System.Windows.Forms.DockStyle]::Fill
$menuStrip.BackColor = [System.Drawing.SystemColors]::Control
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Archivo")
$editMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Edicion")
$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Herramientas")
$optionsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Opciones")
$miRefresh = New-Object System.Windows.Forms.ToolStripMenuItem("Actualizar")
$miRefresh.Add_Click({ Discard-PendingChanges; Refresh-All $true; Reset-History; Register-HistoryState "Estado actualizado" "Sistema" })
$miSave = New-Object System.Windows.Forms.ToolStripMenuItem("Guardar partida")
$miSave.Add_Click({ Send-EditorCommand "save_game" @{} })
$miHeal = New-Object System.Windows.Forms.ToolStripMenuItem("Curar equipo")
$miHeal.Add_Click({ Send-EditorCommand "heal_party" @{} })
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem("Salir")
$miExit.Add_Click({ $form.Close() })
[void]$fileMenu.DropDownItems.Add($miRefresh)
[void]$fileMenu.DropDownItems.Add($miSave)
[void]$fileMenu.DropDownItems.Add($miHeal)
[void]$fileMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$fileMenu.DropDownItems.Add($miExit)

$miUndo = New-Object System.Windows.Forms.ToolStripMenuItem("Deshacer")
$miUndo.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Z
$miUndo.Add_Click({ Invoke-HistoryShortcut "undo" })
$miRedo = New-Object System.Windows.Forms.ToolStripMenuItem("Rehacer")
$miRedo.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Y
$miRedo.Add_Click({ Invoke-HistoryShortcut "redo" })
$miHistory = New-Object System.Windows.Forms.ToolStripMenuItem("Historial de acciones")
$miHistory.Add_Click({ Show-HistoryWindow })
[void]$editMenu.DropDownItems.Add($miUndo)
[void]$editMenu.DropDownItems.Add($miRedo)
[void]$editMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$editMenu.DropDownItems.Add($miHistory)

$miTrainer = New-Object System.Windows.Forms.ToolStripMenuItem("Datos del entrenador")
$miTrainer.Add_Click({ Show-TrainerInfoWindow })
$miItems = New-Object System.Windows.Forms.ToolStripMenuItem("Objetos")
$miItems.Add_Click({ Show-InventoryEditor })
$miPokedex = New-Object System.Windows.Forms.ToolStripMenuItem("Pokedex")
$miPokedex.Add_Click({ Show-PokedexEditor })
$miAchievements = New-Object System.Windows.Forms.ToolStripMenuItem("Logros")
$miAchievements.Add_Click({ Show-AchievementsEditor })
$miSwitches = New-Object System.Windows.Forms.ToolStripMenuItem("Switches / variables")
$miSwitches.Add_Click({ Show-SwitchesWindow })
$miRaw = New-Object System.Windows.Forms.ToolStripMenuItem("Datos de bloque")
$miRaw.Add_Click({ Show-RawDataWindow })
[void]$toolsMenu.DropDownItems.Add($miTrainer)
[void]$toolsMenu.DropDownItems.Add($miItems)
[void]$toolsMenu.DropDownItems.Add($miPokedex)
[void]$toolsMenu.DropDownItems.Add($miAchievements)
[void]$toolsMenu.DropDownItems.Add($miSwitches)
[void]$toolsMenu.DropDownItems.Add($miRaw)

$miStatic = New-Object System.Windows.Forms.ToolStripMenuItem("Carga estatica")
$miStatic.Checked = $true
$miStatic.Enabled = $false
[void]$optionsMenu.DropDownItems.Add($miStatic)
[void]$menuStrip.Items.Add($fileMenu)
[void]$menuStrip.Items.Add($editMenu)
[void]$menuStrip.Items.Add($toolsMenu)
[void]$menuStrip.Items.Add($optionsMenu)
$top.Controls.Add($menuStrip)
$menuStrip.BringToFront()

$nav = New-Object System.Windows.Forms.FlowLayoutPanel
$nav.Dock = [System.Windows.Forms.DockStyle]::Fill
$nav.Height = 44
$nav.Padding = New-Object System.Windows.Forms.Padding(12, 2, 12, 2)
$nav.BackColor = [System.Drawing.Color]::FromArgb(235, 239, 244)
$nav.WrapContents = $false
$nav.Visible = $false
$root.Controls.Add($nav, 0, 1)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$tabs.Multiline = $false
$tabs.Appearance = [System.Windows.Forms.TabAppearance]::Buttons
$tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
$tabs.ItemSize = New-Object System.Drawing.Size(0, 1)
$root.Controls.Add($tabs, 0, 2)

$trainerTab = New-Object System.Windows.Forms.TabPage
$trainerTab.Text = "Entrenador"
$trainerTab.AutoScroll = $true
$tabs.TabPages.Add($trainerTab)

$partyTab = New-Object System.Windows.Forms.TabPage
$partyTab.Text = "Equipo"
$partyTab.AutoScroll = $true
$tabs.TabPages.Add($partyTab)

$pcTab = New-Object System.Windows.Forms.TabPage
$pcTab.Text = "PC cajas"
$pcTab.AutoScroll = $true
$tabs.TabPages.Add($pcTab)

$pokemonTab = New-Object System.Windows.Forms.TabPage
$pokemonTab.Text = "Editor Pokemon"
$pokemonTab.AutoScroll = $true
$pokemonTab.AutoScrollMinSize = New-Object System.Drawing.Size(1000, 1120)
$tabs.TabPages.Add($pokemonTab)

$bagTab = New-Object System.Windows.Forms.TabPage
$bagTab.Text = "Objetos"
$bagTab.AutoScroll = $true
$tabs.TabPages.Add($bagTab)

$batchTab = New-Object System.Windows.Forms.TabPage
$batchTab.Text = "Lote"
$batchTab.AutoScroll = $true
$tabs.TabPages.Add($batchTab)

$worldTab = New-Object System.Windows.Forms.TabPage
$worldTab.Text = "Switches y variables"
$worldTab.AutoScroll = $true
$tabs.TabPages.Add($worldTab)

$rawTab = New-Object System.Windows.Forms.TabPage
$rawTab.Text = "Raw"
$tabs.TabPages.Add($rawTab)

$tabs.Add_SelectedIndexChanged({
  if ($null -eq $script:State) { return }
  if ($tabs.SelectedTab -eq $bagTab) {
    Refresh-BagTab
  } elseif ($tabs.SelectedTab -eq $rawTab) {
    Refresh-RawTab
  }
}.GetNewClosure())

[void]$nav.Controls.Add((New-NavButton "Entrenador" $trainerTab "Edita datos generales del jugador, dinero, ID, Pokedex, Nuzlocke y medallas."))
[void]$nav.Controls.Add((New-NavButton "Equipo" $partyTab "Muestra los 6 Pokemon del equipo con icono y permite abrirlos en el editor."))
[void]$nav.Controls.Add((New-NavButton "PC cajas" $pcTab "Muestra una caja completa del PC, con huecos vacios, iconos, clonado, borrado y creacion."))
[void]$nav.Controls.Add((New-NavButton "Editor Pokemon" $pokemonTab "Edita todos los datos del Pokemon seleccionado: stats, movimientos, OT, captura, cintas y mas."))
[void]$nav.Controls.Add((New-NavButton "Objetos" $bagTab "Consulta todos los objetos del juego y cambia cantidades de la mochila."))
[void]$nav.Controls.Add((New-NavButton "Lote" $batchTab "Aplica cambios masivos al equipo, caja actual, todo el PC o equipo + PC."))
[void]$nav.Controls.Add((New-NavButton "Switches" $worldTab "Edita switches y variables internas del juego. Usalo con cuidado."))
[void]$nav.Controls.Add((New-NavButton "Raw" $rawTab "Muestra el JSON vivo exportado por el juego para diagnostico."))
$top.BringToFront()
$nav.BringToFront()

# Trainer tab
$trainerTab.Controls.Add((New-Label "Nombre" 24 26))
$script:TrainerName = New-TextBox 150 26 220
$trainerTab.Controls.Add($script:TrainerName)
$trainerTab.Controls.Add((New-Label "Dinero" 24 62))
$script:TrainerMoney = New-Number 150 62 0 99999999
$trainerTab.Controls.Add($script:TrainerMoney)
$trainerTab.Controls.Add((New-Label "ID completo" 24 98))
$script:TrainerId = New-Number 150 98 0 2147483647 160
$trainerTab.Controls.Add($script:TrainerId)
$trainerTab.Controls.Add((New-Label "Tipo entrenador" 24 134))
$script:TrainerType = New-Number 150 134 0 9999
$trainerTab.Controls.Add($script:TrainerType)
$trainerTab.Controls.Add((New-Label "Outfit" 24 170))
$script:TrainerOutfit = New-Number 150 170 0 9999
$trainerTab.Controls.Add($script:TrainerOutfit)
$trainerTab.Controls.Add((New-Label "Idioma" 24 206))
$script:TrainerLanguage = New-Number 150 206 0 9999
$trainerTab.Controls.Add($script:TrainerLanguage)

$script:TrainerPokedex = New-Object System.Windows.Forms.CheckBox
$script:TrainerPokedex.Text = "Pokedex obtenida"
$script:TrainerPokedex.Location = New-Object System.Drawing.Point(420, 28)
$script:TrainerPokedex.Size = New-Object System.Drawing.Size(190, 24)
$trainerTab.Controls.Add($script:TrainerPokedex)
$script:TrainerPokegear = New-Object System.Windows.Forms.CheckBox
$script:TrainerPokegear.Text = "Pokegear obtenido"
$script:TrainerPokegear.Location = New-Object System.Drawing.Point(420, 62)
$script:TrainerPokegear.Size = New-Object System.Drawing.Size(190, 24)
$trainerTab.Controls.Add($script:TrainerPokegear)
$script:TrainerNuzlocke = New-Object System.Windows.Forms.CheckBox
$script:TrainerNuzlocke.Text = "Nuzlocke activo"
$script:TrainerNuzlocke.Location = New-Object System.Drawing.Point(420, 96)
$script:TrainerNuzlocke.Size = New-Object System.Drawing.Size(190, 24)
$trainerTab.Controls.Add($script:TrainerNuzlocke)

$trainerTab.Controls.Add((New-Label "Medallas" 650 26))
$script:Badges = New-Object System.Windows.Forms.CheckedListBox
$script:Badges.Location = New-Object System.Drawing.Point(650, 56)
$script:Badges.Size = New-Object System.Drawing.Size(220, 230)
$trainerTab.Controls.Add($script:Badges)

$script:TrainerSummary = New-Object System.Windows.Forms.Label
$script:TrainerSummary.Location = New-Object System.Drawing.Point(24, 270)
$script:TrainerSummary.Size = New-Object System.Drawing.Size(580, 40)
$trainerTab.Controls.Add($script:TrainerSummary)

$applyTrainer = New-Object System.Windows.Forms.Button
$applyTrainer.Text = "Aplicar entrenador"
$applyTrainer.Location = New-Object System.Drawing.Point(24, 330)
$applyTrainer.Size = New-Object System.Drawing.Size(160, 34)
$applyTrainer.Add_Click({
  $badges = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $script:Badges.Items.Count; $i++) {
    if ($script:Badges.GetItemChecked($i)) { $badges.Add([string]$i) }
  }
  Send-EditorCommand "trainer_set" @{
    name = $script:TrainerName.Text
    money = [int]$script:TrainerMoney.Value
    id = [int]$script:TrainerId.Value
    trainertype = [int]$script:TrainerType.Value
    outfit = [int]$script:TrainerOutfit.Value
    language = [int]$script:TrainerLanguage.Value
    pokedex = $script:TrainerPokedex.Checked
    pokegear = $script:TrainerPokegear.Checked
    nuzlocke = $script:TrainerNuzlocke.Checked
    badges = ($badges -join ",")
  }
})
Set-Tip $applyTrainer "Aplica al juego los datos editados del entrenador."
$trainerTab.Controls.Add($applyTrainer)

$trainerTab.Controls.Add((New-Label "Pokedex especie" 24 390 120))
$script:PokedexSpecies = New-Number 150 390 1 9999
$trainerTab.Controls.Add($script:PokedexSpecies)
$setSeen = New-Object System.Windows.Forms.Button
$setSeen.Text = "Marcar vista"
$setSeen.Location = New-Object System.Drawing.Point(280, 386)
$setSeen.Size = New-Object System.Drawing.Size(120, 32)
$setSeen.Add_Click({ Send-EditorCommand "pokedex_set" @{ species = [int]$script:PokedexSpecies.Value; seen = $true; owned = $false } })
Set-Tip $setSeen "Marca esa especie como vista en la Pokedex."
$trainerTab.Controls.Add($setSeen)
$setOwned = New-Object System.Windows.Forms.Button
$setOwned.Text = "Marcar capturada"
$setOwned.Location = New-Object System.Drawing.Point(410, 386)
$setOwned.Size = New-Object System.Drawing.Size(140, 32)
$setOwned.Add_Click({ Send-EditorCommand "pokedex_set" @{ species = [int]$script:PokedexSpecies.Value; seen = $true; owned = $true } })
Set-Tip $setOwned "Marca esa especie como capturada en la Pokedex."
$trainerTab.Controls.Add($setOwned)
$completeSeen = New-Object System.Windows.Forms.Button
$completeSeen.Text = "Completar vistas"
$completeSeen.Location = New-Object System.Drawing.Point(24, 434)
$completeSeen.Size = New-Object System.Drawing.Size(140, 32)
$completeSeen.Add_Click({ Send-EditorCommand "pokedex_set" @{ all = $true; seen = $true; owned = $false } })
Set-Tip $completeSeen "Marca todas las especies conocidas como vistas."
$trainerTab.Controls.Add($completeSeen)
$completeOwned = New-Object System.Windows.Forms.Button
$completeOwned.Text = "Completar capturadas"
$completeOwned.Location = New-Object System.Drawing.Point(174, 434)
$completeOwned.Size = New-Object System.Drawing.Size(170, 32)
$completeOwned.Add_Click({ Send-EditorCommand "pokedex_set" @{ all = $true; seen = $true; owned = $true } })
Set-Tip $completeOwned "Marca todas las especies conocidas como capturadas."
$trainerTab.Controls.Add($completeOwned)

# Party tab
$script:PartySlotGrid = New-Object System.Windows.Forms.TableLayoutPanel
$script:PartySlotGrid.Location = New-Object System.Drawing.Point(16, 16)
$script:PartySlotGrid.Size = New-Object System.Drawing.Size(142, 174)
$script:PartySlotGrid.ColumnCount = 2
$script:PartySlotGrid.RowCount = 3
$script:PartySlotGrid.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
$script:PartySlotGrid.BackColor = [System.Drawing.Color]::FromArgb(96, 174, 108)
for ($c = 0; $c -lt 2; $c++) { [void]$script:PartySlotGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 68))) }
for ($r = 0; $r -lt 3; $r++) { [void]$script:PartySlotGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56))) }
$script:PartySlots = @()
for ($i = 0; $i -lt 6; $i++) {
  $slotBox = New-SlotPictureBox
  $script:PartySlots += $slotBox
  $script:PartySlotGrid.Controls.Add($slotBox, ($i % 2), [int][Math]::Floor($i / 2))
}
Set-Tip $script:PartySlotGrid "Equipo actual. Un clic selecciona un hueco y doble clic abre el Pokemon en el editor."
$partyTab.Controls.Add($script:PartySlotGrid)

$script:PartyGrid = New-Object System.Windows.Forms.DataGridView
$script:PartyGrid.Location = New-Object System.Drawing.Point(178, 16)
$script:PartyGrid.Size = New-Object System.Drawing.Size(568, 360)
$script:PartyGrid.ReadOnly = $true
$script:PartyGrid.AllowUserToAddRows = $false
$script:PartyGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$script:PartyGrid.MultiSelect = $false
$script:PartyGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
Set-Tip $script:PartyGrid "Doble clic o usa Editar seleccionado para abrir ese Pokemon en el editor completo."
$script:PartyGrid.Add_CellDoubleClick({
  if ($null -eq $script:PartyGrid.CurrentRow) { return }
  $row = $script:PartyGrid.CurrentRow.DataBoundItem
  Open-PokemonEditor "party" ([int]$row.Index) -1 -1
})
$partyTab.Controls.Add($script:PartyGrid)

$editParty = New-Object System.Windows.Forms.Button
$editParty.Text = "Editar seleccionado"
$editParty.Location = New-Object System.Drawing.Point(770, 32)
$editParty.Size = New-Object System.Drawing.Size(160, 34)
$editParty.Add_Click({
  $tag = $script:SelectedSlotTag
  if ($null -ne $tag -and $tag.Loc -eq "party" -and !$tag.Empty) {
    Open-PokemonEditor "party" ([int]$tag.Index) -1 -1
    return
  }
  if ($null -eq $script:PartyGrid.CurrentRow) { return }
  $row = $script:PartyGrid.CurrentRow.DataBoundItem
  Open-PokemonEditor "party" ([int]$row.Index) -1 -1
})
Set-Tip $editParty "Abre el Pokemon marcado del equipo en la pestana Editor Pokemon."
$partyTab.Controls.Add($editParty)

$healParty2 = New-Object System.Windows.Forms.Button
$healParty2.Text = "Curar equipo"
$healParty2.Location = New-Object System.Drawing.Point(770, 78)
$healParty2.Size = New-Object System.Drawing.Size(160, 34)
$healParty2.Add_Click({ Send-EditorCommand "heal_party" @{} })
Set-Tip $healParty2 "Restaura PS, PP y estados de todos los Pokemon del equipo."
$partyTab.Controls.Add($healParty2)

$partyTab.Controls.Add((New-Label "Especie" 770 130 70))
$script:PartyCreateSpecies = New-Number 840 130 1 9999 80
Set-Tip $script:PartyCreateSpecies "ID de especie del Pokemon que quieres crear en el equipo."
$partyTab.Controls.Add($script:PartyCreateSpecies)
$script:PartyCreatePreview = New-SlotPictureBox
$script:PartyCreatePreview.Location = New-Object System.Drawing.Point(940, 126)
$script:PartyCreatePreview.Size = New-Object System.Drawing.Size(68, 56)
$script:PartyCreatePreview.Tag = $null
Set-Tip $script:PartyCreatePreview "Vista previa del Pokemon que vas a crear en el equipo."
$script:PartyCreateSpecies.Add_ValueChanged({ Update-SpeciesPreview $script:PartyCreatePreview $script:PartyCreateSpecies })
$partyTab.Controls.Add($script:PartyCreatePreview)
$partyTab.Controls.Add((New-Label "Nivel" 770 166 70))
$script:PartyCreateLevel = New-Number 840 166 1 999 80
Set-Tip $script:PartyCreateLevel "Nivel inicial del Pokemon creado."
$partyTab.Controls.Add($script:PartyCreateLevel)
$createParty = New-Object System.Windows.Forms.Button
$createParty.Text = "Crear en hueco libre"
$createParty.Location = New-Object System.Drawing.Point(770, 204)
$createParty.Size = New-Object System.Drawing.Size(160, 34)
$createParty.Add_Click({
  Send-EditorCommand "pokemon_create" @{ species = [int]$script:PartyCreateSpecies.Value; level = [int]$script:PartyCreateLevel.Value; destLoc = "party"; destIndex = -1; replace = $false }
})
Set-Tip $createParty "Crea un Pokemon nuevo en el primer hueco libre del equipo."
$partyTab.Controls.Add($createParty)

# PC tab
$pcTab.Controls.Add((New-Label "Caja" 16 18 50))
$script:PCBox = New-Object System.Windows.Forms.ComboBox
$script:PCBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:PCBox.Location = New-Object System.Drawing.Point(70, 18)
$script:PCBox.Size = New-Object System.Drawing.Size(280, 24)
$script:PCBox.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { $script:SelectedSlotTag = $null; Refresh-PCTab } })
$pcTab.Controls.Add($script:PCBox)
$pcTab.Controls.Add((New-Label "Nombre" 370 18 70))
$script:PCBoxName = New-TextBox 440 18 220
$pcTab.Controls.Add($script:PCBoxName)
$pcRename = New-Object System.Windows.Forms.Button
$pcRename.Text = "Aplicar caja"
$pcRename.Location = New-Object System.Drawing.Point(675, 14)
$pcRename.Size = New-Object System.Drawing.Size(120, 30)
$pcRename.Add_Click({
  $boxIndex = [Math]::Max(0, $script:PCBox.SelectedIndex)
  Send-EditorCommand "box_set" @{ box = $boxIndex; name = $script:PCBoxName.Text; makeCurrent = $true }
})
Set-Tip $pcRename "Renombra la caja seleccionada y la deja como caja actual del PC."
$pcTab.Controls.Add($pcRename)

$script:PCSlotGrid = New-Object System.Windows.Forms.TableLayoutPanel
$script:PCSlotGrid.Location = New-Object System.Drawing.Point(16, 60)
$script:PCSlotGrid.Size = New-Object System.Drawing.Size(418, 288)
$script:PCSlotGrid.ColumnCount = 6
$script:PCSlotGrid.RowCount = 5
$script:PCSlotGrid.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
$script:PCSlotGrid.BackColor = [System.Drawing.Color]::FromArgb(96, 174, 108)
for ($c = 0; $c -lt 6; $c++) { [void]$script:PCSlotGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 68))) }
for ($r = 0; $r -lt 5; $r++) { [void]$script:PCSlotGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56))) }
$script:PCSlots = @()
for ($slot = 0; $slot -lt 30; $slot++) {
  $slotBox = New-SlotPictureBox
  $script:PCSlots += $slotBox
  $script:PCSlotGrid.Controls.Add($slotBox, ($slot % 6), [int][Math]::Floor($slot / 6))
}
Set-Tip $script:PCSlotGrid "Caja actual del PC. Un clic selecciona un hueco y doble clic abre el Pokemon en el editor."
$pcTab.Controls.Add($script:PCSlotGrid)

$script:PCGrid = New-Object System.Windows.Forms.DataGridView
$script:PCGrid.Location = New-Object System.Drawing.Point(16, 360)
$script:PCGrid.Size = New-Object System.Drawing.Size(730, 230)
$script:PCGrid.Visible = $false
$script:PCGrid.ReadOnly = $true
$script:PCGrid.AllowUserToAddRows = $false
$script:PCGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$script:PCGrid.MultiSelect = $false
$script:PCGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
Set-Tip $script:PCGrid "Doble clic o usa Editar seleccionado para abrir ese Pokemon de la caja."
$script:PCGrid.Add_CellDoubleClick({
  if ($null -eq $script:PCGrid.CurrentRow) { return }
  $row = $script:PCGrid.CurrentRow.DataBoundItem
  Open-PokemonEditor "box" -1 ([int]$row.Box) ([int]$row.SlotIndex)
})
$pcTab.Controls.Add($script:PCGrid)

$editPC = New-Object System.Windows.Forms.Button
$editPC.Text = "Editar seleccionado"
$editPC.Location = New-Object System.Drawing.Point(770, 72)
$editPC.Size = New-Object System.Drawing.Size(160, 34)
$editPC.Add_Click({
  $tag = $script:SelectedSlotTag
  if ($null -ne $tag -and $tag.Loc -eq "box" -and !$tag.Empty) {
    Open-PokemonEditor "box" -1 ([int]$tag.Box) ([int]$tag.Slot)
    return
  }
  if ($null -eq $script:PCGrid.CurrentRow) { return }
  $row = $script:PCGrid.CurrentRow.DataBoundItem
  Open-PokemonEditor "box" -1 ([int]$row.Box) ([int]$row.SlotIndex)
})
Set-Tip $editPC "Abre el Pokemon seleccionado de esta caja en el editor completo."
$pcTab.Controls.Add($editPC)

$clonePC = New-Object System.Windows.Forms.Button
$clonePC.Text = "Clonar a hueco libre"
$clonePC.Location = New-Object System.Drawing.Point(770, 118)
$clonePC.Size = New-Object System.Drawing.Size(160, 34)
$clonePC.Add_Click({
  $tag = $script:SelectedSlotTag
  if ($null -ne $tag -and $tag.Loc -eq "box" -and !$tag.Empty) {
    $values = @{ loc = "box"; box = [int]$tag.Box; slot = [int]$tag.Slot; destLoc = "box"; destBox = [int]$tag.Box; destSlot = -1; replace = $false }
    Send-EditorCommand "pokemon_clone" $values
    return
  }
  if ($null -eq $script:PCGrid.CurrentRow) { return }
  $row = $script:PCGrid.CurrentRow.DataBoundItem
  $values = @{ loc = "box"; box = [int]$row.Box; slot = [int]$row.SlotIndex; destLoc = "box"; destBox = [int]$row.Box; destSlot = -1; replace = $false }
  Send-EditorCommand "pokemon_clone" $values
})
Set-Tip $clonePC "Copia el Pokemon seleccionado al primer hueco libre de la misma caja."
$pcTab.Controls.Add($clonePC)

$deletePC = New-Object System.Windows.Forms.Button
$deletePC.Text = "Borrar seleccionado"
$deletePC.Location = New-Object System.Drawing.Point(770, 164)
$deletePC.Size = New-Object System.Drawing.Size(160, 34)
$deletePC.Add_Click({
  $tag = $script:SelectedSlotTag
  if ($null -ne $tag -and $tag.Loc -eq "box" -and !$tag.Empty) {
    $result = [System.Windows.Forms.MessageBox]::Show("Esto borrara el Pokemon seleccionado de la caja.", "Borrar Pokemon", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
      Send-EditorCommand "pokemon_delete" @{ loc = "box"; box = [int]$tag.Box; slot = [int]$tag.Slot }
    }
    return
  }
  if ($null -eq $script:PCGrid.CurrentRow) { return }
  $row = $script:PCGrid.CurrentRow.DataBoundItem
  $result = [System.Windows.Forms.MessageBox]::Show("Esto borrara el Pokemon seleccionado de la caja.", "Borrar Pokemon", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
  if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    Send-EditorCommand "pokemon_delete" @{ loc = "box"; box = [int]$row.Box; slot = [int]$row.SlotIndex }
  }
})
Set-Tip $deletePC "Elimina el Pokemon seleccionado de la caja actual."
$pcTab.Controls.Add($deletePC)

$pcTab.Controls.Add((New-Label "Crear especie" 770 225 95))
$script:PCCreateSpecies = New-Number 870 225 1 9999 70
Set-Tip $script:PCCreateSpecies "ID de especie del Pokemon que quieres crear en esta caja."
$pcTab.Controls.Add($script:PCCreateSpecies)
$script:PCCreatePreview = New-SlotPictureBox
$script:PCCreatePreview.Location = New-Object System.Drawing.Point(950, 218)
$script:PCCreatePreview.Size = New-Object System.Drawing.Size(68, 56)
$script:PCCreatePreview.Tag = $null
Set-Tip $script:PCCreatePreview "Vista previa del Pokemon que vas a crear en la caja actual."
$script:PCCreateSpecies.Add_ValueChanged({ Update-SpeciesPreview $script:PCCreatePreview $script:PCCreateSpecies })
$pcTab.Controls.Add($script:PCCreatePreview)
$pcTab.Controls.Add((New-Label "Nivel" 770 260 60))
$script:PCCreateLevel = New-Number 870 260 1 999 70
Set-Tip $script:PCCreateLevel "Nivel inicial del Pokemon creado."
$pcTab.Controls.Add($script:PCCreateLevel)
$createPC = New-Object System.Windows.Forms.Button
$createPC.Text = "Crear en caja"
$createPC.Location = New-Object System.Drawing.Point(770, 298)
$createPC.Size = New-Object System.Drawing.Size(160, 34)
$createPC.Add_Click({
  $boxIndex = [Math]::Max(0, $script:PCBox.SelectedIndex)
  Send-EditorCommand "pokemon_create" @{ species = [int]$script:PCCreateSpecies.Value; level = [int]$script:PCCreateLevel.Value; destLoc = "box"; destBox = $boxIndex; destSlot = -1; replace = $false }
})
Set-Tip $createPC "Crea un Pokemon nuevo en el primer hueco libre de la caja mostrada."
$pcTab.Controls.Add($createPC)

# Pokemon tab
$pokemonTab.Controls.Add((New-Label "Origen" 16 18 70))
$script:PokemonSource = New-Object System.Windows.Forms.ComboBox
$script:PokemonSource.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:PokemonSource.Items.AddRange(@("Equipo", "PC"))
$script:PokemonSource.SelectedIndex = 0
$script:PokemonSource.Location = New-Object System.Drawing.Point(86, 18)
$script:PokemonSource.Size = New-Object System.Drawing.Size(120, 24)
$script:PokemonSource.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { Refresh-PokemonList } })
$pokemonTab.Controls.Add($script:PokemonSource)
$pokemonTab.Controls.Add((New-Label "Caja" 220 18 50))
$script:PokemonBox = New-Object System.Windows.Forms.ComboBox
$script:PokemonBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:PokemonBox.Location = New-Object System.Drawing.Point(270, 18)
$script:PokemonBox.Size = New-Object System.Drawing.Size(190, 24)
$script:PokemonBox.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { Refresh-PokemonList } })
$pokemonTab.Controls.Add($script:PokemonBox)

$script:PokemonList = New-Object System.Windows.Forms.ListBox
$script:PokemonList.Location = New-Object System.Drawing.Point(16, 54)
$script:PokemonList.Size = New-Object System.Drawing.Size(440, 540)
$script:PokemonList.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { Select-PokemonByIndex $script:PokemonList.SelectedIndex } })
$pokemonTab.Controls.Add($script:PokemonList)

$x0 = 500
$pokemonTab.Controls.Add((New-Label "Ubicacion" $x0 22 100))
$script:PokemonLoc = New-Object System.Windows.Forms.Label
$script:PokemonLoc.Location = New-Object System.Drawing.Point(($x0 + 120), 22)
$script:PokemonLoc.Size = New-Object System.Drawing.Size(360, 24)
$pokemonTab.Controls.Add($script:PokemonLoc)
$script:PokePreview = New-SlotPictureBox
$script:PokePreview.Location = New-Object System.Drawing.Point(990, 18)
$script:PokePreview.Size = New-Object System.Drawing.Size(68, 56)
$script:PokePreview.Tag = $null
Set-Tip $script:PokePreview "Icono del Pokemon seleccionado."
$pokemonTab.Controls.Add($script:PokePreview)
$pokemonTab.Controls.Add((New-Label "Especie ID" $x0 58 100))
$script:PokeSpecies = New-Number ($x0 + 120) 58 1 9999
$script:PokeSpecies.Add_ValueChanged({ if (!$script:LoadingUi) { Update-SpeciesPreview $script:PokePreview $script:PokeSpecies } })
$pokemonTab.Controls.Add($script:PokeSpecies)
$script:PokeSpeciesName = New-Label "" ($x0 + 240) 58 130
$pokemonTab.Controls.Add($script:PokeSpeciesName)
$pokemonTab.Controls.Add((New-Label "Apodo" $x0 94 100))
$script:PokeNick = New-TextBox ($x0 + 120) 94 210
$pokemonTab.Controls.Add($script:PokeNick)
$pokemonTab.Controls.Add((New-Label "Nivel" $x0 130 100))
$script:PokeLevel = New-Number ($x0 + 120) 130 1 999
$pokemonTab.Controls.Add($script:PokeLevel)
$pokemonTab.Controls.Add((New-Label "Experiencia" $x0 166 100))
$script:PokeExp = New-Number ($x0 + 120) 166 0 99999999 140
$pokemonTab.Controls.Add($script:PokeExp)
$pokemonTab.Controls.Add((New-Label "PS" $x0 202 100))
$script:PokeHp = New-Number ($x0 + 120) 202 0 9999
$pokemonTab.Controls.Add($script:PokeHp)
$script:PokeTotalHp = New-Label "" ($x0 + 240) 202 80
$pokemonTab.Controls.Add($script:PokeTotalHp)
$pokemonTab.Controls.Add((New-Label "Estado ID" $x0 238 100))
$script:PokeStatus = New-Number ($x0 + 120) 238 0 9
$pokemonTab.Controls.Add($script:PokeStatus)
$pokemonTab.Controls.Add((New-Label "Contador" ($x0 + 240) 238 70))
$script:PokeStatusCount = New-Number ($x0 + 315) 238 0 9999 70
$pokemonTab.Controls.Add($script:PokeStatusCount)
$pokemonTab.Controls.Add((New-Label "Felicidad" $x0 274 100))
$script:PokeHappiness = New-Number ($x0 + 120) 274 0 255
$pokemonTab.Controls.Add($script:PokeHappiness)
$pokemonTab.Controls.Add((New-Label "Objeto ID" $x0 310 100))
$script:PokeItem = New-Number ($x0 + 120) 310 0 9999
$pokemonTab.Controls.Add($script:PokeItem)
$script:PokeItemName = New-Label "" ($x0 + 240) 310 130
$pokemonTab.Controls.Add($script:PokeItemName)
$pokemonTab.Controls.Add((New-Label "Naturaleza flag" $x0 346 115))
$script:PokeNatureFlag = New-Number ($x0 + 120) 346 -1 24
$pokemonTab.Controls.Add($script:PokeNatureFlag)
$script:PokeNatureName = New-Label "" ($x0 + 240) 346 130
$pokemonTab.Controls.Add($script:PokeNatureName)
$pokemonTab.Controls.Add((New-Label "Habilidad flag" $x0 382 115))
$script:PokeAbilityFlag = New-Number ($x0 + 120) 382 -1 2
$pokemonTab.Controls.Add($script:PokeAbilityFlag)
$script:PokeAbilityName = New-Label "" ($x0 + 240) 382 130
$pokemonTab.Controls.Add($script:PokeAbilityName)
$pokemonTab.Controls.Add((New-Label "Genero flag" $x0 418 100))
$script:PokeGenderFlag = New-Number ($x0 + 120) 418 -1 1
$pokemonTab.Controls.Add($script:PokeGenderFlag)
$pokemonTab.Controls.Add((New-Label "Pasos huevo" $x0 454 100))
$script:PokeEggSteps = New-Number ($x0 + 120) 454 0 999999
$pokemonTab.Controls.Add($script:PokeEggSteps)
$pokemonTab.Controls.Add((New-Label "Forma" ($x0 + 240) 454 55))
$script:PokeForm = New-Number ($x0 + 295) 454 0 999 70
$pokemonTab.Controls.Add($script:PokeForm)
$pokemonTab.Controls.Add((New-Label "Pokerus" $x0 490 100))
$script:PokePokerus = New-Number ($x0 + 120) 490 0 255
$pokemonTab.Controls.Add($script:PokePokerus)
$script:PokeShiny = New-Object System.Windows.Forms.CheckBox
$script:PokeShiny.Text = "Shiny"
$script:PokeShiny.Location = New-Object System.Drawing.Point(($x0 + 250), 490)
$script:PokeShiny.Size = New-Object System.Drawing.Size(120, 24)
$pokemonTab.Controls.Add($script:PokeShiny)

$stats = @("PS", "Atk", "Def", "At.Esp", "Def.Esp", "Vel")
$script:IvNums = @()
$script:EvNums = @()
$pokemonTab.Controls.Add((New-Label "IV" 945 84 40))
$pokemonTab.Controls.Add((New-Label "EV" 1010 84 40))
for ($i = 0; $i -lt 6; $i++) {
  $y = 116 + ($i * 32)
  $pokemonTab.Controls.Add((New-Label $stats[$i] 890 $y 55))
  $iv = New-Number 945 $y 0 31 50
  $ev = New-Number 1010 $y 0 252 55
  $script:IvNums += $iv
  $script:EvNums += $ev
  $pokemonTab.Controls.Add($iv)
  $pokemonTab.Controls.Add($ev)
}

$script:MoveIds = @()
$script:MovePps = @()
$script:MovePpUps = @()
$script:MoveNames = @()
$pokemonTab.Controls.Add((New-Label "Movimientos" 870 320 160))
for ($i = 0; $i -lt 4; $i++) {
  $y = 354 + ($i * 34)
  $pokemonTab.Controls.Add((New-Label ("Mov {0}" -f ($i + 1)) 870 $y 50))
  $mid = New-Number 920 $y 0 9999 58
  $mpp = New-Number 982 $y 0 99 34
  $mppup = New-Number 1020 $y 0 3 30
  $mname = New-Label "" 1052 $y 1
  $mname.Visible = $false
  $script:MoveIds += $mid
  $script:MovePps += $mpp
  $script:MovePpUps += $mppup
  $script:MoveNames += $mname
  $pokemonTab.Controls.Add($mid)
  $pokemonTab.Controls.Add($mpp)
  $pokemonTab.Controls.Add($mppup)
  $pokemonTab.Controls.Add($mname)
}

$script:PokeMeta = New-Object System.Windows.Forms.Label
$script:PokeMeta.Location = New-Object System.Drawing.Point(520, 530)
$script:PokeMeta.Size = New-Object System.Drawing.Size(540, 36)
$pokemonTab.Controls.Add($script:PokeMeta)

$applyPokemon = New-Object System.Windows.Forms.Button
$applyPokemon.Text = "Aplicar Pokemon"
$applyPokemon.Location = New-Object System.Drawing.Point(520, 574)
$applyPokemon.Size = New-Object System.Drawing.Size(150, 34)
$applyPokemon.Add_Click({
  if ($null -eq $script:SelectedPokemon) { return }
  $values = @{
    loc = $script:SelectedPokemon.loc
    index = [int]$script:SelectedPokemon.index
    box = [int]$script:SelectedPokemon.box
    slot = [int]$script:SelectedPokemon.slot
    species = [int]$script:PokeSpecies.Value
    nickname = $script:PokeNick.Text
    level = [int]$script:PokeLevel.Value
    exp = [int64]$script:PokeExp.Value
    hp = [int]$script:PokeHp.Value
    status = [int]$script:PokeStatus.Value
    statusCount = [int]$script:PokeStatusCount.Value
    happiness = [int]$script:PokeHappiness.Value
    item = [int]$script:PokeItem.Value
    natureflag = [int]$script:PokeNatureFlag.Value
    abilityflag = [int]$script:PokeAbilityFlag.Value
    genderflag = [int]$script:PokeGenderFlag.Value
    eggsteps = [int]$script:PokeEggSteps.Value
    form = [int]$script:PokeForm.Value
    pokerus = [int]$script:PokePokerus.Value
    shiny = $script:PokeShiny.Checked
    ot = $script:PokeOt.Text
    otgender = [int]$script:PokeOtGender.Value
    trainerID = [int64]$script:PokeTrainerId.Value
    personalID = [int64]$script:PokePersonalId.Value
    language = [int]$script:PokeLanguage.Value
    ballused = [int]$script:PokeBallUsed.Value
    obtainMode = [int]$script:PokeObtainMode.Value
    obtainLevel = [int]$script:PokeObtainLevel.Value
    obtainMap = [int]$script:PokeObtainMap.Value
    obtainText = $script:PokeObtainText.Text
    hatchedMap = [int]$script:PokeHatchedMap.Value
    markings = [int]$script:PokeMarkings.Value
    expshare = $script:PokeExpShare.Checked
    cool = [int]$script:PokeCool.Value
    beauty = [int]$script:PokeBeauty.Value
    cute = [int]$script:PokeCute.Value
    smart = [int]$script:PokeSmart.Value
    tough = [int]$script:PokeTough.Value
    sheen = [int]$script:PokeSheen.Value
    timeReceived = [int64]$script:PokeTimeReceived.Value
    timeEggHatched = [int64]$script:PokeTimeEggHatched.Value
    firstmoves = $script:PokeFirstMoves.Text
    ribbons = $script:PokeRibbons.Text
  }
  Add-EditorStatValues $values
  for ($i = 0; $i -lt 4; $i++) {
    $values["move$i"] = [int]$script:MoveIds[$i].Value
    $values["move${i}pp"] = [int]$script:MovePps[$i].Value
    $values["move${i}ppup"] = [int]$script:MovePpUps[$i].Value
  }
  Send-EditorCommand "pokemon_set" $values
})
Set-Tip $applyPokemon "Aplica todos los campos del Editor Pokemon al Pokemon seleccionado."
$pokemonTab.Controls.Add($applyPokemon)

$pokemonTab.Controls.Add((New-Label "OT / captura" 520 630 150))
$pokemonTab.Controls.Add((New-Label "OT" 520 664 80))
$script:PokeOt = New-TextBox 610 664 190
$pokemonTab.Controls.Add($script:PokeOt)
$pokemonTab.Controls.Add((New-Label "Genero OT" 820 664 80))
$script:PokeOtGender = New-Number 910 664 0 3 70
$pokemonTab.Controls.Add($script:PokeOtGender)
$pokemonTab.Controls.Add((New-Label "TID" 520 700 80))
$script:PokeTrainerId = New-Number 610 700 0 4294967295 150
$pokemonTab.Controls.Add($script:PokeTrainerId)
$pokemonTab.Controls.Add((New-Label "PID" 780 700 60))
$script:PokePersonalId = New-Number 840 700 0 4294967295 150
$pokemonTab.Controls.Add($script:PokePersonalId)
$pokemonTab.Controls.Add((New-Label "Idioma" 520 736 80))
$script:PokeLanguage = New-Number 610 736 0 9999 80
$pokemonTab.Controls.Add($script:PokeLanguage)
$pokemonTab.Controls.Add((New-Label "Ball" 710 736 50))
$script:PokeBallUsed = New-Number 760 736 0 9999 80
$pokemonTab.Controls.Add($script:PokeBallUsed)
$pokemonTab.Controls.Add((New-Label "Modo" 860 736 50))
$script:PokeObtainMode = New-Number 910 736 0 9 70
$pokemonTab.Controls.Add($script:PokeObtainMode)
$pokemonTab.Controls.Add((New-Label "Nivel capt." 520 772 85))
$script:PokeObtainLevel = New-Number 610 772 0 999 80
$pokemonTab.Controls.Add($script:PokeObtainLevel)
$pokemonTab.Controls.Add((New-Label "Mapa capt." 710 772 85))
$script:PokeObtainMap = New-Number 800 772 0 99999 90
$pokemonTab.Controls.Add($script:PokeObtainMap)
$pokemonTab.Controls.Add((New-Label "Mapa huevo" 910 772 85))
$script:PokeHatchedMap = New-Number 985 772 0 99999 70
$pokemonTab.Controls.Add($script:PokeHatchedMap)
$pokemonTab.Controls.Add((New-Label "Texto origen" 520 808 90))
$script:PokeObtainText = New-TextBox 610 808 445
$pokemonTab.Controls.Add($script:PokeObtainText)
$pokemonTab.Controls.Add((New-Label "Marcas" 520 844 70))
$script:PokeMarkings = New-Number 590 844 0 15 70
$pokemonTab.Controls.Add($script:PokeMarkings)
$script:PokeExpShare = New-Object System.Windows.Forms.CheckBox
$script:PokeExpShare.Text = "Repartir exp"
$script:PokeExpShare.Location = New-Object System.Drawing.Point(680, 844)
$script:PokeExpShare.Size = New-Object System.Drawing.Size(130, 24)
$pokemonTab.Controls.Add($script:PokeExpShare)
$pokemonTab.Controls.Add((New-Label "Recibido Unix" 820 844 100))
$script:PokeTimeReceived = New-Number 925 844 0 2147483647 130
$pokemonTab.Controls.Add($script:PokeTimeReceived)
$pokemonTab.Controls.Add((New-Label "Huevo Unix" 820 880 100))
$script:PokeTimeEggHatched = New-Number 925 880 0 2147483647 130
$pokemonTab.Controls.Add($script:PokeTimeEggHatched)

$pokemonTab.Controls.Add((New-Label "Concurso" 520 920 100))
$script:PokeCool = New-Number 610 920 0 255 60
$script:PokeBeauty = New-Number 740 920 0 255 60
$script:PokeCute = New-Number 870 920 0 255 60
$script:PokeSmart = New-Number 610 956 0 255 60
$script:PokeTough = New-Number 740 956 0 255 60
$script:PokeSheen = New-Number 870 956 0 255 60
$pokemonTab.Controls.Add((New-Label "Cool" 570 920 40))
$pokemonTab.Controls.Add($script:PokeCool)
$pokemonTab.Controls.Add((New-Label "Beauty" 685 920 55))
$pokemonTab.Controls.Add($script:PokeBeauty)
$pokemonTab.Controls.Add((New-Label "Cute" 830 920 40))
$pokemonTab.Controls.Add($script:PokeCute)
$pokemonTab.Controls.Add((New-Label "Smart" 555 956 55))
$pokemonTab.Controls.Add($script:PokeSmart)
$pokemonTab.Controls.Add((New-Label "Tough" 685 956 55))
$pokemonTab.Controls.Add($script:PokeTough)
$pokemonTab.Controls.Add((New-Label "Sheen" 815 956 55))
$pokemonTab.Controls.Add($script:PokeSheen)
$pokemonTab.Controls.Add((New-Label "Primeros movs" 520 996 95))
$script:PokeFirstMoves = New-TextBox 620 996 210
$pokemonTab.Controls.Add($script:PokeFirstMoves)
$pokemonTab.Controls.Add((New-Label "Cintas IDs" 850 996 75))
$script:PokeRibbons = New-TextBox 930 996 160
$pokemonTab.Controls.Add($script:PokeRibbons)

$pokemonTab.Controls.Add((New-Label "Crear / mover / PC" 16 620 180))
$pokemonTab.Controls.Add((New-Label "Especie" 16 654 60))
$script:CreateSpecies = New-Number 82 654 1 9999 80
$pokemonTab.Controls.Add($script:CreateSpecies)
$script:CreatePreview = New-SlotPictureBox
$script:CreatePreview.Location = New-Object System.Drawing.Point(392, 646)
$script:CreatePreview.Size = New-Object System.Drawing.Size(68, 56)
$script:CreatePreview.Tag = $null
Set-Tip $script:CreatePreview "Vista previa del Pokemon que vas a crear."
$script:CreateSpecies.Add_ValueChanged({ Update-SpeciesPreview $script:CreatePreview $script:CreateSpecies })
$pokemonTab.Controls.Add($script:CreatePreview)
$pokemonTab.Controls.Add((New-Label "Nivel" 172 654 50))
$script:CreateLevel = New-Number 222 654 1 999 70
$pokemonTab.Controls.Add($script:CreateLevel)
$createPokemon = New-Object System.Windows.Forms.Button
$createPokemon.Text = "Crear"
$createPokemon.Location = New-Object System.Drawing.Point(305, 650)
$createPokemon.Size = New-Object System.Drawing.Size(80, 30)
$pokemonTab.Controls.Add($createPokemon)
Set-Tip $createPokemon "Crea un Pokemon con especie/nivel indicados y lo coloca en el destino configurado."

$pokemonTab.Controls.Add((New-Label "Destino" 16 694 60))
$script:DestLoc = New-Object System.Windows.Forms.ComboBox
$script:DestLoc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:DestLoc.Items.AddRange(@("Equipo", "PC"))
$script:DestLoc.SelectedIndex = 1
$script:DestLoc.Location = New-Object System.Drawing.Point(82, 694)
$script:DestLoc.Size = New-Object System.Drawing.Size(95, 24)
$pokemonTab.Controls.Add($script:DestLoc)
$pokemonTab.Controls.Add((New-Label "Equipo slot" 190 694 80))
$script:DestPartyIndex = New-Number 270 694 0 6 55
$pokemonTab.Controls.Add($script:DestPartyIndex)
$pokemonTab.Controls.Add((New-Label "Caja" 16 730 50))
$script:DestBox = New-Number 82 730 1 99 55
$pokemonTab.Controls.Add($script:DestBox)
$pokemonTab.Controls.Add((New-Label "Slot" 150 730 40))
$script:DestSlot = New-Number 190 730 0 99 55
$pokemonTab.Controls.Add($script:DestSlot)
$script:ReplaceSlot = New-Object System.Windows.Forms.CheckBox
$script:ReplaceSlot.Text = "Reemplazar"
$script:ReplaceSlot.Location = New-Object System.Drawing.Point(265, 730)
$script:ReplaceSlot.Size = New-Object System.Drawing.Size(110, 24)
$pokemonTab.Controls.Add($script:ReplaceSlot)
Set-Tip $script:ReplaceSlot "Permite sobrescribir el hueco de destino si ya tiene un Pokemon."

$clonePokemon = New-Object System.Windows.Forms.Button
$clonePokemon.Text = "Clonar sel."
$clonePokemon.Location = New-Object System.Drawing.Point(16, 770)
$clonePokemon.Size = New-Object System.Drawing.Size(100, 30)
$pokemonTab.Controls.Add($clonePokemon)
Set-Tip $clonePokemon "Copia el Pokemon seleccionado al destino configurado."
$movePokemon = New-Object System.Windows.Forms.Button
$movePokemon.Text = "Mover sel."
$movePokemon.Location = New-Object System.Drawing.Point(126, 770)
$movePokemon.Size = New-Object System.Drawing.Size(100, 30)
$pokemonTab.Controls.Add($movePokemon)
Set-Tip $movePokemon "Mueve el Pokemon seleccionado al destino configurado."
$deletePokemon = New-Object System.Windows.Forms.Button
$deletePokemon.Text = "Borrar sel."
$deletePokemon.Location = New-Object System.Drawing.Point(236, 770)
$deletePokemon.Size = New-Object System.Drawing.Size(100, 30)
$pokemonTab.Controls.Add($deletePokemon)
Set-Tip $deletePokemon "Borra el Pokemon seleccionado de su ubicacion actual."

$pokemonTab.Controls.Add((New-Label "Nombre caja" 16 820 90))
$script:BoxName = New-TextBox 110 820 190
$pokemonTab.Controls.Add($script:BoxName)
$setBox = New-Object System.Windows.Forms.Button
$setBox.Text = "Aplicar caja"
$setBox.Location = New-Object System.Drawing.Point(315, 816)
$setBox.Size = New-Object System.Drawing.Size(110, 30)
$pokemonTab.Controls.Add($setBox)
Set-Tip $setBox "Renombra la caja actualmente seleccionada."

$createPokemon.Add_Click({
  $values = Add-DestinationValues @{
    species = [int]$script:CreateSpecies.Value
    level = [int]$script:CreateLevel.Value
  }
  Send-EditorCommand "pokemon_create" $values
})

$clonePokemon.Add_Click({
  $values = Add-SelectedPokemonValues @{}
  if ($null -eq $values) { return }
  $values = Add-DestinationValues $values
  Send-EditorCommand "pokemon_clone" $values
})

$movePokemon.Add_Click({
  $values = Add-SelectedPokemonValues @{}
  if ($null -eq $values) { return }
  $values = Add-DestinationValues $values
  Send-EditorCommand "pokemon_move" $values
})

$deletePokemon.Add_Click({
  $values = Add-SelectedPokemonValues @{}
  if ($null -eq $values) { return }
  $result = [System.Windows.Forms.MessageBox]::Show("Esto borrara el Pokemon seleccionado de la partida actual.", "Borrar Pokemon", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
  if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    Send-EditorCommand "pokemon_delete" $values
  }
})

$setBox.Add_Click({
  $boxIndex = [Math]::Max(0, $script:PokemonBox.SelectedIndex)
  Send-EditorCommand "box_set" @{ box = $boxIndex; name = $script:BoxName.Text; makeCurrent = $true }
})

function Show-HexSection {
  param([string]$Name)
  foreach ($key in $script:HexSections.Keys) {
    $script:HexSections[$key].Visible = ($key -eq $Name)
  }
  foreach ($key in $script:HexButtons.Keys) {
    $script:HexButtons[$key].BackColor = $(if ($key -eq $Name) { [System.Drawing.Color]::FromArgb(226, 226, 226) } else { [System.Drawing.SystemColors]::Control })
    $script:HexButtons[$key].FlatAppearance.BorderColor = $(if ($key -eq $Name) { [System.Drawing.Color]::FromArgb(120, 120, 120) } else { [System.Drawing.Color]::FromArgb(160, 160, 160) })
  }
}

function New-HexSectionPanel {
  param([string]$Name)
  $panel = New-Object System.Windows.Forms.Panel
  $panel.Location = New-Object System.Drawing.Point(98, 0)
  $panel.Size = New-Object System.Drawing.Size(306, 388)
  $panel.BackColor = [System.Drawing.SystemColors]::Control
  $panel.Visible = $false
  $script:HexSections[$Name] = $panel
  $pokemonTab.Controls.Add($panel)
  return $panel
}

function New-HexSectionButton {
  param([string]$Text, [string]$Name, [int]$Y)
  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Location = New-Object System.Drawing.Point(0, $Y)
  $button.Size = New-Object System.Drawing.Size(94, 40)
  $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
  $button.Add_Click({ Show-HexSection $Name }.GetNewClosure())
  $script:HexButtons[$Name] = $button
  return $button
}

function New-HexButton {
  param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [scriptblock]$Click, [string]$Tip = "")
  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Text
  $button.Location = New-Object System.Drawing.Point($X, $Y)
  $button.Size = New-Object System.Drawing.Size($W, $H)
  if ($null -ne $Click) { $button.Add_Click($Click) }
  if ($Tip -ne "") { Set-Tip $button $Tip }
  $Parent.Controls.Add($button)
  return $button
}

function Submit-HexPokemonSet {
  if ($null -eq $script:SelectedPokemon) { return }
  $values = @{
    loc = $script:SelectedPokemon.loc
    index = [int]$script:SelectedPokemon.index
    box = [int]$script:SelectedPokemon.box
    slot = [int]$script:SelectedPokemon.slot
    species = [int]$script:PokeSpecies.Value
    nickname = $script:PokeNick.Text
    level = [int]$script:PokeLevel.Value
    exp = [int64]$script:PokeExp.Value
    hp = [int]$script:PokeHp.Value
    status = [int]$script:PokeStatus.Value
    statusCount = [int]$script:PokeStatusCount.Value
    happiness = [int]$script:PokeHappiness.Value
    item = [int]$script:PokeItem.Value
    natureflag = [int]$script:PokeNatureFlag.Value
    abilityflag = [int]$script:PokeAbilityFlag.Value
    genderflag = [int]$script:PokeGenderFlag.Value
    eggsteps = [int]$script:PokeEggSteps.Value
    form = [int]$script:PokeForm.Value
    pokerus = [int]$script:PokePokerus.Value
    shiny = $script:PokeShiny.Checked
    ot = $script:PokeOt.Text
    otgender = [int]$script:PokeOtGender.Value
    trainerID = [int64]$script:PokeTrainerId.Value
    personalID = [int64]$script:PokePersonalId.Value
    language = [int]$script:PokeLanguage.Value
    ballused = [int]$script:PokeBallUsed.Value
    obtainMode = [int]$script:PokeObtainMode.Value
    obtainLevel = [int]$script:PokeObtainLevel.Value
    obtainMap = [int]$script:PokeObtainMap.Value
    obtainText = $script:PokeObtainText.Text
    hatchedMap = [int]$script:PokeHatchedMap.Value
    markings = [int]$script:PokeMarkings.Value
    expshare = $script:PokeExpShare.Checked
    cool = [int]$script:PokeCool.Value
    beauty = [int]$script:PokeBeauty.Value
    cute = [int]$script:PokeCute.Value
    smart = [int]$script:PokeSmart.Value
    tough = [int]$script:PokeTough.Value
    sheen = [int]$script:PokeSheen.Value
    timeReceived = [int64]$script:PokeTimeReceived.Value
    timeEggHatched = [int64]$script:PokeTimeEggHatched.Value
    firstmoves = $script:PokeFirstMoves.Text
    ribbons = $script:PokeRibbons.Text
  }
  Add-EditorStatValues $values
  for ($i = 0; $i -lt 4; $i++) {
    $values["move$i"] = [int]$script:MoveIds[$i].Value
    $values["move${i}pp"] = [int]$script:MovePps[$i].Value
    $values["move${i}ppup"] = [int]$script:MovePpUps[$i].Value
  }
  Send-EditorCommand "pokemon_set" $values
}

function Add-HexSlotGrid {
  param($Parent, [int]$X, [int]$Y, [int]$Cols, [int]$Rows)
  $grid = New-Object System.Windows.Forms.TableLayoutPanel
  $grid.Location = New-Object System.Drawing.Point($X, $Y)
  $grid.Size = New-Object System.Drawing.Size(($Cols * 69 + 4), ($Rows * 57 + 4))
  $grid.ColumnCount = $Cols
  $grid.RowCount = $Rows
  $grid.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
  $grid.BackColor = [System.Drawing.Color]::FromArgb(96, 174, 108)
  for ($c = 0; $c -lt $Cols; $c++) { [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 68))) }
  for ($r = 0; $r -lt $Rows; $r++) { [void]$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56))) }
  $Parent.Controls.Add($grid)
  return $grid
}

# PKHeX-like main Pokemon editor
$pokemonTab.Controls.Clear()
$pokemonTab.AutoScroll = $false
$pokemonTab.BackColor = [System.Drawing.SystemColors]::Control
$script:HexSections = @{}
$script:HexButtons = @{}

$leftBar = New-Object System.Windows.Forms.Panel
$leftBar.Location = New-Object System.Drawing.Point(0, 0)
$leftBar.Size = New-Object System.Drawing.Size(96, 388)
$leftBar.BackColor = [System.Drawing.SystemColors]::ControlLight
$pokemonTab.Controls.Add($leftBar)

$script:PokePreview = New-SlotPictureBox
$script:PokePreview.Location = New-Object System.Drawing.Point(4, 4)
$script:PokePreview.Size = New-Object System.Drawing.Size(88, 80)
$script:PokePreview.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$script:PokePreview.BackColor = [System.Drawing.SystemColors]::ControlLight
Set-Tip $script:PokePreview "Arrastra este icono para colocar una copia con los datos editados del panel izquierdo."
$script:PokePreview.Add_MouseDown({
  param($sender, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if ($null -eq $script:SelectedPokemon) { return }
  $script:PendingDraftPoint = $e.Location
})
$script:PokePreview.Add_MouseMove({
  param($sender, $e)
  if ($null -eq $script:PendingDraftPoint) { return }
  if (($e.Button -band [System.Windows.Forms.MouseButtons]::Left) -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  $dx = [Math]::Abs($e.X - $script:PendingDraftPoint.X)
  $dy = [Math]::Abs($e.Y - $script:PendingDraftPoint.Y)
  $dragSize = [System.Windows.Forms.SystemInformation]::DragSize
  if ($dx -lt [int]($dragSize.Width / 2) -and $dy -lt [int]($dragSize.Height / 2)) { return }
  $values = Get-EditedPokemonValues
  if ($null -eq $values) { return }
  $script:DraggedSlotTag = $null
  $script:DraggedDraftValues = $values
  $script:PendingDraftPoint = $null
  [void]$sender.DoDragDrop("pokemon-draft", [System.Windows.Forms.DragDropEffects]::Copy)
  $script:DraggedDraftValues = $null
})
$script:PokePreview.Add_MouseUp({ $script:PendingDraftPoint = $null })
$leftBar.Controls.Add($script:PokePreview)
$leftBar.Controls.Add((New-HexSectionButton "Principal" "Main" 88))
$leftBar.Controls.Add((New-HexSectionButton "Captura" "Met" 128))
$leftBar.Controls.Add((New-HexSectionButton "Stats" "Stats" 168))
$leftBar.Controls.Add((New-HexSectionButton "Movs." "Moves" 208))
$leftBar.Controls.Add((New-HexSectionButton "Aspecto" "Cosmetic" 248))
$leftBar.Controls.Add((New-HexSectionButton "EO/Misc" "OT" 288))

$mainPanel = New-HexSectionPanel "Main"
$metPanel = New-HexSectionPanel "Met"
$statsPanel = New-HexSectionPanel "Stats"
$movesPanel = New-HexSectionPanel "Moves"
$cosmeticPanel = New-HexSectionPanel "Cosmetic"
$otPanel = New-HexSectionPanel "OT"

$script:PokemonSource = New-Object System.Windows.Forms.ComboBox
$script:PokemonSource.Items.AddRange(@("Equipo", "PC"))
$script:PokemonSource.SelectedIndex = 0
$script:PokemonSource.Visible = $false
$pokemonTab.Controls.Add($script:PokemonSource)
$script:PokemonBox = New-Object System.Windows.Forms.ComboBox
$script:PokemonBox.Visible = $false
$script:PokemonBox.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { Refresh-PokemonList } })
$pokemonTab.Controls.Add($script:PokemonBox)
$script:PokemonList = New-Object System.Windows.Forms.ListBox
$script:PokemonList.Visible = $false
$script:PokemonList.Add_SelectedIndexChanged({ if (!$script:LoadingUi) { Select-PokemonByIndex $script:PokemonList.SelectedIndex } })
$pokemonTab.Controls.Add($script:PokemonList)
$script:BoxName = New-TextBox 0 0 1
$script:BoxName.Visible = $false
$pokemonTab.Controls.Add($script:BoxName)

$mainPanel.Controls.Add((New-Label "PID:" 54 22 45))
$script:PokePersonalId = New-Number 100 20 0 4294967295 112
$mainPanel.Controls.Add($script:PokePersonalId)
$rerollPid = New-HexButton $mainPanel "Reroll" 224 20 60 24 { Set-NumberValue $script:PokePersonalId (Get-Random -Minimum 1 -Maximum 2147483647) } "Genera un PID aleatorio local antes de aplicar."
$rerollPid.Text = "Nuevo"
$mainPanel.Controls.Add((New-Label "Especie:" 34 54 66))
$script:PokeSpecies = New-Number 100 52 1 9999 86
$script:PokeSpecies.Visible = $false
$mainPanel.Controls.Add($script:PokeSpecies)
$script:SpeciesCombo = New-NamedImageCombo 100 52 184 "species"
$script:SpeciesCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:SpeciesCombo $script:PokeSpecies 1; Update-PokemonPreviewFromInputs; if (!$script:LoadingUi) { Update-AbilityOptionsForCurrentSelection } })
$script:SpeciesCombo.Add_TextChanged({ if (!$script:LoadingUi) { Sync-IdFromCombo $script:SpeciesCombo $script:PokeSpecies 1; Update-PokemonPreviewFromInputs; Update-AbilityOptionsForCurrentSelection } })
$mainPanel.Controls.Add($script:SpeciesCombo)
$script:PokeSpeciesName = New-Label "" 288 52 16
$script:PokeSpeciesName.Visible = $false
$mainPanel.Controls.Add($script:PokeSpeciesName)
$mainPanel.Controls.Add((New-Label "Mote:" 56 86 44))
$script:PokeNick = New-TextBox 100 84 184
$mainPanel.Controls.Add($script:PokeNick)
$mainPanel.Controls.Add((New-Label "EXP:" 60 118 40))
$script:PokeExp = New-Number 100 116 0 99999999 78
$mainPanel.Controls.Add($script:PokeExp)
$mainPanel.Controls.Add((New-Label "Nivel:" 190 118 46))
$script:PokeLevel = New-Number 236 116 1 999 48
$mainPanel.Controls.Add($script:PokeLevel)
$mainPanel.Controls.Add((New-Label "Naturaleza:" 18 150 82))
$script:PokeNatureFlag = New-Number 100 148 -1 24 58
$script:PokeNatureFlag.Visible = $false
$mainPanel.Controls.Add($script:PokeNatureFlag)
$script:NatureCombo = New-NamedImageCombo 100 148 132 "nature"
$script:NatureCombo.DropDownWidth = 326
$script:NatureCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:NatureCombo $script:PokeNatureFlag -1; Update-NatureEffectDisplay })
$mainPanel.Controls.Add($script:NatureCombo)
$randomNature = New-HexButton $mainPanel "Azar" 238 148 46 24 { Set-RandomNature } "Elige una naturaleza aleatoria para el Pokemon seleccionado."
$script:PokeNatureName = New-Label "" 288 148 16
$script:PokeNatureName.Visible = $false
$mainPanel.Controls.Add($script:PokeNatureName)
$script:NatureUpLabel = New-Label "" 100 176 86
$script:NatureUpLabel.ForeColor = [System.Drawing.Color]::FromArgb(190, 35, 35)
$mainPanel.Controls.Add($script:NatureUpLabel)
$script:NatureDownLabel = New-Label "" 190 176 94
$script:NatureDownLabel.ForeColor = [System.Drawing.Color]::FromArgb(35, 95, 190)
$mainPanel.Controls.Add($script:NatureDownLabel)
$mainPanel.Controls.Add((New-Label "Objeto:" 42 214 58))
$script:PokeItem = New-Number 100 212 0 9999 68
$script:PokeItem.Visible = $false
$mainPanel.Controls.Add($script:PokeItem)
$script:ItemCombo = New-NamedImageCombo 100 212 184 "item"
$script:ItemCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:ItemCombo $script:PokeItem 0 })
$script:ItemCombo.Add_TextChanged({ if (!$script:LoadingUi) { Sync-IdFromCombo $script:ItemCombo $script:PokeItem 0 } })
$mainPanel.Controls.Add($script:ItemCombo)
$script:PokeItemName = New-Label "" 288 212 16
$script:PokeItemName.Visible = $false
$mainPanel.Controls.Add($script:PokeItemName)
$mainPanel.Controls.Add((New-Label "Habilidad:" 28 246 72))
$script:PokeAbilityFlag = New-Number 100 244 -1 2 58
$script:PokeAbilityFlag.Visible = $false
$mainPanel.Controls.Add($script:PokeAbilityFlag)
$script:AbilityCombo = New-NamedImageCombo 100 244 184 "ability"
$script:AbilityCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:AbilityCombo $script:PokeAbilityFlag -1; Update-AbilityDetails })
$mainPanel.Controls.Add($script:AbilityCombo)
$script:PokeAbilityName = New-Label "" 288 244 16
$script:PokeAbilityName.Visible = $false
$mainPanel.Controls.Add($script:PokeAbilityName)
$script:AbilityDescriptionBox = New-Object System.Windows.Forms.TextBox
$script:AbilityDescriptionBox.Location = New-Object System.Drawing.Point(18, 272)
$script:AbilityDescriptionBox.Size = New-Object System.Drawing.Size(266, 48)
$script:AbilityDescriptionBox.Multiline = $true
$script:AbilityDescriptionBox.ReadOnly = $true
$script:AbilityDescriptionBox.WordWrap = $true
$script:AbilityDescriptionBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:AbilityDescriptionBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:AbilityDescriptionBox.BackColor = [System.Drawing.SystemColors]::Control
$script:AbilityDescriptionBox.Font = New-Object System.Drawing.Font("Segoe UI", 7.6)
$mainPanel.Controls.Add($script:AbilityDescriptionBox)
$mainPanel.Controls.Add((New-Label "Amistad:" 34 326 66))
$script:PokeHappiness = New-Number 100 324 0 255 58
$mainPanel.Controls.Add($script:PokeHappiness)
$script:PokeLanguage = New-Number 0 0 0 9999 58
$script:PokeLanguage.Visible = $false
$mainPanel.Controls.Add($script:PokeLanguage)
$script:PokeShiny = New-Object System.Windows.Forms.CheckBox
$script:PokeShiny.Text = "Shiny"
$script:PokeShiny.Location = New-Object System.Drawing.Point(100, 352)
$script:PokeShiny.AutoSize = $true
$script:PokeShiny.Add_CheckedChanged({ if (!$script:LoadingUi) { Update-PokemonPreviewFromInputs } })
$mainPanel.Controls.Add($script:PokeShiny)
$script:PokeExpShare = New-Object System.Windows.Forms.CheckBox
$script:PokeExpShare.Text = "Exp Share"
$script:PokeExpShare.Location = New-Object System.Drawing.Point(182, 352)
$script:PokeExpShare.Size = New-Object System.Drawing.Size(108, 24)
$script:PokeExpShare.AutoSize = $false
$mainPanel.Controls.Add($script:PokeExpShare)
$script:PokemonLoc = New-Label "" 8 372 280 16
$mainPanel.Controls.Add($script:PokemonLoc)

$metPanel.Controls.Add((New-Label "Met Location:" 20 28 96))
$script:PokeObtainText = New-TextBox 118 26 160
$metPanel.Controls.Add($script:PokeObtainText)
$metPanel.Controls.Add((New-Label "Poke Ball:" 44 62 74))
$script:PokeBallUsed = New-Number 118 60 0 9999 70
$script:PokeBallUsed.Visible = $false
$script:PokeBallUsed.Add_ValueChanged({ if (!$script:LoadingUi) { Update-BallPreview } })
$metPanel.Controls.Add($script:PokeBallUsed)
$script:PokeBallCombo = New-NamedImageCombo 118 60 164 "ball"
$script:PokeBallCombo.Add_SelectedIndexChanged({
  Sync-IdFromCombo $script:PokeBallCombo $script:PokeBallUsed 0
  Update-BallPreview
})
$script:PokeBallCombo.Add_TextChanged({
  if (!$script:LoadingUi) {
    Sync-IdFromCombo $script:PokeBallCombo $script:PokeBallUsed 0
    Update-BallPreview
  }
})
$metPanel.Controls.Add($script:PokeBallCombo)
$script:PokeBallPreview = New-Object System.Windows.Forms.PictureBox
$script:PokeBallPreview.Location = New-Object System.Drawing.Point(288, 58)
$script:PokeBallPreview.Size = New-Object System.Drawing.Size(32, 28)
$script:PokeBallPreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$metPanel.Controls.Add($script:PokeBallPreview)
$metPanel.Controls.Add((New-Label "Met Level:" 38 96 80))
$script:PokeObtainLevel = New-Number 118 94 0 999 70
$metPanel.Controls.Add($script:PokeObtainLevel)
$metPanel.Controls.Add((New-Label "Met Map:" 52 130 66))
$script:PokeObtainMap = New-Number 118 128 0 99999 80
$metPanel.Controls.Add($script:PokeObtainMap)
$metPanel.Controls.Add((New-Label "Mode:" 70 164 48))
$script:PokeObtainMode = New-Number 118 162 0 9 70
$metPanel.Controls.Add($script:PokeObtainMode)
$script:PokeEggSteps = New-Number 118 220 0 999999 80
$metPanel.Controls.Add((New-Label "Egg Steps:" 42 222 76))
$metPanel.Controls.Add($script:PokeEggSteps)
$script:PokeHatchedMap = New-Number 118 254 0 99999 80
$metPanel.Controls.Add((New-Label "Hatch Map:" 38 256 80))
$metPanel.Controls.Add($script:PokeHatchedMap)
$script:PokeTimeReceived = New-Number 118 304 0 2147483647 120
$metPanel.Controls.Add((New-Label "Received:" 42 306 76))
$metPanel.Controls.Add($script:PokeTimeReceived)
$script:PokeTimeEggHatched = New-Number 118 338 0 2147483647 120
$metPanel.Controls.Add((New-Label "Hatched:" 48 340 70))
$metPanel.Controls.Add($script:PokeTimeEggHatched)

$stats = @("HP", "Atk", "Def", "SpA", "SpD", "Spe")
$script:IvNums = @()
$script:EvNums = @()
$script:BaseStatLabels = @()
$script:ActualStatLabels = @()
$statsPanel.Controls.Add((New-Label "Base" 112 22 40))
$statsPanel.Controls.Add((New-Label "IVs" 158 22 34))
$statsPanel.Controls.Add((New-Label "EVs" 202 22 34))
$statsPanel.Controls.Add((New-Label "Stats" 246 22 44))
for ($i = 0; $i -lt 6; $i++) {
  $y = 54 + ($i * 34)
  $statLabel = New-Label $stats[$i] 54 $y 44
  $statLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
  $baseLabel = New-Label "0" 108 $y 40
  $baseLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
  $iv = New-Number 154 $y 0 31 42
  $ev = New-Number 200 $y 0 252 44
  $actualLabel = New-Label "0" 248 $y 44
  $actualLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
  $actualLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $script:IvNums += $iv
  $script:EvNums += $ev
  $script:BaseStatLabels += $baseLabel
  $script:ActualStatLabels += $actualLabel
  $statsPanel.Controls.Add($statLabel)
  $statsPanel.Controls.Add($baseLabel)
  $statsPanel.Controls.Add($iv)
  $statsPanel.Controls.Add($ev)
  $statsPanel.Controls.Add($actualLabel)
}
$randomIvButton = New-HexButton $statsPanel "Random IVs" 116 258 86 26 {
  for ($i = 0; $i -lt 6; $i++) { Set-NumberValue $script:IvNums[$i] (Get-Random -Minimum 0 -Maximum 32) }
  Mark-Dirty
} "Randomiza todos los IVs del Pokemon editado."
$randomIvButton.Text = "Azar IVs"
$randomEvButton = New-HexButton $statsPanel "Random EVs" 208 258 86 26 {
  $evs = @(0, 0, 0, 0, 0, 0)
  for ($point = 0; $point -lt 510; $point++) {
    $choices = @()
    for ($i = 0; $i -lt 6; $i++) {
      if ($evs[$i] -lt 252) { $choices += $i }
    }
    if ($choices.Count -le 0) { break }
    $pick = $choices[(Get-Random -Minimum 0 -Maximum $choices.Count)]
    $evs[$pick]++
  }
  for ($i = 0; $i -lt 6; $i++) { Set-NumberValue $script:EvNums[$i] $evs[$i] }
  Mark-Dirty
} "Randomiza todos los EVs del Pokemon editado."
$randomEvButton.Text = "Azar EVs"
$statsPanel.Controls.Add((New-Label "PS actual:" 38 296 82))
$script:PokeHp = New-Number 120 294 0 9999 70
$statsPanel.Controls.Add($script:PokeHp)
$script:PokeTotalHp = New-Label "" 196 294 70
$statsPanel.Controls.Add($script:PokeTotalHp)
$statsPanel.Controls.Add((New-Label "Estado:" 62 330 56))
$script:PokeStatus = New-Number 120 328 0 9 60
$script:PokeStatus.Visible = $false
$statsPanel.Controls.Add($script:PokeStatus)
$script:StatusCombo = New-NamedImageCombo 120 328 116 "text"
$script:StatusCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:StatusCombo $script:PokeStatus 0 })
$statsPanel.Controls.Add($script:StatusCombo)
$statsPanel.Controls.Add((New-Label "Turnos:" 240 330 52))
$script:PokeStatusCount = New-Number 292 328 0 9999 44
$statsPanel.Controls.Add($script:PokeStatusCount)

$script:MoveIds = @()
$script:MoveCombos = @()
$script:MovePps = @()
$script:MovePpUps = @()
$script:MoveNames = @()
$movesPanel.Controls.Add((New-Label "Movimiento" 76 24 116))
$movesPanel.Controls.Add((New-Label "PP" 224 24 30))
$movesPanel.Controls.Add((New-Label "Mas" 266 24 35))
for ($i = 0; $i -lt 4; $i++) {
  $y = 58 + ($i * 34)
  $movesPanel.Controls.Add((New-Label ("{0}:" -f ($i + 1)) 42 $y 26))
  $mid = New-Number 70 $y 0 9999 1
  $mid.Visible = $false
  $mcombo = New-NamedImageCombo 70 $y 146 "move"
  $mcombo.Name = "MoveCombo_$i"
  $mcombo.Add_SelectedIndexChanged({
    param($sender, $e)
    $idx = [int](([string]$sender.Name).Replace("MoveCombo_", ""))
    Sync-IdFromCombo $sender $script:MoveIds[$idx] 0
    Update-MoveDetailsBox $idx
  })
  $mcombo.Add_Enter({
    param($sender, $e)
    $idx = [int](([string]$sender.Name).Replace("MoveCombo_", ""))
    Update-MoveDetailsBox $idx
  })
  $mcombo.Add_Click({
    param($sender, $e)
    $idx = [int](([string]$sender.Name).Replace("MoveCombo_", ""))
    Update-MoveDetailsBox $idx
  })
  $mcombo.Add_DropDown({
    param($sender, $e)
    $idx = [int](([string]$sender.Name).Replace("MoveCombo_", ""))
    Update-MoveDetailsBox $idx
  })
  $mcombo.Add_DropDownClosed({
    param($sender, $e)
    $idx = [int](([string]$sender.Name).Replace("MoveCombo_", ""))
    Update-MoveDetailsBox $idx
  })
  $mname = New-Label "" 218 $y 1
  $mname.Visible = $false
  $mpp = New-Number 224 $y 0 99 34
  $mppup = New-Number 264 $y 0 3 34
  $script:MoveIds += $mid
  $script:MoveCombos += $mcombo
  $script:MoveNames += $mname
  $script:MovePps += $mpp
  $script:MovePpUps += $mppup
  $movesPanel.Controls.Add($mid)
  $movesPanel.Controls.Add($mcombo)
  $movesPanel.Controls.Add($mname)
  $movesPanel.Controls.Add($mpp)
  $movesPanel.Controls.Add($mppup)
}
$movesPanel.Controls.Add((New-Label "Mov. iniciales:" 18 198 98))
$script:PokeFirstMoves = New-TextBox 116 196 170
$movesPanel.Controls.Add($script:PokeFirstMoves)
$movesPanel.Controls.Add((New-Label "Detalles:" 18 230 76))
$script:MoveDetailsBox = New-Object System.Windows.Forms.Panel
$script:MoveDetailsBox.Location = New-Object System.Drawing.Point(18, 248)
$script:MoveDetailsBox.Size = New-Object System.Drawing.Size(268, 134)
$script:MoveDetailsBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:MoveDetailsBox.BackColor = [System.Drawing.Color]::White
$movesPanel.Controls.Add($script:MoveDetailsBox)

$cosmeticPanel.Controls.Add((New-Label "Forma:" 66 28 54))
$script:PokeForm = New-Number 120 26 0 999 70
$script:PokeForm.Add_ValueChanged({ if (!$script:LoadingUi) { Update-PokemonPreviewFromInputs } })
$cosmeticPanel.Controls.Add($script:PokeForm)
$cosmeticPanel.Controls.Add((New-Label "Pokerus:" 52 62 68))
$script:PokePokerus = New-Number 120 60 0 255 70
$cosmeticPanel.Controls.Add($script:PokePokerus)
$cosmeticPanel.Controls.Add((New-Label "Genero:" 58 96 62))
$script:PokeGenderFlag = New-Number 120 94 -1 1 70
$script:PokeGenderFlag.Visible = $false
$cosmeticPanel.Controls.Add($script:PokeGenderFlag)
$script:GenderCombo = New-NamedImageCombo 120 94 122 "text"
$script:GenderCombo.Add_SelectedIndexChanged({ Sync-IdFromCombo $script:GenderCombo $script:PokeGenderFlag -1 })
$cosmeticPanel.Controls.Add($script:GenderCombo)
$cosmeticPanel.Controls.Add((New-Label "Marcas:" 58 130 62))
$script:PokeMarkings = New-Number 120 128 0 15 70
$cosmeticPanel.Controls.Add($script:PokeMarkings)
$contestNames = @("Carisma", "Belleza", "Dulzura", "Ingenio", "Dureza", "Brillo")
$contestVars = @("PokeCool", "PokeBeauty", "PokeCute", "PokeSmart", "PokeTough", "PokeSheen")
for ($i = 0; $i -lt 6; $i++) {
  $x = 30 + (($i % 3) * 86)
  $y = 210 + ([Math]::Floor($i / 3) * 42)
  $cosmeticPanel.Controls.Add((New-Label $contestNames[$i] $x $y 54))
  Set-Variable -Name $contestVars[$i] -Scope Script -Value (New-Number ($x + 50) $y 0 255 38)
  $cosmeticPanel.Controls.Add((Get-Variable -Name $contestVars[$i] -Scope Script).Value)
}
$cosmeticPanel.Controls.Add((New-Label "Cintas:" 54 320 58))
$script:PokeRibbons = New-TextBox 108 318 176
$cosmeticPanel.Controls.Add($script:PokeRibbons)

$otPanel.Controls.Add((New-Label "Datos del entrenador" 70 28 170))
$script:PokeOt = New-TextBox 100 70 160
$otPanel.Controls.Add((New-Label "OT:" 70 72 30))
$otPanel.Controls.Add($script:PokeOt)
$script:PokeTrainerId = New-Number 100 106 0 4294967295 100
$otPanel.Controls.Add((New-Label "TID:" 64 108 36))
$otPanel.Controls.Add($script:PokeTrainerId)
$script:PokeOtGender = New-Number 100 142 0 3 70
$otPanel.Controls.Add((New-Label "Gender:" 44 144 56))
$otPanel.Controls.Add($script:PokeOtGender)
$script:PokeMeta = New-Object System.Windows.Forms.Label
$script:PokeMeta.Location = New-Object System.Drawing.Point(26, 214)
$script:PokeMeta.Size = New-Object System.Drawing.Size(250, 70)
$otPanel.Controls.Add($script:PokeMeta)

$rightTabs = New-Object System.Windows.Forms.TabControl
$rightTabs.Location = New-Object System.Drawing.Point(404, 0)
$rightTabs.Size = New-Object System.Drawing.Size(444, 388)
$rightTabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$pokemonTab.Controls.Add($rightTabs)
$boxRightTab = New-Object System.Windows.Forms.TabPage
$boxRightTab.Text = "Caja"
$partyRightTab = New-Object System.Windows.Forms.TabPage
$partyRightTab.Text = "Equipo"
$otherRightTab = New-Object System.Windows.Forms.TabPage
$otherRightTab.Text = "Otros"
$savRightTab = New-Object System.Windows.Forms.TabPage
$savRightTab.Text = "SAV"
$rightTabs.TabPages.AddRange(@($boxRightTab, $partyRightTab, $otherRightTab, $savRightTab))

$prevBox = New-HexButton $boxRightTab "<<" 122 10 30 24 {
  if ($script:PCBox.Items.Count -le 0) { return }
  $script:PCBox.SelectedIndex = [Math]::Max(0, $script:PCBox.SelectedIndex - 1)
} "Caja anterior."
$script:HexBoxSelector = New-Object System.Windows.Forms.ComboBox
$script:HexBoxSelector.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:HexBoxSelector.Location = New-Object System.Drawing.Point(156, 10)
$script:HexBoxSelector.Size = New-Object System.Drawing.Size(160, 24)
$script:HexBoxSelector.Add_SelectedIndexChanged({
  if ($script:LoadingUi) { return }
  if ($script:HexBoxSelector.SelectedIndex -ge 0 -and $script:PCBox.Items.Count -gt $script:HexBoxSelector.SelectedIndex) {
    $script:PCBox.SelectedIndex = $script:HexBoxSelector.SelectedIndex
    if ($script:PokemonBox.Items.Count -gt $script:HexBoxSelector.SelectedIndex) { $script:PokemonBox.SelectedIndex = $script:HexBoxSelector.SelectedIndex }
    Refresh-PCTab
  }
})
$boxRightTab.Controls.Add($script:HexBoxSelector)
$nextBox = New-HexButton $boxRightTab ">>" 322 10 30 24 {
  if ($script:PCBox.Items.Count -le 0) { return }
  $script:PCBox.SelectedIndex = [Math]::Min($script:PCBox.Items.Count - 1, $script:PCBox.SelectedIndex + 1)
} "Caja siguiente."
$hexBoxGrid = Add-HexSlotGrid $boxRightTab 16 50 6 5
$script:HexBoxSlots = @()
for ($slot = 0; $slot -lt 30; $slot++) {
  $slotBox = New-SlotPictureBox
  $script:HexBoxSlots += $slotBox
  $hexBoxGrid.Controls.Add($slotBox, ($slot % 6), [int][Math]::Floor($slot / 6))
}

$hexPartyGrid = Add-HexSlotGrid $partyRightTab 98 30 2 3
$script:HexPartySlots = @()
for ($slot = 0; $slot -lt 6; $slot++) {
  $slotBox = New-SlotPictureBox
  $script:HexPartySlots += $slotBox
  $hexPartyGrid.Controls.Add($slotBox, ($slot % 2), [int][Math]::Floor($slot / 2))
}

$daycare = New-Object System.Windows.Forms.GroupBox
$daycare.Text = "Guarderia"
$daycare.Location = New-Object System.Drawing.Point(24, 20)
$daycare.Size = New-Object System.Drawing.Size(200, 180)
$otherRightTab.Controls.Add($daycare)
for ($i = 0; $i -lt 2; $i++) {
  $empty = New-Object System.Windows.Forms.Panel
  $empty.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $empty.Location = New-Object System.Drawing.Point(12, (24 + ($i * 64)))
  $empty.Size = New-Object System.Drawing.Size(70, 56)
  $daycare.Controls.Add($empty)
  $daycare.Controls.Add((New-Label ("{0}:" -f ($i + 1)) 92 (42 + ($i * 64)) 24))
  $xp = New-Number 122 (38 + ($i * 64)) 0 999999 72
  $daycare.Controls.Add($xp)
}
$otherRightTab.Controls.Add((New-Label "Misc" 344 8 60))
for ($i = 0; $i -lt 4; $i++) {
  $red = New-Object System.Windows.Forms.Panel
  $red.BackColor = [System.Drawing.Color]::Red
  $red.Location = New-Object System.Drawing.Point(338, (36 + ($i * 64)))
  $red.Size = New-Object System.Drawing.Size(70, 58)
  $otherRightTab.Controls.Add($red)
}

[void](New-HexButton $savRightTab "Recargar`nestado" 12 18 92 46 { Discard-PendingChanges; Refresh-All $true } "Recarga el estado vivo y descarta cambios pendientes no guardados.")
[void](New-HexButton $savRightTab "Verificar`ndatos" 116 18 92 46 { Refresh-All $true } "Recarga y verifica que el editor lee el estado vivo.")
[void](New-HexButton $savRightTab "Verificar`nPokemon" 220 18 92 46 { Refresh-All $true } "Relee equipo y PC.")
[void](New-HexButton $savRightTab "Resultado`nultimo" 324 18 92 46 { Load-LiveData } "Relee el ultimo resultado de comandos sin guardar la partida.")
[void](New-HexButton $savRightTab "Datos" 16 190 94 30 { Show-RawDataWindow } "Abre los datos raw en una ventana separada.")
[void](New-HexButton $savRightTab "Cajas" 120 190 94 30 { Show-BoxLayoutWindow } "Abre el diseno de cajas en una ventana separada.")
[void](New-HexButton $savRightTab "Objetos" 224 190 94 30 { Show-InventoryEditor } "Abre una ventana de inventario tipo PKHeX.")
[void](New-HexButton $savRightTab "Entrenador" 328 190 94 30 { Show-TrainerInfoWindow } "Abre datos del entrenador en una ventana separada.")
[void](New-HexButton $savRightTab "Pokedex" 16 230 94 30 { Show-PokedexEditor } "Abre una ventana de Pokedex tipo PKHeX.")
[void](New-HexButton $savRightTab "Switches" 120 230 94 30 { Show-SwitchesWindow } "Abre switches y variables en una ventana separada.")
[void](New-HexButton $savRightTab "Logros" 224 230 94 30 { Show-AchievementsEditor } "Abre una ventana para modificar los logros del juego.")

$savRightTab.Controls.Add((New-Label "Crear" 18 284 55))
$script:CreateSpecies = New-Number 78 282 1 9999 70
$script:CreateSpecies.Visible = $false
$savRightTab.Controls.Add($script:CreateSpecies)
$script:CreateSpeciesCombo = New-NamedImageCombo 78 282 146 "species"
$script:CreateSpeciesCombo.Add_SelectedIndexChanged({
  $id = Get-NamedComboId $script:CreateSpeciesCombo
  if ($id -ne $null -and $id -gt 0) { Set-NumberValue $script:CreateSpecies $id }
})
$script:CreateSpeciesCombo.Add_TextChanged({
  $id = Get-NamedComboId $script:CreateSpeciesCombo
  if ($id -ne $null -and $id -gt 0) { Set-NumberValue $script:CreateSpecies $id }
})
$savRightTab.Controls.Add($script:CreateSpeciesCombo)
$script:CreateLevel = New-Number 232 282 1 999 48
$savRightTab.Controls.Add($script:CreateLevel)
$script:DestLoc = New-Object System.Windows.Forms.ComboBox
$script:DestLoc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:DestLoc.Items.AddRange(@("Equipo", "PC"))
$script:DestLoc.SelectedIndex = 1
$script:DestLoc.Location = New-Object System.Drawing.Point(286, 282)
$script:DestLoc.Size = New-Object System.Drawing.Size(72, 24)
$savRightTab.Controls.Add($script:DestLoc)
$script:DestPartyIndex = New-Number 0 0 0 6 55
$script:DestPartyIndex.Visible = $false
$pokemonTab.Controls.Add($script:DestPartyIndex)
$script:DestBox = New-Number 0 0 1 99 55
$script:DestBox.Visible = $false
$pokemonTab.Controls.Add($script:DestBox)
$script:DestSlot = New-Number 0 0 0 99 55
$script:DestSlot.Visible = $false
$pokemonTab.Controls.Add($script:DestSlot)
$script:ReplaceSlot = New-Object System.Windows.Forms.CheckBox
$script:ReplaceSlot.Visible = $false
$pokemonTab.Controls.Add($script:ReplaceSlot)
[void](New-HexButton $savRightTab "Crear" 364 280 58 30 {
  $values = Add-DestinationValues @{
    species = [int]$script:CreateSpecies.Value
    level = [int]$script:CreateLevel.Value
  }
  Send-EditorCommand "pokemon_create" $values
} "Crea un Pokemon con especie/nivel indicados.")

Show-HexSection "Main"

# Bag tab
$bagTab.Controls.Add((New-Label "Buscar" 16 14 60))
$script:BagSearch = New-TextBox 80 14 260
$script:BagSearch.Add_TextChanged({ if (!$script:LoadingUi) { Refresh-BagTab } })
Set-Tip $script:BagSearch "Filtra objetos por nombre o ID."
$bagTab.Controls.Add($script:BagSearch)
$script:BagOwnedOnly = New-Object System.Windows.Forms.CheckBox
$script:BagOwnedOnly.Text = "Solo con cantidad"
$script:BagOwnedOnly.Checked = Get-SebiSettingBool -Path $script:IniPath -Name 'save_editor_bag_owned_only' -Default $true
$script:BagOwnedOnly.Add_CheckedChanged({
  Set-SebiSetting -Path $script:IniPath -Name 'save_editor_bag_owned_only' -Value ([string]$script:BagOwnedOnly.Checked).ToLowerInvariant()
})
$script:BagOwnedOnly.Location = New-Object System.Drawing.Point(360, 16)
$script:BagOwnedOnly.Size = New-Object System.Drawing.Size(150, 24)
$script:BagOwnedOnly.Add_CheckedChanged({ if (!$script:LoadingUi) { Refresh-BagTab } })
Set-Tip $script:BagOwnedOnly "Muestra solo objetos que tienen cantidad mayor que 0."
$bagTab.Controls.Add($script:BagOwnedOnly)

$script:BagGrid = New-Object System.Windows.Forms.DataGridView
$script:BagGrid.Location = New-Object System.Drawing.Point(16, 52)
$script:BagGrid.Size = New-Object System.Drawing.Size(700, 535)
$script:BagGrid.ReadOnly = $true
$script:BagGrid.AllowUserToAddRows = $false
$script:BagGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$script:BagGrid.MultiSelect = $false
$script:BagGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$script:BagGrid.Add_SelectionChanged({
  if ($script:LoadingUi -or $null -eq $script:BagGrid.CurrentRow) { return }
  $row = $script:BagGrid.CurrentRow.DataBoundItem
  if ($null -eq $row) { return }
  Set-NumberValue $script:BagItemId ([int]$row.ID)
  Set-NumberValue $script:BagQty ([int]$row.Cantidad)
})
Set-Tip $script:BagGrid "Selecciona un objeto para copiar su ID y cantidad a los campos de la derecha."
$bagTab.Controls.Add($script:BagGrid)
$bagTab.Controls.Add((New-Label "Objeto ID" 750 70 100))
$script:BagItemId = New-Number 850 70 1 9999
$bagTab.Controls.Add($script:BagItemId)
$bagTab.Controls.Add((New-Label "Cantidad" 750 110 100))
$script:BagQty = New-Number 850 110 0 999
$bagTab.Controls.Add($script:BagQty)
$giveItem = New-Object System.Windows.Forms.Button
$giveItem.Text = "Dar cantidad"
$giveItem.Location = New-Object System.Drawing.Point(750, 155)
$giveItem.Size = New-Object System.Drawing.Size(130, 34)
$giveItem.Add_Click({ Send-EditorCommand "give_item" @{ item = [int]$script:BagItemId.Value; qty = [int]$script:BagQty.Value } })
Set-Tip $giveItem "Suma esa cantidad del objeto a la mochila."
$bagTab.Controls.Add($giveItem)
$setItem = New-Object System.Windows.Forms.Button
$setItem.Text = "Fijar cantidad"
$setItem.Location = New-Object System.Drawing.Point(890, 155)
$setItem.Size = New-Object System.Drawing.Size(130, 34)
$setItem.Add_Click({ Send-EditorCommand "set_item_qty" @{ item = [int]$script:BagItemId.Value; qty = [int]$script:BagQty.Value } })
Set-Tip $setItem "Fija la cantidad exacta de ese objeto en la mochila."
$bagTab.Controls.Add($setItem)
$clearItem = New-Object System.Windows.Forms.Button
$clearItem.Text = "Poner a 0"
$clearItem.Location = New-Object System.Drawing.Point(750, 200)
$clearItem.Size = New-Object System.Drawing.Size(130, 34)
$clearItem.Add_Click({ Send-EditorCommand "set_item_qty" @{ item = [int]$script:BagItemId.Value; qty = 0 } })
Set-Tip $clearItem "Elimina ese objeto de la mochila poniendo su cantidad a 0."
$bagTab.Controls.Add($clearItem)

# Batch tab
$batchTab.Controls.Add((New-Label "Alcance" 24 34 90))
$script:BatchScope = New-Object System.Windows.Forms.ComboBox
$script:BatchScope.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:BatchScope.Items.AddRange(@("Equipo", "Caja actual", "Todo el PC", "Equipo + PC"))
$script:BatchScope.SelectedIndex = 0
$script:BatchScope.Location = New-Object System.Drawing.Point(140, 34)
$script:BatchScope.Size = New-Object System.Drawing.Size(180, 24)
Set-Tip $script:BatchScope "Elige si el lote afecta al equipo, caja actual, todo el PC o todo junto."
$batchTab.Controls.Add($script:BatchScope)

$script:BatchSetLevel = New-Object System.Windows.Forms.CheckBox
$script:BatchSetLevel.Text = "Fijar nivel"
$script:BatchSetLevel.Location = New-Object System.Drawing.Point(24, 86)
$script:BatchSetLevel.Size = New-Object System.Drawing.Size(120, 24)
Set-Tip $script:BatchSetLevel "Activa esto para cambiar el nivel de todos los Pokemon del alcance."
$batchTab.Controls.Add($script:BatchSetLevel)
$script:BatchLevel = New-Number 160 84 1 999 80
$batchTab.Controls.Add($script:BatchLevel)

$script:BatchSetItem = New-Object System.Windows.Forms.CheckBox
$script:BatchSetItem.Text = "Fijar objeto"
$script:BatchSetItem.Location = New-Object System.Drawing.Point(24, 126)
$script:BatchSetItem.Size = New-Object System.Drawing.Size(120, 24)
Set-Tip $script:BatchSetItem "Activa esto para poner el mismo objeto equipado a todos los Pokemon del alcance."
$batchTab.Controls.Add($script:BatchSetItem)
$script:BatchItem = New-Number 160 124 0 9999 90
$batchTab.Controls.Add($script:BatchItem)

$script:BatchSetHappiness = New-Object System.Windows.Forms.CheckBox
$script:BatchSetHappiness.Text = "Fijar felicidad"
$script:BatchSetHappiness.Location = New-Object System.Drawing.Point(24, 166)
$script:BatchSetHappiness.Size = New-Object System.Drawing.Size(130, 24)
Set-Tip $script:BatchSetHappiness "Activa esto para fijar la felicidad de todos los Pokemon del alcance."
$batchTab.Controls.Add($script:BatchSetHappiness)
$script:BatchHappiness = New-Number 160 164 0 255 80
$batchTab.Controls.Add($script:BatchHappiness)

$batchTab.Controls.Add((New-Label "Shiny" 24 206 90))
$script:BatchShiny = New-Object System.Windows.Forms.ComboBox
$script:BatchShiny.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:BatchShiny.Items.AddRange(@("No cambiar", "Forzar shiny", "Forzar normal"))
$script:BatchShiny.SelectedIndex = 0
$script:BatchShiny.Location = New-Object System.Drawing.Point(160, 206)
$script:BatchShiny.Size = New-Object System.Drawing.Size(160, 24)
Set-Tip $script:BatchShiny "Permite dejar shiny igual, forzar shiny o forzar normal en lote."
$batchTab.Controls.Add($script:BatchShiny)

$script:BatchHeal = New-Object System.Windows.Forms.CheckBox
$script:BatchHeal.Text = "Curar PS/PP/estado"
$script:BatchHeal.Location = New-Object System.Drawing.Point(24, 246)
$script:BatchHeal.Size = New-Object System.Drawing.Size(180, 24)
Set-Tip $script:BatchHeal "Cura PS, PP y estado de todos los Pokemon afectados por el lote."
$batchTab.Controls.Add($script:BatchHeal)

$applyBatch = New-Object System.Windows.Forms.Button
$applyBatch.Text = "Aplicar lote"
$applyBatch.Location = New-Object System.Drawing.Point(24, 302)
$applyBatch.Size = New-Object System.Drawing.Size(140, 36)
$applyBatch.Add_Click({
  $scope = @("party", "box", "pc", "all")[$script:BatchScope.SelectedIndex]
  $shinyValue = "keep"
  if ($script:BatchShiny.SelectedIndex -eq 1) { $shinyValue = "true" }
  if ($script:BatchShiny.SelectedIndex -eq 2) { $shinyValue = "false" }
  $boxIndex = 0
  if ($null -ne $script:PCBox -and $script:PCBox.SelectedIndex -ge 0) { $boxIndex = [int]$script:PCBox.SelectedIndex }
  Send-EditorCommand "pokemon_batch" @{
    scope = $scope
    box = $boxIndex
    setLevel = $script:BatchSetLevel.Checked
    level = [int]$script:BatchLevel.Value
    setItem = $script:BatchSetItem.Checked
    item = [int]$script:BatchItem.Value
    setHappiness = $script:BatchSetHappiness.Checked
    happiness = [int]$script:BatchHappiness.Value
    shiny = $shinyValue
    heal = $script:BatchHeal.Checked
  }
})
Set-Tip $applyBatch "Aplica los cambios marcados a todos los Pokemon del alcance seleccionado."
$batchTab.Controls.Add($applyBatch)

# World tab
$worldTab.Controls.Add((New-Label "Switch ID" 24 28 100))
$script:SwitchId = New-Number 130 28 1 9999
$worldTab.Controls.Add($script:SwitchId)
$script:SwitchValue = New-Object System.Windows.Forms.CheckBox
$script:SwitchValue.Text = "Activado"
$script:SwitchValue.Location = New-Object System.Drawing.Point(260, 28)
$worldTab.Controls.Add($script:SwitchValue)
$setSwitch = New-Object System.Windows.Forms.Button
$setSwitch.Text = "Aplicar switch"
$setSwitch.Location = New-Object System.Drawing.Point(380, 24)
$setSwitch.Size = New-Object System.Drawing.Size(130, 32)
$setSwitch.Add_Click({ Send-EditorCommand "switch_set" @{ id = [int]$script:SwitchId.Value; value = $script:SwitchValue.Checked } })
Set-Tip $setSwitch "Cambia el valor ON/OFF del switch indicado. Puede afectar eventos."
$worldTab.Controls.Add($setSwitch)

$worldTab.Controls.Add((New-Label "Variable ID" 24 80 100))
$script:VariableId = New-Number 130 80 1 9999
$worldTab.Controls.Add($script:VariableId)
$worldTab.Controls.Add((New-Label "Valor" 260 80 50))
$script:VariableValue = New-TextBox 315 80 220
$worldTab.Controls.Add($script:VariableValue)
$setVariable = New-Object System.Windows.Forms.Button
$setVariable.Text = "Aplicar variable"
$setVariable.Location = New-Object System.Drawing.Point(550, 76)
$setVariable.Size = New-Object System.Drawing.Size(140, 32)
$setVariable.Add_Click({ Send-EditorCommand "variable_set" @{ id = [int]$script:VariableId.Value; value = $script:VariableValue.Text } })
Set-Tip $setVariable "Cambia el valor de la variable indicada. Puede afectar progreso o eventos."
$worldTab.Controls.Add($setVariable)

$worldTab.Controls.Add((New-Label "Switches ON" 24 140 140))
$script:SwitchList = New-Object System.Windows.Forms.TextBox
$script:SwitchList.Multiline = $true
$script:SwitchList.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:SwitchList.Location = New-Object System.Drawing.Point(24, 170)
$script:SwitchList.Size = New-Object System.Drawing.Size(480, 410)
$worldTab.Controls.Add($script:SwitchList)
$worldTab.Controls.Add((New-Label "Variables con valor" 530 140 180))
$script:VariableList = New-Object System.Windows.Forms.TextBox
$script:VariableList.Multiline = $true
$script:VariableList.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:VariableList.Location = New-Object System.Drawing.Point(530, 170)
$script:VariableList.Size = New-Object System.Drawing.Size(520, 410)
$worldTab.Controls.Add($script:VariableList)

# Raw tab
$script:RawState = New-Object System.Windows.Forms.TextBox
$script:RawState.Multiline = $true
$script:RawState.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$script:RawState.WordWrap = $false
$script:RawState.Dock = [System.Windows.Forms.DockStyle]::Fill
$rawTab.Controls.Add($script:RawState)

@(
  $script:TrainerName, $script:TrainerMoney, $script:TrainerId, $script:TrainerType,
  $script:TrainerOutfit, $script:TrainerLanguage, $script:TrainerPokedex,
  $script:TrainerPokegear, $script:TrainerNuzlocke, $script:Badges,
  $script:SpeciesCombo, $script:ItemCombo, $script:PokeBallCombo, $script:NatureCombo,
  $script:AbilityCombo, $script:StatusCombo, $script:GenderCombo,
  $script:PokeSpecies, $script:PokeNick, $script:PokeLevel, $script:PokeExp,
  $script:PokeHp, $script:PokeStatus, $script:PokeStatusCount, $script:PokeHappiness,
  $script:PokeItem, $script:PokeNatureFlag, $script:PokeAbilityFlag,
  $script:PokeGenderFlag, $script:PokeEggSteps, $script:PokeForm,
  $script:PokePokerus, $script:PokeShiny, $script:PokeOt, $script:PokeOtGender,
  $script:PokeTrainerId, $script:PokePersonalId, $script:PokeLanguage,
  $script:PokeBallUsed, $script:PokeObtainMode, $script:PokeObtainLevel,
  $script:PokeObtainMap, $script:PokeObtainText, $script:PokeHatchedMap,
  $script:PokeMarkings, $script:PokeExpShare, $script:PokeCool, $script:PokeBeauty,
  $script:PokeCute, $script:PokeSmart, $script:PokeTough, $script:PokeSheen,
  $script:PokeTimeReceived, $script:PokeTimeEggHatched, $script:PokeFirstMoves,
  $script:PokeRibbons, $script:BoxName, $script:PCBoxName
) | ForEach-Object { Register-DirtyControl $_ }

foreach ($control in $script:IvNums) { Register-DirtyControl $control }
foreach ($control in $script:EvNums) { Register-DirtyControl $control }
foreach ($control in $script:MoveIds) { Register-DirtyControl $control }
foreach ($control in $script:MoveCombos) { Register-DirtyControl $control }
foreach ($control in $script:MovePps) { Register-DirtyControl $control }
foreach ($control in $script:MovePpUps) { Register-DirtyControl $control }

$tabs.SelectedTab = $pokemonTab
Disable-WheelChangeRecursive $form

Write-AliveFile
$script:AliveTimer = New-Object System.Windows.Forms.Timer
$script:AliveTimer.Interval = 1500
$script:AliveTimer.Add_Tick({ Write-AliveFile })
$script:AliveTimer.Start()

$form.KeyPreview = $true
$form.Add_KeyDown({
  param($sender, $e)
  if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Z) {
    Invoke-HistoryShortcut "undo"
    $e.SuppressKeyPress = $true
    $e.Handled = $true
  } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Y) {
    Invoke-HistoryShortcut "redo"
    $e.SuppressKeyPress = $true
    $e.Handled = $true
  }
})

$form.Add_Shown({
  Refresh-All $true
  Reset-History
  Register-HistoryState "Estado inicial" "Sistema"
})

$form.Add_FormClosing({
  if (!$script:ClosingNotified) {
    $script:ClosingNotified = $true
    [void](Send-EditorCommandImmediate "close_window" @{})
  }
  try {
    if ($null -ne $script:PostCommandTimer) {
      $script:PostCommandTimer.Stop()
      $script:PostCommandTimer.Dispose()
      $script:PostCommandTimer = $null
    }
  } catch {}
  try {
    if ($null -ne $script:HistoryTimer) { $script:HistoryTimer.Stop() }
  } catch {}
  try {
    if ($null -ne $script:AliveTimer) {
      $script:AliveTimer.Stop()
      $script:AliveTimer.Dispose()
      $script:AliveTimer = $null
    }
  } catch {}
  try {
    if (Test-Path -LiteralPath $script:AlivePath) { Remove-Item -LiteralPath $script:AlivePath -Force }
  } catch {}
}.GetNewClosure())

[System.Windows.Forms.Application]::Run($form)
