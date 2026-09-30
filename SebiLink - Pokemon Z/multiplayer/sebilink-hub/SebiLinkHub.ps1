param(
  [switch]$SelfTest,
  [switch]$OpenAi,
  [string]$AiWorkerRequestPath = "",
  [string]$AiConnectionCheckPath = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:BaseDir)) {
  $script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:MultiplayerDir = Split-Path $script:BaseDir -Parent
$script:GameDir = Split-Path $script:MultiplayerDir -Parent
$script:GameExePath = Join-Path $script:GameDir "Game.exe"

function Get-HubAddonVersion {
  try {
    $source = Get-Content -LiteralPath (Join-Path $script:MultiplayerDir "updates\update-source.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($source.version -match '^\d+\.\d+\.\d+$') { return [string]$source.version }
  } catch {}
  return "desconocida"
}
$script:AddonVersion = Get-HubAddonVersion

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

function Copy-SebiLinkLegacyFile {
  param([string]$OldPath, [string]$NewPath)
  try {
    if ([string]::IsNullOrWhiteSpace($OldPath) -or [string]::IsNullOrWhiteSpace($NewPath)) { return }
    if ((Test-Path -LiteralPath $NewPath) -or !(Test-Path -LiteralPath $OldPath)) { return }
    $parent = Split-Path -Parent $NewPath
    if (!(Test-Path -LiteralPath $parent)) {
      [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    Copy-Item -LiteralPath $OldPath -Destination $NewPath -Force
  } catch {
  }
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
if (!(Test-Path -LiteralPath $script:SebiLinkConfigRoot)) {
  [void](New-Item -ItemType Directory -Path $script:SebiLinkConfigRoot -Force)
}
$script:IniPath = Join-Path $script:SebiLinkConfigRoot "sebilink.ini"
$script:RuntimeDir = Join-Path $script:SebiLinkConfigRoot "sebilink-hub\runtime"
$script:CommandPath = Join-Path $script:RuntimeDir "commands.txt"
$script:ResultPath = Join-Path $script:RuntimeDir "last_result.json"
$script:AiBaseDir = Join-Path $script:MultiplayerDir "ai-codex"
$script:AiRuntimeDir = Join-Path $script:SebiLinkConfigRoot "ai-codex\runtime"
$script:AiStatePath = Join-Path $script:AiRuntimeDir "battle_state.json"
$script:AiTeamStatePath = Join-Path $script:AiRuntimeDir "team_state.json"
$script:AiBattleHistoryPath = Join-Path $script:AiRuntimeDir "last_battle_history.json"
$script:AiPvpTeamPath = Join-Path $script:AiRuntimeDir "pvp_ai_team.txt"
$script:AiLastPromptPath = Join-Path $script:AiRuntimeDir "last_prompt.md"
$script:AiLastResponsePath = Join-Path $script:AiRuntimeDir "last_response.md"
$script:AiLastLogPath = Join-Path $script:AiRuntimeDir "last_log.txt"
$script:AiChatStatePath = Join-Path $script:AiRuntimeDir "hub_chat.json"
$script:AiConnectionStatusPath = Join-Path $script:AiRuntimeDir "connection_status.json"
$script:GameIcon = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:AiChatState = $null
$script:AiRequestActive = $false
$script:AiCodexRayChatSupport = $null
$script:AiWorker = $null
$script:AiWarmupWorker = $null
$script:AiPendingRequest = $null
$script:AiPollTimer = $null
$script:AiConnectionCheckProcess = $null
$script:AiConnectionCheckStartedAt = $null
$script:AiConnectionTimer = $null
$script:AiConnectionSummary = "IA: sin comprobar"
$script:AiCurrentActivity = "lista"
$script:AiActionComboReady = $false
$script:ExternalProcesses = New-Object System.Collections.ArrayList
$script:GameProcessId = $null
$script:ClosingBecauseGameClosed = $false

Copy-SebiLinkLegacyFile -OldPath (Join-Path $script:MultiplayerDir "sebilink.ini") -NewPath $script:IniPath
Copy-SebiLinkLegacyRuntime -OldPath (Join-Path $script:BaseDir "runtime") -NewPath $script:RuntimeDir
Copy-SebiLinkLegacyRuntime -OldPath (Join-Path $script:AiBaseDir "runtime") -NewPath $script:AiRuntimeDir

try {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SebiLinkHubNative {
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
} catch {
}

try {
  if (Test-Path -LiteralPath $script:GameExePath) {
    $script:GameIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:GameExePath)
  }
} catch {
  $script:GameIcon = $null
}

function New-HubAction {
  param(
    [string]$Category,
    [string]$Option,
    [string]$Access,
    [string]$Command,
    [string]$Detail
  )
  return [pscustomobject]@{
    Categoria = $Category
    Opcion    = $Option
    Acceso    = $Access
    Comando   = $Command
    Detalle   = $Detail
  }
}

function Get-HubIniValue {
  param(
    [string]$Name,
    [string]$Default
  )
  try {
    if (!(Test-Path -LiteralPath $script:IniPath)) { return $Default }
    foreach ($line in Get-Content -LiteralPath $script:IniPath) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
      $eq = $trimmed.IndexOf("=")
      if ($eq -le 0) { continue }
      $key = $trimmed.Substring(0, $eq).Trim()
      if ($key -ieq $Name) {
        return $trimmed.Substring($eq + 1).Trim()
      }
    }
  } catch {
  }
  return $Default
}

function Set-HubIniValue {
  param(
    [string]$Name,
    [string]$Value
  )
  try {
    $lines = @()
    if (Test-Path -LiteralPath $script:IniPath) {
      $lines = @(Get-Content -LiteralPath $script:IniPath)
    } else {
      $lines = @("# SebiLink runtime settings.")
    }
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = [string]$lines[$i]
      $trimmed = $line.Trim()
      if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
      $eq = $trimmed.IndexOf("=")
      if ($eq -le 0) { continue }
      $key = $trimmed.Substring(0, $eq).Trim()
      if ($key -ieq $Name) {
        $lines[$i] = $Name + "=" + $Value
        $updated = $true
        break
      }
    }
    if (!$updated) {
      $lines += ($Name + "=" + $Value)
    }
    [System.IO.File]::WriteAllLines($script:IniPath, [string[]]$lines, $script:Utf8NoBom)
  } catch {
  }
}

function Get-HubIniInt {
  param(
    [string]$Name,
    [int]$Default
  )
  $value = Get-HubIniValue -Name $Name -Default $Default.ToString()
  $parsed = 0
  if ([int]::TryParse($value, [ref]$parsed)) { return $parsed }
  return $Default
}

function Get-HubIniBool {
  param(
    [string]$Name,
    [bool]$Default
  )
  $value = (Get-HubIniValue -Name $Name -Default ($(if ($Default) { "true" } else { "false" }))).Trim().ToLowerInvariant()
  if ($value -in @("true", "1", "yes", "on", "si")) { return $true }
  if ($value -in @("false", "0", "no", "off")) { return $false }
  return $Default
}

function Get-HubKeyName {
  param(
    [int]$Code,
    [string]$Fallback
  )
  $special = @{
    8 = "Backspace"; 9 = "Tab"; 13 = "Enter"; 16 = "Shift"; 17 = "Ctrl"; 18 = "Alt"; 19 = "Pause"; 20 = "Caps Lock";
    27 = "Esc"; 32 = "Espacio"; 33 = "Pag Arriba"; 34 = "Pag Abajo"; 35 = "Fin"; 36 = "Inicio"; 37 = "Izquierda";
    38 = "Arriba"; 39 = "Derecha"; 40 = "Abajo"; 45 = "Insert"; 46 = "Delete"; 112 = "F1"; 113 = "F2";
    114 = "F3"; 115 = "F4"; 116 = "F5"; 117 = "F6"; 118 = "F7"; 119 = "F8"; 120 = "F9"; 121 = "F10";
    122 = "F11"; 123 = "F12"
  }
  if ($special.ContainsKey($Code)) { return $special[$Code] }
  if ($Code -ge 48 -and $Code -le 57) { return [char]$Code }
  if ($Code -ge 65 -and $Code -le 90) { return [char]$Code }
  if (![string]::IsNullOrWhiteSpace($Fallback)) { return $Fallback }
  return ("0x{0:X2}" -f $Code)
}

$script:DbKeyName = Get-HubKeyName -Code (Get-HubIniInt -Name "extra_control_pokemondb" -Default 114) -Fallback "F3"
$script:WeaknessKeyName = Get-HubKeyName -Code (Get-HubIniInt -Name "extra_control_weakness" -Default 115) -Fallback "F4"
$script:LevelKeyName = Get-HubKeyName -Code (Get-HubIniInt -Name "extra_control_level_sync" -Default 117) -Fallback "F6"

$script:Actions = @(
  New-HubAction "Teclas" "F1 - Controles originales" "F1" "open_original_controls" "Abre la pantalla original para cambiar controles."
  New-HubAction "Teclas" "PokemonDB contextual" $script:DbKeyName "open_pokemondb_context" "En combate abre los rivales visibles; fuera de combate abre el equipo en PokemonDB."
  New-HubAction "Teclas" "Debilidades combate" $script:WeaknessKeyName "toggle_weakness_overlay" "Alterna el overlay de debilidades durante un combate."
  New-HubAction "Teclas" "Objeto registrado" "F5" "use_registered_item" "Solicita el objeto registrado en el mapa."
  New-HubAction "Teclas" "Igualar niveles del equipo" $script:LevelKeyName "equalize_party" "Iguala el equipo al maximo permitido por el level cap."
  New-HubAction "Teclas" "Abrir SebiHeX" "F7" "open_save_editor" "Abre el editor de partida externo."
  New-HubAction "Teclas" "Gestor de partidas" "F8" "open_quick_saves" "Abre la ventana de partidas en la pestana Cargar partida."
  New-HubAction "Teclas" "Repelente max" "F9" "toggle_repel" "Activa o desactiva el repelente maximo."
  New-HubAction "Teclas" "Abrir esta ventana" "F12" "open_hub_window" "Vuelve a pedir la ventana F12 desde el juego."

  New-HubAction "IA" "Consejo IA combate" "F12 > IA" "open_battle_advisor" "Exporta el combate actual y pregunta al Codex del Debian la mejor accion."
  New-HubAction "IA" "Analizar ultimo combate" "F12 > IA" "open_post_battle_analysis" "Explica la partida terminada, aciertos, fallos, turnos y mejoras."
  New-HubAction "IA" "Analizar equipo IA" "F12 > IA" "open_team_analyzer" "Analiza el equipo actual, puntos debiles, estrategias y mejoras de movimientos."
  New-HubAction "IA" "Crear equipo IA" "F12 > IA" "open_team_builder" "Crea un equipo recomendado usando el equipo actual y todas las cajas PC."
  New-HubAction "IA" "Preparar equipo PvP IA" "F12 > IA" "prepare_pvp_ai_team" "Elige y guarda un equipo PvP real segun las reglas multijugador configuradas."

  New-HubAction "Centro Pokemon" "Menu Centro Pokemon" "SebiLink > Centro Pokemon" "open_pokemon_center_menu" "Abre el menu interno con curacion, PC, recordador, tiendas, formas e intercambios."
  New-HubAction "Centro Pokemon" "Curar equipo" "Centro Pokemon" "pokemon_center_heal" "Cura el equipo y rellena los Pokeviales como una enfermera del Centro Pokemon."
  New-HubAction "Centro Pokemon" "Recordar movs" "Centro Pokemon" "pokemon_center_move_reminder" "Abre el recordador de movimientos del NPC de los centros."
  New-HubAction "Centro Pokemon" "Niveles lideres" "Centro Pokemon" "pokemon_center_leader_levels" "Muestra los niveles de lideres del NPC de los centros."
  New-HubAction "Centro Pokemon" "Abrir PC" "Centro Pokemon" "pokemon_center_open_pc" "Abre el PC/Rancho Pokemon como el PC del centro."
  New-HubAction "Centro Pokemon" "Menu de tiendas" "Centro Pokemon" "pokemon_center_shops" "Lista tiendas y mercados indexados en el mundo y abre la tienda elegida."
  New-HubAction "Centro Pokemon" "Cambiar formas" "Centro Pokemon" "pokemon_center_forms" "Abre el transformador exotico/comun para cambiar formas usando las reglas del NPC."
  New-HubAction "Centro Pokemon" "Cambiar habilidades" "Centro Pokemon" "pokemon_center_abilities" "Cambia la habilidad de un Pokemon como el NPC de habilidades, gastando 1 Mini Seta."
  New-HubAction "Centro Pokemon" "Intercambio Pokemon" "Centro Pokemon" "pokemon_center_trades" "Lista intercambios fijos de NPCs como Pokemon dado -> Pokemon recibido."
  New-HubAction "Centro Pokemon" "Intercambio prodigio" "SebiLink" "wonder_trade_daily" "Intercambia un Pokemon por otro aleatorio de calidad parecida."
  New-HubAction "Centro Pokemon" "Intercambio huevo aleatorio" "SebiLink" "random_egg_trade_daily" "Intercambia un Pokemon por un huevo de especie totalmente aleatoria."
  New-HubAction "Centro Pokemon" "Entrenamiento" "SebiLink" "training_battle" "Inicia un combate de prueba contra 6 Pokemon que no hacen dano."
  New-HubAction "Centro Pokemon" "Equipos guardados" "SebiLink" "saved_teams_menu" "Gestiona equipos Showdown guardados para entrenamiento y combates entre jugadores."

  New-HubAction "Trucos" "Menu Trucos" "SebiLink > Trucos" "open_cheats_menu" "Abre el menu completo de trucos."
  New-HubAction "Trucos" "Randomizador" "SebiLink > Randomizador" "open_randomizer_menu" "Configura el randomizador por partida: Region, formas regionales, Pokemon propios de Z, encuentros nuevos cada vez y categorias independientes."
  New-HubAction "Trucos" "Shiny salvajes" "Trucos" "change_shiny" "Cambia el porcentaje shiny salvaje."
  New-HubAction "Trucos" "Mover shiny" "Trucos" "transfer_shiny" "Mueve el shiny entre Pokemon del equipo."
  New-HubAction "Trucos" "Level cap" "Trucos" "change_level_cap" "Cambia el limite temporal de nivel."
  New-HubAction "Trucos" "Repelente max" "F9" "toggle_repel" "Activa o desactiva el repelente maximo."
  New-HubAction "Trucos" "Dar Cenizas Sagradas" "Trucos" "give_ashes" "Entrega la cantidad elegida de Cenizas Sagradas."

  New-HubAction "Sistema" "Menu SebiLink interno" "SebiLink" "open_sebilink_menu" "Abre el menu integrado del juego con Centro Pokemon, multijugador, trucos, guardados y controles."
  New-HubAction "Sistema" "Multijugador integrado" "SebiLink > Multijugador" "open_multiplayer_menu" "Abre dentro del juego la pantalla multijugador personalizada."
  New-HubAction "Sistema" "Colisiones jugadores" "SebiLink" "toggle_collisions" "Activa o desactiva colisiones con jugadores remotos."
  New-HubAction "Sistema" "Guardados automaticos" "SebiLink" "open_backups_menu" "Abre el menu de respaldos automaticos."
  New-HubAction "Sistema" "Crear respaldo ahora" "Guardados" "create_backup" "Crea un respaldo manual de la partida actual con descripcion opcional."
  New-HubAction "Sistema" "Cargar partida" "Guardados" "load_backup" "Abre la ventana de partidas, respaldos y accesos rapidos."
  New-HubAction "Sistema" "Gestor de partidas" "F8" "open_quick_saves" "Abre la ventana de partidas en la pestana Cargar partida."
  New-HubAction "Sistema" "Controles extra" "SebiLink > Controles" "open_extra_controls" "Cambia las teclas de PokemonDB, debilidades e igualar niveles."
  New-HubAction "Sistema" "Buscar actualizaciones" "SebiLink" "check_sebilink_updates" "Busca una nueva version de Pokemon Z en GitHub; pregunta antes de guardar, actualizar y reiniciar."
)

if ($SelfTest) {
  if ($script:Actions.Count -lt 20) {
    throw "La ventana F12 tiene menos acciones de las esperadas."
  }
  foreach ($category in @("Teclas", "IA", "Centro Pokemon", "Trucos", "Sistema")) {
    if (@($script:Actions | Where-Object { $_.Categoria -eq $category }).Count -eq 0) {
      throw ("La ventana F12 no tiene acciones para el grupo {0}." -f $category)
    }
  }
  Write-Host ("SebiLinkHub.ps1 OK - {0} acciones" -f $script:Actions.Count)
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

function Encode-HubValue {
  param([string]$Value)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $out = New-Object System.Text.StringBuilder
  foreach ($byte in $bytes) {
    $ch = [char]$byte
    if (($byte -ge 48 -and $byte -le 57) -or ($byte -ge 65 -and $byte -le 90) -or ($byte -ge 97 -and $byte -le 122) -or $ch -eq "-" -or $ch -eq "_" -or $ch -eq "." ) {
      [void]$out.Append($ch)
    } elseif ($ch -eq " ") {
      [void]$out.Append("+")
    } else {
      [void]$out.Append(("%{0:X2}" -f $byte))
    }
  }
  return $out.ToString()
}

function ConvertTo-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) { return '""' }
  if ($Value -match '^[A-Za-z0-9_@%+=:,./\\-]+$') { return $Value }
  return '"' + ($Value -replace '"', '\"') + '"'
}

function ConvertTo-ShellLiteral {
  param([string]$Value)
  if ($null -eq $Value) { return "''" }
  return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-ExternalProcess {
  param(
    [string]$FileName,
    [string[]]$Arguments,
    [int]$TimeoutMs = 60000
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FileName
  $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " ")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  try {
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  } catch {
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  [void]$script:ExternalProcesses.Add($process)
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  try {
    if (!$process.WaitForExit($TimeoutMs)) {
      try { $process.Kill() } catch {}
      throw "Tiempo agotado ejecutando $FileName."
    }
    try { $process.WaitForExit() } catch {}
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($process.ExitCode -ne 0) {
      $msg = $stderr
      if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $stdout }
      throw ("{0} salio con codigo {1}: {2}" -f $FileName, $process.ExitCode, $msg)
    }
    return $stdout
  } finally {
    try { [void]$script:ExternalProcesses.Remove($process) } catch {}
  }
}

function Get-OpenSshPath {
  param([string]$ExeName)
  $candidates = @()
  if (![string]::IsNullOrWhiteSpace($env:WINDIR)) {
    $candidates += (Join-Path $env:WINDIR ("Sysnative\OpenSSH\" + $ExeName))
    $candidates += (Join-Path $env:WINDIR ("System32\OpenSSH\" + $ExeName))
  }
  foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
      try { return (Resolve-Path -LiteralPath $path).ProviderPath } catch { return $path }
    }
  }
  try {
    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd -and !( [string]::IsNullOrWhiteSpace([string]$cmd.Source))) { return [string]$cmd.Source }
  } catch {
  }
  return $ExeName
}

function Get-WindowsPowerShellPath {
  $candidates = @()
  if (![string]::IsNullOrWhiteSpace($env:WINDIR)) {
    $candidates += (Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe")
    $candidates += (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe")
  }
  try {
    if (![string]::IsNullOrWhiteSpace($PSHOME)) {
      $candidates += (Join-Path $PSHOME "powershell.exe")
    }
  } catch {
  }
  foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
      try { return (Resolve-Path -LiteralPath $path).ProviderPath } catch { return $path }
    }
  }
  return "powershell.exe"
}

function Get-CodeXRayAskScriptPath {
  $candidates = New-Object System.Collections.Generic.List[string]
  try {
    $configured = Get-HubIniValue -Name "codex_ai_bridge_script" -Default ""
    if (![string]::IsNullOrWhiteSpace($configured)) {
      [void]$candidates.Add([Environment]::ExpandEnvironmentVariables($configured))
    }
  } catch {
  }
  try {
    $sebiRoot = Split-Path (Split-Path $script:GameDir -Parent) -Parent
    $reposRoot = Split-Path $sebiRoot -Parent
    [void]$candidates.Add((Join-Path $reposRoot "CodeXRay\scripts\ask-debian-codex.ps1"))
  } catch {
  }
  try {
    if (![string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
      [void]$candidates.Add((Join-Path $env:USERPROFILE "source\repos\CodeXRay\scripts\ask-debian-codex.ps1"))
      [void]$candidates.Add((Join-Path $env:USERPROFILE "Documents\GitHub\CodeXRay\scripts\ask-debian-codex.ps1"))
    }
  } catch {
  }
  try {
    if (![string]::IsNullOrWhiteSpace($env:CODEXRAY_REPO)) {
      [void]$candidates.Add((Join-Path $env:CODEXRAY_REPO "scripts\ask-debian-codex.ps1"))
    }
  } catch {
  }
  foreach ($candidate in $candidates) {
    try {
      if (![string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
      }
    } catch {
    }
  }
  return ""
}

function Get-SebiPokeLinkCodexRaySkillPath {
  $candidates = New-Object System.Collections.Generic.List[string]
  try {
    $configured = Get-HubIniValue -Name "codex_ai_sebilink_skill" -Default ""
    if (![string]::IsNullOrWhiteSpace($configured)) {
      [void]$candidates.Add([Environment]::ExpandEnvironmentVariables($configured))
    }
  } catch {
  }
  try {
    if (![string]::IsNullOrWhiteSpace($env:SEBI_POKELINK_SKILL)) {
      [void]$candidates.Add([Environment]::ExpandEnvironmentVariables($env:SEBI_POKELINK_SKILL))
    }
  } catch {
  }
  try {
    if (![string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
      [void]$candidates.Add((Join-Path $env:USERPROFILE ".codex\skills\sebi-pokelink\SKILL.md"))
    }
  } catch {
  }
  try {
    $profileHome = [Environment]::GetFolderPath("UserProfile")
    if (![string]::IsNullOrWhiteSpace($profileHome)) {
      [void]$candidates.Add((Join-Path $profileHome ".codex\skills\sebi-pokelink\SKILL.md"))
    }
  } catch {
  }
  # Portable gameplay context and prompts shipped with the public mod package.
  [void]$candidates.Add((Join-Path $script:MultiplayerDir "ai-codex\gameplay-ai.md"))
  foreach ($candidate in $candidates) {
    try {
      if (![string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
      }
    } catch {
    }
  }
  return ""
}

function Get-SebiPokeLinkSkillPromptTemplate {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) {
    throw "No se indico el nombre de la plantilla IA."
  }
  $skillPath = Get-SebiPokeLinkCodexRaySkillPath
  if ([string]::IsNullOrWhiteSpace($skillPath)) {
    throw "No se encontro la skill sebi-pokelink con las plantillas IA."
  }
  $content = [System.IO.File]::ReadAllText($skillPath, [System.Text.Encoding]::UTF8)
  $escapedName = [regex]::Escape($Name.Trim())
  $pattern = "(?ms)^<!--\s*SEBILINK_AI_TEMPLATE_BEGIN\s+$escapedName\s*-->\s*\r?\n(?<body>.*?)\r?\n<!--\s*SEBILINK_AI_TEMPLATE_END\s+$escapedName\s*-->"
  $match = [regex]::Match($content, $pattern)
  if (!$match.Success) {
    throw "No se encontro la plantilla IA '$Name' dentro de la skill: $skillPath"
  }
  return $match.Groups["body"].Value.Trim()
}

function Normalize-AiReasoning {
  param([string]$Value)
  $text = $Value.Trim().ToLowerInvariant()
  switch ($text) {
    "" { return "" }
    "auto" { return "" }
    "ninguno" { return "none" }
    "minimo" { return "minimal" }
    "mínimo" { return "minimal" }
    "bajo" { return "low" }
    "medio" { return "medium" }
    "alto" { return "high" }
    "muy alto" { return "xhigh" }
    "extremadamente alto" { return "xhigh" }
    default { return $Value.Trim() }
  }
}

function Get-AiSelectedModel {
  if ($null -eq $script:AiModelCombo) {
    return (Get-HubIniValue -Name "codex_ai_model" -Default "").Trim()
  }
  $value = [string]$script:AiModelCombo.Text
  if ($value -eq "Auto") { return "" }
  return $value.Trim()
}

function Get-AiSelectedReasoning {
  if ($null -eq $script:AiReasoningCombo) {
    $stored = Normalize-AiReasoning (Get-HubIniValue -Name "codex_ai_reasoning" -Default "medium")
    if ($stored -eq "minimal") { return "low" }
    return $stored
  }
  $value = [string]$script:AiReasoningCombo.Text
  if ($value -eq "Auto") { return "" }
  $normalized = Normalize-AiReasoning $value
  if ($normalized -eq "minimal") { return "low" }
  return $normalized
}

function Focus-GameWindow {
  try {
    $proc = Get-Process -Name "Game" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if ($null -ne $proc -and $null -ne ([type]"SebiLinkHubNative")) {
      [void][SebiLinkHubNative]::SetForegroundWindow($proc.MainWindowHandle)
    }
  } catch {
  }
}

function Get-GameProcess {
  try {
    $processes = @(Get-Process -Name "Game" -ErrorAction SilentlyContinue)
    $withWindow = $processes |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if ($null -ne $withWindow) { return $withWindow }

    $gamePath = ""
    try { $gamePath = (Resolve-Path -LiteralPath $script:GameExePath).ProviderPath } catch {}
    if (![string]::IsNullOrWhiteSpace($gamePath)) {
      return $processes |
        Where-Object {
          try { [string]::Compare($_.Path, $gamePath, $true) -eq 0 } catch { $false }
        } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
    }
    return $processes | Sort-Object StartTime -Descending | Select-Object -First 1
  } catch {
    return $null
  }
}

function Stop-ProcessTree {
  param([int]$ProcessId)
  try {
    $children = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ProcessId) -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
      Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
  } catch {
  }
  try {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -ne $process -and !$process.HasExited) {
      $process.Kill()
    }
  } catch {
  }
}

function Stop-ExternalProcesses {
  try {
    foreach ($process in @($script:ExternalProcesses)) {
      try {
        if ($null -ne $process -and !$process.HasExited) {
          Stop-ProcessTree -ProcessId $process.Id
        }
      } catch {
      }
    }
    [void]$script:ExternalProcesses.Clear()
  } catch {
  }
}

function Initialize-GameMonitor {
  try {
    $game = Get-GameProcess
    if ($null -ne $game) { $script:GameProcessId = $game.Id }
  } catch {
  }
}

function Test-GameStillRunning {
  try {
    if ($null -eq $script:GameProcessId) { return $true }
    $process = Get-Process -Id $script:GameProcessId -ErrorAction SilentlyContinue
    return $null -ne $process
  } catch {
    return $false
  }
}

function Write-HubCommand {
  param(
    [string]$Command,
    [string]$Label,
    [hashtable]$Values = @{},
    [bool]$FocusGameAfterSend = $true
  )
  if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
  try {
    if (!(Test-Path -LiteralPath $script:RuntimeDir)) {
      [void](New-Item -ItemType Directory -Path $script:RuntimeDir -Force)
    }
    $seq = [DateTime]::UtcNow.Ticks.ToString()
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($seq)
    $parts.Add($Command)
    $parts.Add(("label={0}" -f (Encode-HubValue $Label)))
    if ($null -ne $Values) {
      foreach ($key in $Values.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$key)) { continue }
        $parts.Add(("{0}={1}" -f $key, (Encode-HubValue ([string]$Values[$key]))))
      }
    }
    $line = ($parts -join "|") + "`n"
    [System.IO.File]::AppendAllText($script:CommandPath, $line, $script:Utf8NoBom)
    if ($FocusGameAfterSend) { Focus-GameWindow }
    return $seq
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      "No se pudo enviar la accion al juego: " + $_.Exception.Message,
      "SebiLink Hub",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return $null
  }
}

function Send-HubCommand {
  param(
    [string]$Command,
    [string]$Label,
    [hashtable]$Values = @{}
  )
  return $null -ne (Write-HubCommand -Command $Command -Label $Label -Values $Values -FocusGameAfterSend $true)
}

function New-AiChatState {
  $title = "Pokemon Z IA " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  return [pscustomobject]@{
    title          = $title
    conversationId = ""
    model          = Get-HubIniValue -Name "codex_ai_model" -Default ""
    reasoning      = Get-HubIniValue -Name "codex_ai_reasoning" -Default "medium"
    messages       = @()
  }
}

function Get-TextMojibakeScore {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return 0 }
  $score = 0
  foreach ($entry in @(
    @([string][char]0x00C3, 5),
    @([string][char]0x00C2, 4),
    @([string][char]0x00C6, 3),
    @([string][char]0x00E2, 5),
    @([string][char]0x20AC, 2),
    @([string][char]0xFFFD, 20)
  )) {
    $pattern = [regex]::Escape([string]$entry[0])
    $score += ([regex]::Matches($Text, $pattern).Count * [int]$entry[1])
  }
  return $score
}

function Repair-TextEncoding {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) { return $Text }
  $best = $Text
  $current = $Text
  $bestScore = Get-TextMojibakeScore -Text $best
  if ($bestScore -le 0) { return $Text }
  $enc1252 = [System.Text.Encoding]::GetEncoding(1252)
  $utf8 = [System.Text.Encoding]::UTF8
  for ($i = 0; $i -lt 5; $i++) {
    try {
      $next = $utf8.GetString($enc1252.GetBytes($current))
    } catch {
      break
    }
    if ($next -eq $current) { break }
    $score = Get-TextMojibakeScore -Text $next
    if ($score -lt $bestScore) {
      $best = $next
      $bestScore = $score
      if ($bestScore -le 0) { break }
    }
    $current = $next
  }
  return $best
}

function Repair-AiChatStateText {
  param([object]$State)
  $changed = $false
  if ($null -eq $State) { return $false }
  try {
    $title = [string]$State.title
    $fixedTitle = Repair-TextEncoding -Text $title
    if ($fixedTitle -ne $title) {
      $State.title = $fixedTitle
      $changed = $true
    }
  } catch {
  }
  try {
    foreach ($message in @($State.messages)) {
      if ($null -eq $message) { continue }
      $content = [string]$message.content
      $fixedContent = Repair-TextEncoding -Text $content
      if ($fixedContent -ne $content) {
        $message.content = $fixedContent
        $changed = $true
      }
    }
  } catch {
  }
  return $changed
}

function Get-AiChatState {
  if ($null -ne $script:AiChatState) { return $script:AiChatState }
  try {
    if (Test-Path -LiteralPath $script:AiChatStatePath) {
      $state = [System.IO.File]::ReadAllText($script:AiChatStatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
      if ($null -ne $state) {
        if ($null -eq $state.messages) { $state | Add-Member -NotePropertyName messages -NotePropertyValue @() -Force }
        $script:AiChatState = $state
        if (Repair-AiChatStateText -State $script:AiChatState) {
          Save-AiChatState
        }
        return $script:AiChatState
      }
    }
  } catch {
  }
  $script:AiChatState = New-AiChatState
  Save-AiChatState
  return $script:AiChatState
}

function Save-AiChatState {
  try {
    if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
      [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
    }
    $json = $script:AiChatState | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($script:AiChatStatePath, $json, $script:Utf8NoBom)
  } catch {
  }
}

function Add-AiMessage {
  param(
    [string]$Role,
    [string]$Content
  )
  $Content = Repair-TextEncoding -Text $Content
  $state = Get-AiChatState
  $messages = @($state.messages)
  $messages += [pscustomobject]@{
    role = $Role
    content = $Content
    time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  }
  $state.messages = $messages
  Save-AiChatState
  Render-AiChat
}

function Format-AiRole {
  param([string]$Role)
  switch ($Role) {
    "user" { return "TU" }
    "assistant" { return "IA" }
    "system" { return "SISTEMA" }
    default { return $Role }
  }
}

function Add-AiChatRun {
  param(
    [System.Windows.Forms.RichTextBox]$Box,
    [string]$Text,
    [System.Drawing.Color]$ForeColor,
    [System.Drawing.Color]$BackColor,
    [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
    [System.Windows.Forms.HorizontalAlignment]$Alignment = [System.Windows.Forms.HorizontalAlignment]::Left
  )
  if ($null -eq $Box -or [string]::IsNullOrEmpty($Text)) { return }
  $font = New-Object System.Drawing.Font($Box.Font.FontFamily, $Box.Font.Size, $Style)
  $Box.SelectionStart = $Box.TextLength
  $Box.SelectionLength = 0
  $Box.SelectionAlignment = $Alignment
  $Box.SelectionFont = $font
  $Box.SelectionColor = $ForeColor
  $Box.SelectionBackColor = $BackColor
  $Box.AppendText($Text)
}

function Render-AiChat {
  if ($null -eq $script:AiChatBox) { return }
  $state = Get-AiChatState
  $box = $script:AiChatBox
  $box.SuspendLayout()
  try {
    $box.Clear()
    foreach ($message in @($state.messages)) {
      $rawRole = [string]$message.role
      $role = Format-AiRole -Role $rawRole
      $time = [string]$message.time
      $content = ([string]$message.content).Trim()
      if ([string]::IsNullOrWhiteSpace($content)) { continue }

      $headerBack = [System.Drawing.Color]::FromArgb(75, 96, 120)
      $bodyBack = [System.Drawing.Color]::FromArgb(241, 244, 248)
      $bodyFore = [System.Drawing.Color]::FromArgb(31, 41, 55)
      $alignment = [System.Windows.Forms.HorizontalAlignment]::Left
      if ($rawRole -eq "user") {
        $headerBack = [System.Drawing.Color]::FromArgb(44, 116, 179)
        $bodyBack = [System.Drawing.Color]::FromArgb(226, 240, 255)
        $alignment = [System.Windows.Forms.HorizontalAlignment]::Right
      } elseif ($rawRole -eq "assistant") {
        $headerBack = [System.Drawing.Color]::FromArgb(35, 139, 88)
        $bodyBack = [System.Drawing.Color]::FromArgb(228, 246, 235)
      } elseif ($rawRole -eq "system") {
        $headerBack = [System.Drawing.Color]::FromArgb(153, 102, 28)
        $bodyBack = [System.Drawing.Color]::FromArgb(255, 244, 214)
      }

      Add-AiChatRun -Box $box -Text (" {0}  {1} `r`n" -f $role, $time) -ForeColor ([System.Drawing.Color]::White) -BackColor $headerBack -Style ([System.Drawing.FontStyle]::Bold) -Alignment $alignment
      Add-AiChatRun -Box $box -Text ($content + "`r`n") -ForeColor $bodyFore -BackColor $bodyBack -Style ([System.Drawing.FontStyle]::Regular) -Alignment $alignment
      Add-AiChatRun -Box $box -Text "`r`n" -ForeColor $bodyFore -BackColor $box.BackColor -Style ([System.Drawing.FontStyle]::Regular) -Alignment ([System.Windows.Forms.HorizontalAlignment]::Left)
    }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionBackColor = $box.BackColor
    $box.ScrollToCaret()
  } finally {
    $box.ResumeLayout()
  }
}

function Set-AiBusy {
  param(
    [bool]$Busy,
    [string]$Status
  )
  $script:AiRequestActive = $Busy
  foreach ($control in @($script:AiSendButton, $script:AiActionCombo, $script:AiBattleButton, $script:AiPostBattleButton, $script:AiTeamAnalysisButton, $script:AiTeamBuilderButton, $script:AiPvpTeamButton, $script:AiNewChatButton, $script:AiInputBox, $script:AiModelCombo, $script:AiReasoningCombo, $script:AiRefreshConnectionButton)) {
    if ($null -ne $control) { $control.Enabled = !$Busy }
  }
  Set-AiActivity -Status $Status
}

function Update-AiActivityLabel {
  if ($null -eq $script:AiConnectionDetailLabel) { return }
  $summary = [string]$script:AiConnectionSummary
  if ([string]::IsNullOrWhiteSpace($summary)) { $summary = "IA" }
  $activity = [string]$script:AiCurrentActivity
  if ([string]::IsNullOrWhiteSpace($activity)) { $activity = "lista" }
  $script:AiConnectionDetailLabel.Text = ("{0} - {1}" -f $summary, $activity)
}

function Set-AiActivity {
  param([string]$Status)
  $text = ([string]$Status).Trim()
  $text = $text -replace "^\s*IA:\s*", ""
  if ([string]::IsNullOrWhiteSpace($text)) { $text = "lista" }
  $script:AiCurrentActivity = $text
  Update-AiActivityLabel
}

function Set-AiPillLabel {
  param(
    [System.Windows.Forms.Label]$Label,
    [string]$Text,
    [string]$Kind
  )
  if ($null -eq $Label) { return }
  $Label.Text = "  " + $Text
  $Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $Label.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $Label.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
  switch ($Kind) {
    "ok" {
      $Label.BackColor = [System.Drawing.Color]::FromArgb(38, 145, 82)
      $Label.ForeColor = [System.Drawing.Color]::White
    }
    "bad" {
      $Label.BackColor = [System.Drawing.Color]::FromArgb(185, 63, 63)
      $Label.ForeColor = [System.Drawing.Color]::White
    }
    "wait" {
      $Label.BackColor = [System.Drawing.Color]::FromArgb(255, 236, 179)
      $Label.ForeColor = [System.Drawing.Color]::FromArgb(80, 60, 15)
    }
    default {
      $Label.BackColor = [System.Drawing.Color]::FromArgb(224, 229, 236)
      $Label.ForeColor = [System.Drawing.Color]::FromArgb(38, 50, 56)
    }
  }
}

function Set-AiConnectionLabelsPending {
  Set-AiPillLabel -Label $script:AiTailscaleStatusLabel -Text "Tailscale: comprobando..." -Kind "wait"
  Set-AiPillLabel -Label $script:AiCodexRayStatusLabel -Text "CodeXRay: comprobando..." -Kind "wait"
  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
  $script:AiConnectionSummary = "Comprobando - " + $user + "@" + $hostName
  Set-AiActivity -Status "comprobando conexion"
}

function Set-AiConnectionLabels {
  param([object]$Status)
  if ($null -eq $Status) {
    Set-AiPillLabel -Label $script:AiTailscaleStatusLabel -Text "Tailscale: desconocido" -Kind "neutral"
    Set-AiPillLabel -Label $script:AiCodexRayStatusLabel -Text "CodeXRay: desconocido" -Kind "neutral"
    $script:AiConnectionSummary = "IA: sin comprobar"
    Update-AiActivityLabel
    return
  }
  Set-AiPillLabel -Label $script:AiTailscaleStatusLabel -Text ([string]$Status.tailscaleText) -Kind ($(if ([bool]$Status.tailscaleOk) { "ok" } else { "bad" }))
  Set-AiPillLabel -Label $script:AiCodexRayStatusLabel -Text ([string]$Status.codexrayText) -Kind ($(if ([bool]$Status.codexrayOk) { "ok" } else { "bad" }))
  $readyText = if ([bool]$Status.ready) { "IA lista" } else { "IA no lista" }
  $script:AiConnectionSummary = ("{0} - {1}" -f $readyText, [string]$Status.target)
  if ([string]::IsNullOrWhiteSpace([string]$script:AiCurrentActivity) -or [string]$script:AiCurrentActivity -eq "comprobando conexion") {
    $script:AiCurrentActivity = "lista"
  }
  Update-AiActivityLabel
}

function Read-AiConnectionStatusFile {
  try {
    if (!(Test-Path -LiteralPath $script:AiConnectionStatusPath)) { return $null }
    return [System.IO.File]::ReadAllText($script:AiConnectionStatusPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Complete-AiConnectionCheck {
  $status = Read-AiConnectionStatusFile
  if ($null -ne $status -and $status.pending -ne $true) {
    Set-AiConnectionLabels -Status $status
    try {
      if ($null -ne $script:AiConnectionCheckProcess) {
        [void]$script:ExternalProcesses.Remove($script:AiConnectionCheckProcess)
        $script:AiConnectionCheckProcess.Dispose()
      }
    } catch {
    }
    $script:AiConnectionCheckProcess = $null
    try { if ($null -ne $script:AiConnectionTimer) { $script:AiConnectionTimer.Stop() } } catch {}
    return $true
  }

  $ended = $false
  try { $ended = ($null -ne $script:AiConnectionCheckProcess -and $script:AiConnectionCheckProcess.HasExited) } catch {}
  if ($ended) {
    Set-AiPillLabel -Label $script:AiTailscaleStatusLabel -Text "Tailscale: error" -Kind "bad"
    Set-AiPillLabel -Label $script:AiCodexRayStatusLabel -Text "CodeXRay: error" -Kind "bad"
    Set-AiActivity -Status "no se pudo comprobar la conexion"
    try {
      [void]$script:ExternalProcesses.Remove($script:AiConnectionCheckProcess)
      $script:AiConnectionCheckProcess.Dispose()
    } catch {
    }
    $script:AiConnectionCheckProcess = $null
    try { if ($null -ne $script:AiConnectionTimer) { $script:AiConnectionTimer.Stop() } } catch {}
    return $true
  }
  return $false
}

function Ensure-AiConnectionTimer {
  if ($null -eq $script:AiConnectionTimer) {
    $script:AiConnectionTimer = New-Object System.Windows.Forms.Timer
    $script:AiConnectionTimer.Interval = 500
    $script:AiConnectionTimer.Add_Tick({ [void](Complete-AiConnectionCheck) })
  }
  $script:AiConnectionTimer.Start()
}

function Start-AiConnectionCheck {
  try {
    if ($null -ne $script:AiConnectionCheckProcess -and !$script:AiConnectionCheckProcess.HasExited) { return }
  } catch {
  }
  try {
    if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
      [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
    }
    $script:AiConnectionCheckStartedAt = Get-Date
    Write-AiConnectionStatusFile -Path $script:AiConnectionStatusPath -Status ([pscustomobject]@{ pending = $true })
    Set-AiConnectionLabelsPending
    $psExe = Get-WindowsPowerShellPath
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = (@(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $scriptPath,
      "-AiConnectionCheckPath", $script:AiConnectionStatusPath
    ) | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $script:AiConnectionCheckProcess = $process
    [void]$script:ExternalProcesses.Add($process)
    Ensure-AiConnectionTimer
  } catch {
    Set-AiPillLabel -Label $script:AiTailscaleStatusLabel -Text "Tailscale: error" -Kind "bad"
    Set-AiPillLabel -Label $script:AiCodexRayStatusLabel -Text "CodeXRay: error" -Kind "bad"
    Set-AiActivity -Status $_.Exception.Message
  }
}

function Read-HubResult {
  try {
    if (!(Test-Path -LiteralPath $script:ResultPath)) { return $null }
    return Get-Content -LiteralPath $script:ResultPath -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Request-AiBattleState {
  if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
  }
  $start = (Get-Date).AddSeconds(-1)
  $seq = Write-HubCommand -Command "export_battle_advisor_state" -Label "Consejo IA combate" -FocusGameAfterSend $false
  if ([string]::IsNullOrWhiteSpace($seq)) {
    throw "No se pudo pedir al juego que exporte el combate."
  }

  $deadline = (Get-Date).AddSeconds(8)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $script:AiStatePath) {
      $item = Get-Item -LiteralPath $script:AiStatePath
      if ($item.LastWriteTime -ge $start -and $item.Length -gt 2) {
        return
      }
    }
    $result = Read-HubResult
    if ($null -ne $result -and [string]$result.seq -eq $seq -and $result.ok -eq $false) {
      throw ([string]$result.message)
    }
    Start-Sleep -Milliseconds 200
  }
  throw "El juego no exporto el combate a tiempo. Mantente dentro del combate y vuelve a pulsar el boton."
}

function New-AiBattlePrompt {
  if (!(Test-Path -LiteralPath $script:AiStatePath)) {
    throw "No hay estado de combate exportado."
  }
  $json = [System.IO.File]::ReadAllText($script:AiStatePath, [System.Text.Encoding]::UTF8).Trim()
  try { [void]($json | ConvertFrom-Json) } catch {}
  $template = Get-SebiPokeLinkSkillPromptTemplate -Name "battle-advice"
  $prompt = $template.Replace("{{GENERATED_AT}}", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $prompt = $prompt.Replace("{{BATTLE_STATE_JSON}}", $json)
  [System.IO.File]::WriteAllText($script:AiLastPromptPath, $prompt, $script:Utf8NoBom)
  return $prompt
}

function Request-AiTeamState {
  param(
    [string]$Label = "Equipo IA"
  )
  if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
  }
  $start = (Get-Date).AddSeconds(-1)
  $seq = Write-HubCommand -Command "export_ai_team_state" -Label $Label -FocusGameAfterSend $false
  if ([string]::IsNullOrWhiteSpace($seq)) {
    throw "No se pudo pedir al juego que exporte el equipo."
  }

  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $script:AiTeamStatePath) {
      $item = Get-Item -LiteralPath $script:AiTeamStatePath
      if ($item.LastWriteTime -ge $start -and $item.Length -gt 2) {
        return
      }
    }
    $result = Read-HubResult
    if ($null -ne $result -and [string]$result.seq -eq $seq -and $result.ok -eq $false) {
      throw ([string]$result.message)
    }
    Start-Sleep -Milliseconds 250
  }
  throw "El juego no exporto el equipo a tiempo. Vuelve a pulsar el boton con la partida cargada."
}

function New-AiTeamPrompt {
  param(
    [string]$TemplateName
  )
  if (!(Test-Path -LiteralPath $script:AiTeamStatePath)) {
    throw "No hay estado de equipo exportado."
  }
  $json = [System.IO.File]::ReadAllText($script:AiTeamStatePath, [System.Text.Encoding]::UTF8).Trim()
  try { [void]($json | ConvertFrom-Json) } catch {}
  $template = Get-SebiPokeLinkSkillPromptTemplate -Name $TemplateName
  $prompt = $template.Replace("{{GENERATED_AT}}", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $prompt = $prompt.Replace("{{TEAM_STATE_JSON}}", $json)
  [System.IO.File]::WriteAllText($script:AiLastPromptPath, $prompt, $script:Utf8NoBom)
  return $prompt
}

function New-AiPostBattlePrompt {
  if (!(Test-Path -LiteralPath $script:AiBattleHistoryPath)) {
    throw "No hay historial de combate terminado. Completa un combate normal o multijugador y vuelve a intentarlo."
  }
  $json = [System.IO.File]::ReadAllText($script:AiBattleHistoryPath, [System.Text.Encoding]::UTF8).Trim()
  try { [void]($json | ConvertFrom-Json) } catch {}
  $template = Get-SebiPokeLinkSkillPromptTemplate -Name "post-battle-analysis"
  $prompt = $template.Replace("{{GENERATED_AT}}", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $prompt = $prompt.Replace("{{BATTLE_HISTORY_JSON}}", $json)
  [System.IO.File]::WriteAllText($script:AiLastPromptPath, $prompt, $script:Utf8NoBom)
  return $prompt
}

function Get-PvpRulesText {
  $source = Get-HubIniValue -Name "pvp_team_source" -Default "current"
  $level = Get-HubIniValue -Name "pvp_level_rule" -Default "current"
  $type = Get-HubIniValue -Name "pvp_monotype" -Default "-1"
  $legends = Get-HubIniValue -Name "pvp_legend_count" -Default "0"
  $ivs = Get-HubIniValue -Name "pvp_iv_rule" -Default "default"
  $evs = Get-HubIniValue -Name "pvp_ev_rule" -Default "default"
  $items = Get-HubIniValue -Name "pvp_item_rule" -Default "default"
  return @"
Origen del equipo: $source
Regla de nivel: $level
ID de monotipo (-1 significa cualquiera, -2 aleatorio): $type
Legendarios exactos (0 a 6): $legends
Regla de IVs: $ivs
Regla de EVs: $evs
Regla de objetos: $items
"@.Trim()
}

function New-AiPvpTeamPrompt {
  if (!(Test-Path -LiteralPath $script:AiTeamStatePath)) {
    throw "No hay estado de equipo exportado."
  }
  $json = [System.IO.File]::ReadAllText($script:AiTeamStatePath, [System.Text.Encoding]::UTF8).Trim()
  try { [void]($json | ConvertFrom-Json) } catch {}
  $template = Get-SebiPokeLinkSkillPromptTemplate -Name "pvp-team-builder"
  $prompt = $template.Replace("{{GENERATED_AT}}", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $prompt = $prompt.Replace("{{PVP_RULES_TEXT}}", (Get-PvpRulesText))
  $prompt = $prompt.Replace("{{TEAM_STATE_JSON}}", $json)
  [System.IO.File]::WriteAllText($script:AiLastPromptPath, $prompt, $script:Utf8NoBom)
  return $prompt
}

function Save-AiPvpTeamSelection {
  param([string]$Text)
  $match = [regex]::Match($Text, "(?ms)SEBILINK_PVP_TEAM:\s*(?<body>.*?)\s*SEBILINK_PVP_TEAM_END")
  if (!$match.Success) {
    throw "La IA no devolvio el bloque SEBILINK_PVP_TEAM requerido."
  }
  $refs = New-Object System.Collections.Generic.List[string]
  foreach ($rawLine in ($match.Groups["body"].Value -split "\r?\n")) {
    $line = $rawLine.Trim()
    $line = $line -replace "^[-*]\s*", ""
    if ($line -match "^party\|(\d+)$") {
      $refs.Add(("party|{0}" -f [int]$Matches[1]))
    } elseif ($line -match "^box\|(\d+)\|(\d+)$") {
      $refs.Add(("box|{0}|{1}" -f [int]$Matches[1], [int]$Matches[2]))
    }
  }
  $unique = @($refs | Select-Object -Unique)
  if ($unique.Count -ne 6) {
    throw ("La IA debe devolver exactamente 6 referencias Pokemon unicas; devolvio {0}." -f $unique.Count)
  }
  if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
  }
  $lines = @(
    "# Equipo PvP elegido por la IA. Referencias de solo lectura al equipo y PC.",
    "# Generado: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  ) + $unique
  [System.IO.File]::WriteAllLines($script:AiPvpTeamPath, $lines, $script:Utf8NoBom)
  return $unique.Count
}

function Test-AiCodexRayChatSupport {
  if ($null -ne $script:AiCodexRayChatSupport) { return [bool]$script:AiCodexRayChatSupport }
  try {
    $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
    $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
    $ssh = Get-OpenSshPath "ssh.exe"
    $sshBase = @(
      "-o", "BatchMode=yes",
      "-o", "ConnectTimeout=10",
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=NUL",
      "-o", "LogLevel=ERROR"
    )
    $target = $user + "@" + $hostName
    [void](Invoke-ExternalProcess -FileName $ssh -Arguments ($sshBase + @($target, "codexray chat list >/dev/null 2>&1")) -TimeoutMs 15000)
    $script:AiCodexRayChatSupport = $true
  } catch {
    $script:AiCodexRayChatSupport = $false
  }
  return [bool]$script:AiCodexRayChatSupport
}

function Get-PingExecutablePath {
  $candidates = @()
  if (![string]::IsNullOrWhiteSpace($env:WINDIR)) {
    $candidates += (Join-Path $env:WINDIR "System32\ping.exe")
    $candidates += (Join-Path $env:WINDIR "Sysnative\ping.exe")
  }
  try {
    $cmd = Get-Command "ping.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd -and ![string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
      $candidates += [string]$cmd.Source
    }
  } catch {
  }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      try { return (Resolve-Path -LiteralPath $candidate).ProviderPath } catch { return $candidate }
    }
  }
  return "ping.exe"
}

function Test-AiTailscaleConnection {
  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $detail = ""
  try {
    $tailscale = Get-Command "tailscale.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $tailscale -and ![string]::IsNullOrWhiteSpace([string]$tailscale.Source)) {
      $raw = Invoke-ExternalProcess -FileName ([string]$tailscale.Source) -Arguments @("status", "--json") -TimeoutMs 5000
      $json = $raw | ConvertFrom-Json
      $backend = [string]$json.BackendState
      $online = $false
      try { $online = [bool]$json.Self.Online } catch {}
      if ($backend -eq "Running" -and ($online -or $raw -match '"Online"\s*:\s*true')) {
        return [pscustomobject]@{ ok = $true; text = "Tailscale: conectado"; detail = "tailscale.exe activo" }
      }
      $detail = ("tailscale.exe: {0}" -f ($(if ([string]::IsNullOrWhiteSpace($backend)) { "sin estado" } else { $backend })))
    }
  } catch {
    $detail = "tailscale.exe no confirma estado"
  }

  try {
    $ping = Get-PingExecutablePath
    [void](Invoke-ExternalProcess -FileName $ping -Arguments @("-n", "1", "-w", "1200", $hostName) -TimeoutMs 2500)
    return [pscustomobject]@{ ok = $true; text = "Tailscale: ruta OK"; detail = ("host {0} responde" -f $hostName) }
  } catch {
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
  }
  return [pscustomobject]@{ ok = $false; text = "Tailscale: sin ruta"; detail = $detail }
}

function Test-AiCodeXRayConnection {
  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
  $ssh = Get-OpenSshPath "ssh.exe"
  $sshBase = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=8",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=NUL",
    "-o", "LogLevel=ERROR"
  )
  $target = $user + "@" + $hostName
  try {
    $raw = Invoke-ExternalProcess -FileName $ssh -Arguments ($sshBase + @($target, "command -v codexray >/dev/null 2>&1 && codexray chat list >/dev/null 2>&1 && printf CODEXRAY_OK")) -TimeoutMs 12000
    if ($raw -match "CODEXRAY_OK") {
      return [pscustomobject]@{ ok = $true; text = "CodeXRay: conectado"; detail = $target }
    }
    return [pscustomobject]@{ ok = $false; text = "CodeXRay: sin respuesta"; detail = $target }
  } catch {
    return [pscustomobject]@{ ok = $false; text = "CodeXRay: error"; detail = $_.Exception.Message }
  }
}

function Get-AiConnectionStatus {
  $tailscale = Test-AiTailscaleConnection
  $codexray = Test-AiCodeXRayConnection
  if (!$tailscale.ok -and $codexray.ok) {
    $tailscale = [pscustomobject]@{
      ok = $true
      text = "Tailscale: ruta OK"
      detail = "SSH a CodeXRay funciona"
    }
  }
  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
  return [pscustomobject]@{
    pending = $false
    tailscaleOk = [bool]$tailscale.ok
    tailscaleText = [string]$tailscale.text
    tailscaleDetail = [string]$tailscale.detail
    codexrayOk = [bool]$codexray.ok
    codexrayText = [string]$codexray.text
    codexrayDetail = [string]$codexray.detail
    ready = ([bool]$tailscale.ok -and [bool]$codexray.ok)
    target = ($user + "@" + $hostName)
    checkedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  }
}

function Write-AiConnectionStatusFile {
  param(
    [string]$Path,
    [object]$Status
  )
  try {
    $parent = Split-Path -Parent $Path
    if (![string]::IsNullOrWhiteSpace($parent) -and !(Test-Path -LiteralPath $parent)) {
      [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [System.IO.File]::WriteAllText($Path, ($Status | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
  } catch {
  }
}

if (![string]::IsNullOrWhiteSpace($AiConnectionCheckPath)) {
  try {
    Write-AiConnectionStatusFile -Path $AiConnectionCheckPath -Status (Get-AiConnectionStatus)
    exit 0
  } catch {
    Write-AiConnectionStatusFile -Path $AiConnectionCheckPath -Status ([pscustomobject]@{
      pending = $false
      tailscaleOk = $false
      tailscaleText = "Tailscale: error"
      tailscaleDetail = $_.Exception.Message
      codexrayOk = $false
      codexrayText = "CodeXRay: error"
      codexrayDetail = $_.Exception.Message
      ready = $false
      target = ""
      checkedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    })
    exit 1
  }
}

function Get-AiTimeoutMs {
  $timeoutSeconds = Get-HubIniInt -Name "codex_ai_timeout_seconds" -Default 180
  if ($timeoutSeconds -lt 30) { $timeoutSeconds = 30 }
  if ($timeoutSeconds -gt 1800) { $timeoutSeconds = 1800 }
  return ($timeoutSeconds * 1000)
}

function New-AiFallbackPrompt {
  param([string]$CurrentPrompt)
  $state = Get-AiChatState
  $builder = New-Object System.Text.StringBuilder
  [void]$builder.AppendLine("Continua esta conversacion de ayuda para Pokemon Z. Responde en espanol, directo y sin markdown pesado.")
  [void]$builder.AppendLine()
  foreach ($message in @($state.messages)) {
    $role = if ([string]$message.role -eq "assistant") { "IA" } else { "Usuario" }
    [void]$builder.AppendLine(("### {0}" -f $role))
    [void]$builder.AppendLine(([string]$message.content).Trim())
    [void]$builder.AppendLine()
  }
  $last = @($state.messages) | Select-Object -Last 1
  if ($null -eq $last -or ([string]$last.content).Trim() -ne $CurrentPrompt.Trim()) {
    [void]$builder.AppendLine("### Usuario")
    [void]$builder.AppendLine($CurrentPrompt.Trim())
  }
  return $builder.ToString()
}

function Add-AiSenderReadOnlyContext {
  param([string]$Prompt)
  $teamStateInfo = "No exportado todavia."
  try {
    if (Test-Path -LiteralPath $script:AiTeamStatePath) {
      $item = Get-Item -LiteralPath $script:AiTeamStatePath
      $teamStateInfo = ("{0} bytes, actualizado {1}" -f $item.Length, $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }
  } catch {
  }
  $saveStatePath = Join-Path $script:SebiLinkConfigRoot "save-editor\runtime\state.json"
  $saveDataPath = Join-Path $script:SebiLinkConfigRoot "save-editor\runtime\data.json"
  $saveIndexPath = Join-Path $script:SebiLinkConfigRoot "save-manager\runtime\index.json"
  $pbsPath = Join-Path $script:GameDir "PBS"
  $sebiSkillPath = Get-SebiPokeLinkCodexRaySkillPath
  if ([string]::IsNullOrWhiteSpace($sebiSkillPath)) {
    $sebiSkillPath = "no encontrado en este PC"
  }
  return @"
Contexto SebiLink para CodeXRay:
  - Estas ayudando dentro de Pokemon Z de ericlostie.
  - El prompt viene del PC Windows del jugador y CodeXRay puede usar sender tools para inspeccionar ese PC.
  - El puente sincroniza y activa el skill CodeXRay 'sebi-pokelink' en cada mensaje desde: $sebiSkillPath.
  - Para preguntas normales de juego no empieces leyendo la documentacion viva del proyecto: inspecciona primero los snapshots runtime que correspondan y responde a la pregunta del jugador.
  - Para datos de partida usa solo lectura. No escribas, borres ni modifiques saves, runtimes, PBS ni archivos del juego.
  - Si necesitas PowerShell, usa comandos de lectura/consulta como Get-Content, Get-ChildItem, Select-String, ConvertFrom-Json, Measure-Object o consultas CIM. No uses Set-Content, Add-Content, Remove-Item, Move-Item, Copy-Item, comandos de guardado ni scripts que cambien la partida.
- Si el usuario pide tocar archivos o ejecutar algo que modifique el PC, pide confirmacion explicita primero. Para consejos Pokemon normales, lee datos y responde.

Rutas utiles en este PC Windows:
- Juego: $script:GameDir
- Config SebiLink del jugador: $script:SebiLinkConfigRoot
- Snapshot IA de equipo/cajas: $script:AiTeamStatePath ($teamStateInfo)
- Snapshot IA de combate: $script:AiStatePath
- Historial IA del ultimo combate: $script:AiBattleHistoryPath
- Referencias del equipo PvP elegido por IA: $script:AiPvpTeamPath
- Snapshot vivo de SebiHeX/F7: $saveStatePath
- Datos base de SebiHeX/F7: $saveDataPath
- Indice de partidas F8: $saveIndexPath
- PBS del juego: $pbsPath

Cuando el usuario pregunte por equipo, Pokemon capturados, movimientos, cajas PC, objetos, partida, scripts, NPCs, eventos, mapas, PBS o codigo del juego, usa las herramientas sender de CodeXRay para inspeccionar este PC antes de responder. Lee primero 'team_state.json' si existe para preguntas de equipo/partida. En 'team_state.json', para Pokemon del equipo usa 'nickname', 'speciesName' y 'level'; no uses 'species' como nombre porque es un id numerico. Si necesitas datos base de movimientos/especies/objetos, lee 'data.json' o PBS. Si necesitas buscar NPCs/eventos/scripts, lista y lee archivos del juego en solo lectura. No digas que no tienes herramientas: pide una herramienta sender. Responde en espanol, directo y util para jugar, con ruta y linea cuando el usuario pida ubicacion.

Prompt del usuario o plantilla:
$Prompt
"@
}

function New-AiCustomPrompt {
  param([string]$UserPrompt)
  return @"
El usuario ha escrito un mensaje libre en la pestana IA de SebiLink.
Interpreta la pregunta con el contexto de Pokemon Z y usa datos vivos de la partida cuando hagan falta.

Mensaje del usuario:
$UserPrompt
"@
}

function Test-AiCustomNeedsTeamExport {
  param([string]$Text)
  return ($Text -match "(?i)pokemon|pok[eé]mon|equipo|caja|pc|movim|ataque|captur|partida|save|objeto|habilidad|naturaleza|nivel|estrateg")
}

function Parse-AiRemoteResponse {
  param([string]$Text)
  $meta = @{}
  $response = $Text
  $pattern = "(?s)__SEBILINK_META_BEGIN__\s*(.*?)\s*__SEBILINK_META_END__"
  $match = [regex]::Match($Text, $pattern)
  if ($match.Success) {
    $response = $Text.Substring(0, $match.Index).Trim()
    foreach ($line in ($match.Groups[1].Value -split "`n")) {
      $parts = $line.Trim() -split "=", 2
      if ($parts.Count -eq 2) { $meta[$parts[0]] = $parts[1] }
    }
  }
  return [pscustomobject]@{
    Response = $response.Trim()
    Meta = $meta
  }
}

function Invoke-DebianAiChat {
  param(
    [string]$Prompt,
    [bool]$NewConversation,
    [string]$Model,
    [string]$Reasoning
  )
  if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
  }
  $state = Get-AiChatState
  $model = $Model.Trim()
  $reasoning = Normalize-AiReasoning $Reasoning
  if ($reasoning -eq "minimal") { $reasoning = "low" }
  $state.model = $model
  $state.reasoning = $reasoning
  Save-AiChatState
  Set-HubIniValue -Name "codex_ai_model" -Value $model
  Set-HubIniValue -Name "codex_ai_reasoning" -Value $reasoning

  $bridgeScript = Get-CodeXRayAskScriptPath
  $promptToSend = Add-AiSenderReadOnlyContext -Prompt $Prompt
  if ([string]::IsNullOrWhiteSpace($bridgeScript) -and !(Test-AiCodexRayChatSupport)) {
    $promptToSend = New-AiFallbackPrompt -CurrentPrompt $Prompt
  }
  [System.IO.File]::WriteAllText($script:AiLastPromptPath, $promptToSend, $script:Utf8NoBom)

  if (![string]::IsNullOrWhiteSpace($bridgeScript)) {
    $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
    $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
    $conversationId = [string]$state.conversationId
    if ($NewConversation -or [string]::IsNullOrWhiteSpace($conversationId)) {
      try {
        $createdId = Invoke-DebianCreateAiConversation -Title ([string]$state.title) -Model $model -Reasoning $reasoning
        if (![string]::IsNullOrWhiteSpace($createdId)) {
          $state.conversationId = $createdId
          $conversationId = $createdId
          Save-AiChatState
        }
      } catch {
      }
    }

    $psExe = Get-WindowsPowerShellPath
    $bridgeArgs = @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $bridgeScript,
      "-HostName", $hostName,
      "-User", $user,
      "-PromptFile", $script:AiLastPromptPath,
      "-TargetDevice", "Sender",
      "-ReadOnlySenderTools"
    )
    $sebiSkillPath = Get-SebiPokeLinkCodexRaySkillPath
    if (![string]::IsNullOrWhiteSpace($sebiSkillPath)) {
      $bridgeArgs += @("-Skill", $sebiSkillPath)
    }
    if (![string]::IsNullOrWhiteSpace($model)) {
      $bridgeArgs += @("-Model", $model)
    }
    if (![string]::IsNullOrWhiteSpace($reasoning)) {
      $bridgeArgs += @("-Reasoning", $reasoning)
    }
    if (![string]::IsNullOrWhiteSpace($conversationId)) {
      $bridgeArgs += @("-ConversationId", $conversationId)
    } elseif ($NewConversation -or [string]::IsNullOrWhiteSpace([string]$state.conversationId)) {
      $bridgeArgs += @("-NewConversation", "-Title", ([string]$state.title))
    }

    $rawBridge = Invoke-ExternalProcess -FileName $psExe -Arguments $bridgeArgs -TimeoutMs (Get-AiTimeoutMs)
    $response = Repair-TextEncoding -Text ($rawBridge.Trim())
    [System.IO.File]::WriteAllText($script:AiLastResponsePath, $response, $script:Utf8NoBom)
    [System.IO.File]::WriteAllText($script:AiLastLogPath, "Host=$user@$hostName`r`nBridgeScript=$bridgeScript`r`nMode=codexray-sender`r`nPrompt=$script:AiLastPromptPath`r`n", $script:Utf8NoBom)
    return $response
  }

  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
  $remoteDir = Get-HubIniValue -Name "codex_ai_remote_dir" -Default "/root/codexray-requests"
  $remoteWorkDir = Get-HubIniValue -Name "codex_ai_workdir" -Default "/root"
  $ssh = Get-OpenSshPath "ssh.exe"
  $scp = Get-OpenSshPath "scp.exe"
  $target = $user + "@" + $hostName
  $requestId = "pokemon_z_chat_" + (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
  $remotePrompt = ($remoteDir.TrimEnd("/") + "/" + $requestId + ".prompt.md")
  $remoteOutput = ($remoteDir.TrimEnd("/") + "/" + $requestId + ".output.md")
  $remoteLog = ($remoteDir.TrimEnd("/") + "/" + $requestId + ".log.txt")
  $remoteScript = ($remoteDir.TrimEnd("/") + "/" + $requestId + ".run.sh")
  $localScript = Join-Path $script:AiRuntimeDir ($requestId + ".run.sh")
  $conversationId = [string]$state.conversationId
  $forceNew = if ($NewConversation -or [string]::IsNullOrWhiteSpace($conversationId)) { "1" } else { "0" }
  $title = if ([string]::IsNullOrWhiteSpace([string]$state.title)) { "Pokemon Z IA" } else { [string]$state.title }

  $sshBase = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=NUL",
    "-o", "LogLevel=ERROR"
  )

  Invoke-ExternalProcess -FileName $ssh -Arguments ($sshBase + @($target, "mkdir -p " + (ConvertTo-ShellLiteral $remoteDir))) -TimeoutMs 15000 | Out-Null

  $modelArgCodexRay = ""
  $modelArgRaw = ""
  if (![string]::IsNullOrWhiteSpace($model)) {
    $modelArgCodexRay = " --model " + (ConvertTo-ShellLiteral $model)
    $modelArgRaw = " --model " + (ConvertTo-ShellLiteral $model)
  }
  $reasoningArgCodexRay = ""
  $reasoningArgRaw = ""
  if (![string]::IsNullOrWhiteSpace($reasoning)) {
    $reasoningArgCodexRay = " --reasoning " + (ConvertTo-ShellLiteral $reasoning)
    $normalizedReasoning = Normalize-AiReasoning -Value $reasoning
    if (![string]::IsNullOrWhiteSpace($normalizedReasoning)) {
      $reasoningArgRaw = " --config " + (ConvertTo-ShellLiteral ("model_reasoning_effort=" + $normalizedReasoning))
    }
  }

  $remotePromptLine = "remote_prompt=" + (ConvertTo-ShellLiteral $remotePrompt)
  $remoteOutputLine = "remote_output=" + (ConvertTo-ShellLiteral $remoteOutput)
  $remoteLogLine = "remote_log=" + (ConvertTo-ShellLiteral $remoteLog)
  $conversationLine = "conversation_id=" + (ConvertTo-ShellLiteral $conversationId)
  $forceNewLine = "force_new=" + (ConvertTo-ShellLiteral $forceNew)
  $titleLine = "title=" + (ConvertTo-ShellLiteral $title)
  $cdDirLine = "cd_dir=" + (ConvertTo-ShellLiteral $remoteWorkDir)
  $codexRayNewLine = "      create_out=`$(codexray chat new --title `"`$title`" --cd `"`$cd_dir`"" + $modelArgCodexRay + $reasoningArgCodexRay + " 2>>`$remote_log)"
  $codexRayAskLine = "      if codexray chat ask --conversation `"`$conversation_id`" --file `"`$remote_prompt`" --cd `"`$cd_dir`"" + $modelArgCodexRay + $reasoningArgCodexRay + " > `"`$remote_output`" 2>>`"`$remote_log`"; then"
  $rawCodexLine = "codex exec --skip-git-repo-check --cd `"`$cd_dir`"" + $modelArgRaw + $reasoningArgRaw + " -o `"`$remote_output`" - < `"`$remote_prompt`" > `"`$remote_log`" 2>&1"

  $remoteLines = @(
    "set -e",
    "umask 077",
    $remotePromptLine,
    $remoteOutputLine,
    $remoteLogLine,
    $conversationLine,
    $forceNewLine,
    $titleLine,
    $cdDirLine,
    "mode=raw",
    "chmod u+rw `"`$remote_prompt`" 2>/dev/null || true",
    "if [ ! -r `"`$remote_prompt`" ]; then echo `"Prompt no legible: `$remote_prompt`" >&2; exit 126; fi",
    "if command -v codexray >/dev/null 2>&1; then",
    "  set +e",
    "  codexray chat list >/dev/null 2>>`$remote_log",
    "  support=`$?",
    "  set -e",
    "  if [ `$support -eq 0 ]; then",
    "    mode=codexray",
    "    if [ `$force_new = '1' ] || [ -z `"`$conversation_id`" ]; then",
    $codexRayNewLine,
    "      conversation_id=`$(printf '%s\n' `"`$create_out`" | awk -F': ' '/^Id:/ {print `$2; exit}')",
    "    fi",
    "    if [ -n `"`$conversation_id`" ]; then",
    $codexRayAskLine,
    "        cat `"`$remote_output`"",
    "        printf '\n__SEBILINK_META_BEGIN__\nconversation_id=%s\nmode=codexray\n__SEBILINK_META_END__\n' `"`$conversation_id`"",
    "        exit 0",
    "      fi",
    "    fi",
    "  fi",
    "fi",
    $rawCodexLine,
    "cat `"`$remote_output`"",
    "printf '\n__SEBILINK_META_BEGIN__\nconversation_id=%s\nmode=raw\n__SEBILINK_META_END__\n' `"`$conversation_id`""
  )
  $remoteCommand = ($remoteLines -join "`n")
  [System.IO.File]::WriteAllText($localScript, ($remoteCommand + "`n"), $script:Utf8NoBom)
  try {
    Invoke-ExternalProcess -FileName $scp -Arguments ($sshBase + @($script:AiLastPromptPath, ($target + ":" + $remotePrompt))) -TimeoutMs 30000 | Out-Null
    Invoke-ExternalProcess -FileName $scp -Arguments ($sshBase + @($localScript, ($target + ":" + $remoteScript))) -TimeoutMs 30000 | Out-Null
    $remoteLogLiteral = ConvertTo-ShellLiteral $remoteLog
    $remoteRunner = "chmod 600 " + (ConvertTo-ShellLiteral $remotePrompt) + " " + (ConvertTo-ShellLiteral $remoteScript) + " 2>/dev/null || true; bash " + (ConvertTo-ShellLiteral $remoteScript) + "; rc=`$?; if [ `$rc -ne 0 ]; then echo 'Fallo remoto IA. Ultimas lineas del log:' >&2; if [ -r " + $remoteLogLiteral + " ]; then tail -80 " + $remoteLogLiteral + " >&2; fi; exit `$rc; fi"
    $raw = Invoke-ExternalProcess -FileName $ssh -Arguments ($sshBase + @($target, $remoteRunner)) -TimeoutMs (Get-AiTimeoutMs)
  } finally {
    try { Remove-Item -LiteralPath $localScript -Force -ErrorAction SilentlyContinue } catch {}
  }
  $parsed = Parse-AiRemoteResponse -Text $raw
  $parsed.Response = Repair-TextEncoding -Text ([string]$parsed.Response)
  [System.IO.File]::WriteAllText($script:AiLastResponsePath, $parsed.Response, $script:Utf8NoBom)
  [System.IO.File]::WriteAllText($script:AiLastLogPath, "Host=$target`r`nRemotePrompt=$remotePrompt`r`nRemoteOutput=$remoteOutput`r`nMode=$($parsed.Meta["mode"])`r`n", $script:Utf8NoBom)
  if ($parsed.Meta.ContainsKey("conversation_id") -and ![string]::IsNullOrWhiteSpace($parsed.Meta["conversation_id"])) {
    $state.conversationId = $parsed.Meta["conversation_id"]
    Save-AiChatState
  }
  return $parsed.Response
}

function Write-AiWorkerResult {
  param(
    [string]$Path,
    [bool]$Ok,
    [string]$Response = "",
    [string]$ErrorMessage = ""
  )
  try {
    $payload = [pscustomobject]@{
      ok = $Ok
      response = $Response
      error = $ErrorMessage
      completedAt = (Get-Date).ToString("o")
    }
    $json = $payload | ConvertTo-Json -Depth 10
    $tempPath = $Path + ".tmp"
    [System.IO.File]::WriteAllText($tempPath, $json, $script:Utf8NoBom)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
  } catch {
  }
}

function Invoke-AiWorkerRequestFile {
  param([string]$RequestPath)
  $responsePath = ""
  try {
    if (!(Test-Path -LiteralPath $RequestPath)) {
      throw "No se encontro la peticion IA: $RequestPath"
    }
    $request = [System.IO.File]::ReadAllText($RequestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $responsePath = [string]$request.responsePath
    if ([string]::IsNullOrWhiteSpace($responsePath)) {
      $responsePath = [System.IO.Path]::ChangeExtension($RequestPath, ".response.json")
    }
    $response = Invoke-DebianAiChat `
      -Prompt ([string]$request.prompt) `
      -NewConversation ([bool]$request.newConversation) `
      -Model ([string]$request.model) `
      -Reasoning ([string]$request.reasoning)
    Write-AiWorkerResult -Path $responsePath -Ok $true -Response $response
  } catch {
    if ([string]::IsNullOrWhiteSpace($responsePath)) {
      $responsePath = [System.IO.Path]::ChangeExtension($RequestPath, ".response.json")
    }
    Write-AiWorkerResult -Path $responsePath -Ok $false -ErrorMessage $_.Exception.Message
  } finally {
    Stop-ExternalProcesses
  }
}

if (![string]::IsNullOrWhiteSpace($AiWorkerRequestPath)) {
  Invoke-AiWorkerRequestFile -RequestPath $AiWorkerRequestPath
  exit
}

function Invoke-DebianCreateAiConversation {
  param(
    [string]$Title,
    [string]$Model,
    [string]$Reasoning
  )
  if (!(Test-AiCodexRayChatSupport)) { return "" }
  $hostName = Get-HubIniValue -Name "codex_ai_host" -Default "127.0.0.1"
  $user = Get-HubIniValue -Name "codex_ai_user" -Default "root"
  $remoteWorkDir = Get-HubIniValue -Name "codex_ai_workdir" -Default "/root"
  $ssh = Get-OpenSshPath "ssh.exe"
  $target = $user + "@" + $hostName
  $sshBase = @(
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=NUL",
    "-o", "LogLevel=ERROR"
  )
  $modelArg = ""
  if (![string]::IsNullOrWhiteSpace($Model)) { $modelArg = " --model " + (ConvertTo-ShellLiteral $Model) }
  $reasoningArg = ""
  if (![string]::IsNullOrWhiteSpace($Reasoning)) { $reasoningArg = " --reasoning " + (ConvertTo-ShellLiteral $Reasoning) }
  $remoteCommand = "codexray chat new --title " + (ConvertTo-ShellLiteral $Title) + " --cd " + (ConvertTo-ShellLiteral $remoteWorkDir) + $modelArg + $reasoningArg
  $output = Invoke-ExternalProcess -FileName $ssh -Arguments ($sshBase + @($target, $remoteCommand)) -TimeoutMs 30000
  foreach ($line in ($output -split "`n")) {
    if ($line -match "^Id:\s*(.+)$") { return $Matches[1].Trim() }
  }
  return ""
}

function Invoke-AiResponseHandler {
  param(
    [string]$Name,
    [string]$Response
  )
  if ([string]::IsNullOrWhiteSpace($Name)) { return }
  switch ($Name) {
    "save_pvp_team" {
      $count = Save-AiPvpTeamSelection -Text $Response
      Add-AiMessage -Role "system" -Content ("Equipo PvP IA guardado con {0} Pokemon. Ya puede usarse desde la configuracion multijugador." -f $count)
    }
  }
}

function Complete-AiPendingRequest {
  param(
    [bool]$ForceCancel = $false,
    [string]$CancelMessage = ""
  )
  $pending = $script:AiPendingRequest
  if ($null -eq $pending) { return $true }

  if ($ForceCancel) {
    try {
      if ($null -ne $pending.Process -and !$pending.Process.HasExited) {
        Stop-ProcessTree -ProcessId $pending.Process.Id
      }
    } catch {
    }
    Add-AiMessage -Role "system" -Content $CancelMessage
    Set-AiBusy -Busy $false -Status "IA: cancelada."
    $script:AiPendingRequest = $null
    return $true
  }

  if (Test-Path -LiteralPath $pending.ResponsePath) {
    try {
      $result = [System.IO.File]::ReadAllText($pending.ResponsePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
      if ($result.ok -eq $true) {
        Add-AiMessage -Role "assistant" -Content ([string]$result.response)
        try {
          Invoke-AiResponseHandler -Name ([string]$pending.ResponseHandler) -Response ([string]$result.response)
          Set-AiBusy -Busy $false -Status "IA: respuesta recibida."
        } catch {
          Add-AiMessage -Role "system" -Content ("La respuesta IA se recibio, pero no se pudo aplicar: " + $_.Exception.Message)
          Set-AiBusy -Busy $false -Status "IA: respuesta recibida con aviso."
        }
      } else {
        Add-AiMessage -Role "system" -Content ("Error consultando la IA: " + [string]$result.error)
        Set-AiBusy -Busy $false -Status "IA: error."
      }
    } catch {
      Add-AiMessage -Role "system" -Content ("Error leyendo la respuesta IA: " + $_.Exception.Message)
      Set-AiBusy -Busy $false -Status "IA: error."
    }
    try { [void]$script:ExternalProcesses.Remove($pending.Process) } catch {}
    try { if ($null -ne $pending.Process) { $pending.Process.Dispose() } } catch {}
    $script:AiPendingRequest = $null
    return $true
  }

  $timeoutMs = Get-AiTimeoutMs
  $elapsed = ((Get-Date) - [DateTime]$pending.StartedAt).TotalMilliseconds
  $processEnded = $false
  try { $processEnded = ($null -ne $pending.Process -and $pending.Process.HasExited) } catch {}
  if ($processEnded) {
    Add-AiMessage -Role "system" -Content "La consulta IA termino sin devolver respuesta. Revisa el Debian codexray o vuelve a intentarlo."
    Set-AiBusy -Busy $false -Status "IA: error."
    try { [void]$script:ExternalProcesses.Remove($pending.Process) } catch {}
    try { if ($null -ne $pending.Process) { $pending.Process.Dispose() } } catch {}
    $script:AiPendingRequest = $null
    return $true
  }
  if ($elapsed -gt ($timeoutMs + 15000)) {
    try {
      if ($null -ne $pending.Process -and !$pending.Process.HasExited) {
        Stop-ProcessTree -ProcessId $pending.Process.Id
      }
    } catch {
    }
    Add-AiMessage -Role "system" -Content "La consulta IA ha superado el tiempo limite y se ha cancelado."
    Set-AiBusy -Busy $false -Status "IA: timeout."
    try { [void]$script:ExternalProcesses.Remove($pending.Process) } catch {}
    try { if ($null -ne $pending.Process) { $pending.Process.Dispose() } } catch {}
    $script:AiPendingRequest = $null
    return $true
  }

  if ($null -ne $script:AiStatusLabel) {
    Set-AiActivity -Status "enviada al Debian. Esperando respuesta..."
  }
  return $false
}

function Ensure-AiPollTimer {
  if ($null -eq $script:AiPollTimer) {
    $script:AiPollTimer = New-Object System.Windows.Forms.Timer
    $script:AiPollTimer.Interval = 500
    $script:AiPollTimer.Add_Tick({
      if (Complete-AiPendingRequest) {
        try { $script:AiPollTimer.Stop() } catch {}
      }
    })
  }
  $script:AiPollTimer.Start()
}

function Start-AiRequest {
  param(
    [string]$VisibleUserMessage,
    [scriptblock]$PromptFactory,
    [string]$PromptText = "",
    [bool]$NewConversation = $false,
    [string]$ResponseHandler = ""
  )
  if ($script:AiRequestActive) { return }
  $selectedModel = Get-AiSelectedModel
  $selectedReasoning = Get-AiSelectedReasoning
  Add-AiMessage -Role "user" -Content $VisibleUserMessage
  Set-AiBusy -Busy $true -Status "IA: preparando envio..."

  try {
    if (![string]::IsNullOrWhiteSpace([string]$PromptText)) {
      $prompt = [string]$PromptText
    } else {
      Set-AiActivity -Status "preparando prompt..."
      try { [System.Windows.Forms.Application]::DoEvents() } catch {}
      $prompt = & $PromptFactory
    }
    if ([string]::IsNullOrWhiteSpace($prompt)) {
      throw "El prompt IA esta vacio."
    }

    if (!(Test-Path -LiteralPath $script:AiRuntimeDir)) {
      [void](New-Item -ItemType Directory -Path $script:AiRuntimeDir -Force)
    }
    $requestId = "hub_ai_" + (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $requestPath = Join-Path $script:AiRuntimeDir ($requestId + ".request.json")
    $responsePath = Join-Path $script:AiRuntimeDir ($requestId + ".response.json")
    $payload = [pscustomobject]@{
      prompt = $prompt
      newConversation = $NewConversation
      model = $selectedModel
      reasoning = $selectedReasoning
      responsePath = $responsePath
    }
    [System.IO.File]::WriteAllText($requestPath, ($payload | ConvertTo-Json -Depth 20), $script:Utf8NoBom)

    $psExe = Get-WindowsPowerShellPath
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = (@(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-STA",
      "-File", $scriptPath,
      "-AiWorkerRequestPath", $requestPath
    ) | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    [void]$script:ExternalProcesses.Add($process)

    $script:AiPendingRequest = [pscustomobject]@{
      RequestPath = $requestPath
      ResponsePath = $responsePath
      Process = $process
      StartedAt = (Get-Date)
      ResponseHandler = $ResponseHandler
    }
    Set-AiBusy -Busy $true -Status "IA: enviada al Debian. Esperando respuesta..."
    Ensure-AiPollTimer
  } catch {
    Add-AiMessage -Role "system" -Content ("Error preparando la consulta IA: " + $_.Exception.Message)
    Set-AiBusy -Busy $false -Status "IA: error."
  }
}

function Start-AiBattleAdvice {
  Start-AiRequest `
    -VisibleUserMessage "Consejo IA combate: analiza el turno actual con los datos completos del combate." `
    -PromptFactory {
      Request-AiBattleState
      return New-AiBattlePrompt
    } `
    -NewConversation $false
}

function Start-AiPostBattleAnalysis {
  Start-AiRequest `
    -VisibleUserMessage "Analisis IA postcombate: explica la partida terminada, que estuvo bien, que se pudo mejorar y que habria hecho en cada turno importante." `
    -PromptFactory {
      return New-AiPostBattlePrompt
    } `
    -NewConversation $false
}

function Start-AiTeamAnalysis {
  Start-AiRequest `
    -VisibleUserMessage "Analisis IA del equipo: revisa el equipo actual, estrategias, puntos debiles y mejoras de movimientos." `
    -PromptFactory {
      Request-AiTeamState -Label "Analizar equipo IA"
      return New-AiTeamPrompt -TemplateName "team-analysis"
    } `
    -NewConversation $false
}

function Start-AiTeamBuilder {
  Start-AiRequest `
    -VisibleUserMessage "Crear equipo IA: mira mi equipo y mis cajas PC, usa el nivel maximo de mis Pokemon y propon un equipo de 6 con estrategia." `
    -PromptFactory {
      Request-AiTeamState -Label "Crear equipo IA"
      return New-AiTeamPrompt -TemplateName "team-builder"
    } `
    -NewConversation $false
}

function Start-AiPvpTeamBuilder {
  Start-AiRequest `
    -VisibleUserMessage "Preparar equipo PvP IA: elige 6 Pokemon reales de mi equipo y PC que cumplan las reglas multijugador configuradas." `
    -PromptFactory {
      Request-AiTeamState -Label "Preparar equipo PvP IA"
      return New-AiPvpTeamPrompt
    } `
    -NewConversation $false `
    -ResponseHandler "save_pvp_team"
}

function Start-AiCustomMessage {
  if ($null -eq $script:AiInputBox) { return }
  $text = $script:AiInputBox.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return }
  $script:AiInputBox.Text = ""
  $userText = $text
  Start-AiRequest `
    -VisibleUserMessage $userText `
    -PromptFactory ({
      if (Test-AiCustomNeedsTeamExport -Text $userText) {
        try { Request-AiTeamState -Label "Mensaje IA" } catch {}
      }
      return New-AiCustomPrompt -UserPrompt $userText
    }.GetNewClosure()) `
    -NewConversation $false
}

function New-AiConversation {
  $script:AiChatState = New-AiChatState
  $script:AiChatState.model = Get-AiSelectedModel
  $script:AiChatState.reasoning = Get-AiSelectedReasoning
  Save-AiChatState
  Render-AiChat
  Set-AiActivity -Status "creando nuevo chat en Debian..."
  try {
    $id = Invoke-DebianCreateAiConversation -Title ([string]$script:AiChatState.title) -Model ([string]$script:AiChatState.model) -Reasoning ([string]$script:AiChatState.reasoning)
    if (![string]::IsNullOrWhiteSpace($id)) {
      $script:AiChatState.conversationId = $id
      Save-AiChatState
      Set-AiActivity -Status "nuevo chat creado"
    } else {
      Set-AiActivity -Status "nuevo chat local creado; Debian lo creara al enviar"
    }
  } catch {
    Set-AiActivity -Status "nuevo chat local creado; no se pudo crear en Debian ahora"
  }
}

function Start-AiWarmup {
  if (!$script:AiRequestActive) {
    Set-AiActivity -Status "comprobando Tailscale y CodeXRay..."
    Start-AiConnectionCheck
  }
}

function Copy-AiChatToClipboard {
  if ($null -ne $script:AiChatBox -and ![string]::IsNullOrWhiteSpace($script:AiChatBox.Text)) {
    [System.Windows.Forms.Clipboard]::SetText($script:AiChatBox.Text)
    Set-AiActivity -Status "chat copiado"
  }
}

function Invoke-AiActionComboSelection {
  if ($null -eq $script:AiActionCombo) { return }
  $index = [int]$script:AiActionCombo.SelectedIndex
  if ($index -le 0) { return }
  $action = [string]$script:AiActionCombo.SelectedItem
  try {
    $script:AiActionComboReady = $false
    $script:AiActionCombo.SelectedIndex = 0
  } finally {
    $script:AiActionComboReady = $true
  }

  switch ($action) {
    "Analizar equipo" { Start-AiTeamAnalysis }
    "Analizar ultimo combate" { Start-AiPostBattleAnalysis }
    "Consejo IA combate" { Start-AiBattleAdvice }
    "Crear equipo" { Start-AiTeamBuilder }
    "Preparar equipo PvP" { Start-AiPvpTeamBuilder }
    "Copiar chat" { Copy-AiChatToClipboard }
  }
}

function Get-ActionDescription {
  param([object]$Action)
  if ($null -eq $Action) { return "" }
  if (![string]::IsNullOrWhiteSpace($Action.Acceso)) {
    return ("[{0}] {1}" -f $Action.Acceso, $Action.Detalle)
  }
  return $Action.Detalle
}

function Invoke-HubAction {
  param([object]$Action)
  if ($null -eq $Action) {
    $script:StatusLabel.Text = "No se encontro la accion."
    return
  }
  if ([string]$Action.Comando -eq "open_battle_advisor") {
    if ($null -ne $script:AiTabPage -and $null -ne $script:MainTabControl) {
      $script:MainTabControl.SelectedTab = $script:AiTabPage
    }
    Start-AiBattleAdvice
    return
  }
  if ([string]$Action.Comando -eq "open_post_battle_analysis") {
    if ($null -ne $script:AiTabPage -and $null -ne $script:MainTabControl) {
      $script:MainTabControl.SelectedTab = $script:AiTabPage
    }
    Start-AiPostBattleAnalysis
    return
  }
  if ([string]$Action.Comando -eq "open_team_analyzer") {
    if ($null -ne $script:AiTabPage -and $null -ne $script:MainTabControl) {
      $script:MainTabControl.SelectedTab = $script:AiTabPage
    }
    Start-AiTeamAnalysis
    return
  }
  if ([string]$Action.Comando -eq "open_team_builder") {
    if ($null -ne $script:AiTabPage -and $null -ne $script:MainTabControl) {
      $script:MainTabControl.SelectedTab = $script:AiTabPage
    }
    Start-AiTeamBuilder
    return
  }
  if ([string]$Action.Comando -eq "prepare_pvp_ai_team") {
    if ($null -ne $script:AiTabPage -and $null -ne $script:MainTabControl) {
      $script:MainTabControl.SelectedTab = $script:AiTabPage
    }
    Start-AiPvpTeamBuilder
    return
  }
  if (Send-HubCommand -Command $Action.Comando -Label $Action.Opcion) {
    $script:StatusLabel.Text = "Accion enviada al juego: " + $Action.Opcion
  }
}

function Resize-ActionRows {
  param([System.Windows.Forms.FlowLayoutPanel]$Flow)
  $targetWidth = [Math]::Max(420, $Flow.ClientSize.Width - 24)
  foreach ($control in $Flow.Controls) {
    $control.Width = $targetWidth
  }
}

function New-ActionRow {
  param([object]$Action)

  $row = New-Object System.Windows.Forms.TableLayoutPanel
  $row.ColumnCount = 2
  $row.RowCount = 1
  $row.Width = 680
  $row.Height = 44
  $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $row.Padding = New-Object System.Windows.Forms.Padding(0)
  $row.BackColor = [System.Drawing.Color]::FromArgb(250, 251, 252)
  [void]$row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 205)))
  [void]$row.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

  $button = New-Object System.Windows.Forms.Button
  $button.Text = $Action.Opcion
  $button.Tag = $Action
  $button.Dock = [System.Windows.Forms.DockStyle]::Fill
  $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
  $button.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  $button.Add_Click({
    param($sender, $eventArgs)
    Invoke-HubAction -Action $sender.Tag
  })
  [void]$row.Controls.Add($button, 0, 0)

  $description = New-Object System.Windows.Forms.Label
  $description.Text = Get-ActionDescription -Action $Action
  $description.Dock = [System.Windows.Forms.DockStyle]::Fill
  $description.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $description.AutoEllipsis = $true
  $description.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  $description.ForeColor = [System.Drawing.Color]::FromArgb(39, 45, 53)
  $description.Margin = New-Object System.Windows.Forms.Padding(0)
  [void]$row.Controls.Add($description, 1, 0)

  return $row
}

function New-QuickLabel {
  param([string]$Text, [int]$Width = 54)
  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Text
  $label.Width = $Width
  $label.Height = 28
  $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $label.Margin = New-Object System.Windows.Forms.Padding(0, 4, 4, 0)
  return $label
}

function New-QuickTextBox {
  param([string]$Text, [int]$Width = 120)
  $box = New-Object System.Windows.Forms.TextBox
  $box.Text = $Text
  $box.Width = $Width
  $box.Height = 24
  $box.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 0)
  return $box
}

function New-QuickNumber {
  param([int]$Minimum, [int]$Maximum, [int]$Value, [int]$Width = 70)
  $number = New-Object System.Windows.Forms.NumericUpDown
  $number.Minimum = $Minimum
  $number.Maximum = $Maximum
  $number.Width = $Width
  $number.Height = 24
  $number.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 0)
  try { $number.Value = [Math]::Min($Maximum, [Math]::Max($Minimum, $Value)) } catch {}
  return $number
}

function Set-HubStatus {
  param([string]$Text)
  if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = $Text }
}

function New-TricksQuickPanel {
  $group = New-Object System.Windows.Forms.GroupBox
  $group.Text = "Trucos con campos editables"
  $group.Dock = [System.Windows.Forms.DockStyle]::Fill
  $group.Padding = New-Object System.Windows.Forms.Padding(8)

  $flow = New-Object System.Windows.Forms.FlowLayoutPanel
  $flow.Dock = [System.Windows.Forms.DockStyle]::Fill
  $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
  $flow.WrapContents = $true
  $flow.AutoScroll = $true
  $flow.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
  $group.Controls.Add($flow)

  $capText = Get-HubIniValue -Name "level_cap_override" -Default "0"
  $capDefault = 0
  [void][int]::TryParse($capText, [ref]$capDefault)
  $shinyDefault = Get-HubIniInt -Name "wild_shiny_percent" -Default 10

  $capBox = New-QuickNumber -Minimum 0 -Maximum 999 -Value $capDefault -Width 64
  $ashesBox = New-QuickNumber -Minimum 1 -Maximum 999 -Value 2 -Width 64
  $shinyBox = New-QuickNumber -Minimum 0 -Maximum 100 -Value $shinyDefault -Width 58

  [void]$flow.Controls.Add((New-QuickLabel -Text "Cap" -Width 30))
  [void]$flow.Controls.Add($capBox)
  $capButton = New-Object System.Windows.Forms.Button
  $capButton.Text = "Aplicar cap"
  $capButton.Width = 94
  $capButton.Height = 28
  $capButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 6, 0)
  $capButton.Add_Click({
    $level = [int]$capBox.Value
    $stored = ""
    if ($level -gt 0) { $stored = $level.ToString() }
    Set-HubIniValue -Name "level_cap_override" -Value $stored
    if (Send-HubCommand -Command "set_level_cap_value" -Label "Aplicar level cap" -Values @{ level = $level }) {
      Set-HubStatus "Level cap enviado al juego."
    }
  }.GetNewClosure())
  [void]$flow.Controls.Add($capButton)

  [void]$flow.Controls.Add((New-QuickLabel -Text "Cenizas" -Width 56))
  [void]$flow.Controls.Add($ashesBox)
  $ashesButton = New-Object System.Windows.Forms.Button
  $ashesButton.Text = "Dar"
  $ashesButton.Width = 56
  $ashesButton.Height = 28
  $ashesButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 6, 0)
  $ashesButton.Add_Click({
    if (Send-HubCommand -Command "give_ashes_quantity" -Label "Dar Cenizas Sagradas" -Values @{ quantity = [int]$ashesBox.Value }) {
      Set-HubStatus "Cenizas Sagradas enviadas al juego."
    }
  }.GetNewClosure())
  [void]$flow.Controls.Add($ashesButton)

  [void]$flow.Controls.Add((New-QuickLabel -Text "Shiny %" -Width 58))
  [void]$flow.Controls.Add($shinyBox)
  $shinyButton = New-Object System.Windows.Forms.Button
  $shinyButton.Text = "Aplicar"
  $shinyButton.Width = 70
  $shinyButton.Height = 28
  $shinyButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
  $shinyButton.Add_Click({
    Set-HubIniValue -Name "wild_shiny_percent" -Value ([int]$shinyBox.Value).ToString()
    if (Send-HubCommand -Command "set_wild_shiny_percent_value" -Label "Aplicar shiny salvaje" -Values @{ percent = [int]$shinyBox.Value }) {
      Set-HubStatus "Porcentaje shiny enviado al juego."
    }
  }.GetNewClosure())
  [void]$flow.Controls.Add($shinyButton)

  return $group
}

function New-ActionTab {
  param(
    [string]$Name,
    [object[]]$Actions
  )

  $tab = New-Object System.Windows.Forms.TabPage
  $tab.Text = $Name
  $tab.Padding = New-Object System.Windows.Forms.Padding(8)

  $flow = New-Object System.Windows.Forms.FlowLayoutPanel
  $flow.Dock = [System.Windows.Forms.DockStyle]::Fill
  $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
  $flow.WrapContents = $false
  $flow.AutoScroll = $true
  $flow.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 248)
  $flow.Padding = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $flow.Add_Resize({
    param($sender, $eventArgs)
    Resize-ActionRows -Flow $sender
  })

  foreach ($action in $Actions) {
    [void]$flow.Controls.Add((New-ActionRow -Action $action))
  }
  Resize-ActionRows -Flow $flow
  if ($Name -eq "Trucos") {
    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.ColumnCount = 1
    $layout.RowCount = 2
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.Controls.Add((New-TricksQuickPanel), 0, 0)
    [void]$layout.Controls.Add($flow, 0, 1)
    $tab.Controls.Add($layout)
  } else {
    $tab.Controls.Add($flow)
  }
  return $tab
}

function New-AiTab {
  $tab = New-Object System.Windows.Forms.TabPage
  $tab.Text = "IA"
  $tab.Padding = New-Object System.Windows.Forms.Padding(8)
  $script:AiTabPage = $tab

  $layout = New-Object System.Windows.Forms.TableLayoutPanel
  $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
  $layout.ColumnCount = 1
  $layout.RowCount = 4
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
  $tab.Controls.Add($layout)

  $topLayout = New-Object System.Windows.Forms.TableLayoutPanel
  $topLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
  $topLayout.ColumnCount = 1
  $topLayout.RowCount = 2
  $topLayout.Margin = New-Object System.Windows.Forms.Padding(0)
  [void]$topLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
  [void]$topLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
  $layout.Controls.Add($topLayout, 0, 0)

  $settings = New-Object System.Windows.Forms.TableLayoutPanel
  $settings.Dock = [System.Windows.Forms.DockStyle]::Fill
  $settings.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $settings.ColumnCount = 6
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 154)))
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 94)))
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 166)))
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 105)))
  $topLayout.Controls.Add($settings, 0, 0)

  $modelLabel = New-Object System.Windows.Forms.Label
  $modelLabel.Text = "Modelo"
  $modelLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $modelLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  [void]$settings.Controls.Add($modelLabel, 0, 0)

  $script:AiModelCombo = New-Object System.Windows.Forms.ComboBox
  $script:AiModelCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiModelCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  [void]$script:AiModelCombo.Items.AddRange([object[]]@("Auto", "gpt-5.5", "gpt-5.4", "gpt-5", "gpt-5-codex"))
  $savedModel = Get-HubIniValue -Name "codex_ai_model" -Default ""
  $script:AiModelCombo.Text = if ([string]::IsNullOrWhiteSpace($savedModel)) { "Auto" } else { $savedModel }
  [void]$settings.Controls.Add($script:AiModelCombo, 1, 0)

  $reasoningLabel = New-Object System.Windows.Forms.Label
  $reasoningLabel.Text = "Pensamiento"
  $reasoningLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $reasoningLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  [void]$settings.Controls.Add($reasoningLabel, 2, 0)

  $script:AiReasoningCombo = New-Object System.Windows.Forms.ComboBox
  $script:AiReasoningCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiReasoningCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
  [void]$script:AiReasoningCombo.Items.AddRange([object[]]@("Auto", "bajo", "medio", "alto", "extremadamente alto", "none", "minimal", "low", "medium", "high", "xhigh"))
  $script:AiReasoningCombo.Text = Get-HubIniValue -Name "codex_ai_reasoning" -Default "medio"
  [void]$settings.Controls.Add($script:AiReasoningCombo, 3, 0)

  $script:AiNewChatButton = New-Object System.Windows.Forms.Button
  $script:AiNewChatButton.Text = "Nuevo chat"
  $script:AiNewChatButton.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiNewChatButton.Add_Click({ New-AiConversation })
  [void]$settings.Controls.Add($script:AiNewChatButton, 5, 0)

  $connection = New-Object System.Windows.Forms.TableLayoutPanel
  $connection.Dock = [System.Windows.Forms.DockStyle]::Fill
  $connection.Margin = New-Object System.Windows.Forms.Padding(0)
  $connection.ColumnCount = 4
  [void]$connection.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 148)))
  [void]$connection.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
  [void]$connection.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$connection.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
  $topLayout.Controls.Add($connection, 0, 1)

  $script:AiTailscaleStatusLabel = New-Object System.Windows.Forms.Label
  $script:AiTailscaleStatusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiTailscaleStatusLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  [void]$connection.Controls.Add($script:AiTailscaleStatusLabel, 0, 0)

  $script:AiCodexRayStatusLabel = New-Object System.Windows.Forms.Label
  $script:AiCodexRayStatusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiCodexRayStatusLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  [void]$connection.Controls.Add($script:AiCodexRayStatusLabel, 1, 0)

  $script:AiConnectionDetailLabel = New-Object System.Windows.Forms.Label
  $script:AiConnectionDetailLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiConnectionDetailLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $script:AiConnectionDetailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.25)
  $script:AiConnectionDetailLabel.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
  [void]$connection.Controls.Add($script:AiConnectionDetailLabel, 2, 0)
  $script:AiStatusLabel = $script:AiConnectionDetailLabel

  $script:AiRefreshConnectionButton = New-Object System.Windows.Forms.Button
  $script:AiRefreshConnectionButton.Text = "Comprobar"
  $script:AiRefreshConnectionButton.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiRefreshConnectionButton.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
  $script:AiRefreshConnectionButton.Add_Click({ Start-AiConnectionCheck })
  [void]$connection.Controls.Add($script:AiRefreshConnectionButton, 3, 0)
  Set-AiConnectionLabels -Status (Read-AiConnectionStatusFile)

  $script:AiChatBox = New-Object System.Windows.Forms.RichTextBox
  $script:AiChatBox.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiChatBox.ReadOnly = $true
  $script:AiChatBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $script:AiChatBox.BackColor = [System.Drawing.Color]::FromArgb(250, 251, 253)
  $script:AiChatBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  $script:AiChatBox.DetectUrls = $true
  $script:AiChatBox.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)
  $layout.Controls.Add($script:AiChatBox, 0, 1)

  $inputRow = New-Object System.Windows.Forms.TableLayoutPanel
  $inputRow.Dock = [System.Windows.Forms.DockStyle]::Fill
  $inputRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $inputRow.ColumnCount = 2
  [void]$inputRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$inputRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
  $layout.Controls.Add($inputRow, 0, 2)

  $script:AiInputBox = New-Object System.Windows.Forms.TextBox
  $script:AiInputBox.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiInputBox.Multiline = $false
  $script:AiInputBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  $script:AiInputBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $script:AiInputBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and !$_.Shift) {
      $_.SuppressKeyPress = $true
      Start-AiCustomMessage
    }
  })
  [void]$inputRow.Controls.Add($script:AiInputBox, 0, 0)

  $script:AiSendButton = New-Object System.Windows.Forms.Button
  $script:AiSendButton.Text = "Enviar"
  $script:AiSendButton.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiSendButton.Margin = New-Object System.Windows.Forms.Padding(0)
  $script:AiSendButton.BackColor = [System.Drawing.Color]::FromArgb(52, 120, 210)
  $script:AiSendButton.ForeColor = [System.Drawing.Color]::White
  $script:AiSendButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $script:AiSendButton.Add_Click({ Start-AiCustomMessage })
  [void]$inputRow.Controls.Add($script:AiSendButton, 1, 0)

  $actionRow = New-Object System.Windows.Forms.TableLayoutPanel
  $actionRow.Dock = [System.Windows.Forms.DockStyle]::Fill
  $actionRow.Margin = New-Object System.Windows.Forms.Padding(0)
  $actionRow.ColumnCount = 2
  [void]$actionRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
  [void]$actionRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  $layout.Controls.Add($actionRow, 0, 3)

  $actionLabel = New-Object System.Windows.Forms.Label
  $actionLabel.Text = "Accion IA"
  $actionLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
  $actionLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $actionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
  [void]$actionRow.Controls.Add($actionLabel, 0, 0)

  $script:AiActionCombo = New-Object System.Windows.Forms.ComboBox
  $script:AiActionCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:AiActionCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
  $script:AiActionCombo.Margin = New-Object System.Windows.Forms.Padding(0)
  [void]$script:AiActionCombo.Items.AddRange([object[]]@(
    "Selecciona una accion...",
    "Analizar equipo",
    "Analizar ultimo combate",
    "Consejo IA combate",
    "Crear equipo",
    "Preparar equipo PvP",
    "Copiar chat"
  ))
  $script:AiActionCombo.SelectedIndex = 0
  $script:AiActionCombo.Add_SelectedIndexChanged({
    if (!$script:AiActionComboReady) { return }
    Invoke-AiActionComboSelection
  })
  $script:AiActionComboReady = $true
  [void]$actionRow.Controls.Add($script:AiActionCombo, 1, 0)

  [void](Get-AiChatState)
  Render-AiChat
  return $tab
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "SebiLink Hub F12 | Pokemon Z | v" + $script:AddonVersion
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(760, 500)
$form.MinimumSize = New-Object System.Drawing.Size(620, 380)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 248)
if ($null -ne $script:GameIcon) {
  $form.Icon = $script:GameIcon
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount = 3
$root.Margin = New-Object System.Windows.Forms.Padding(0)
$root.Padding = New-Object System.Windows.Forms.Padding(10)
[void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 54)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$form.Controls.Add($root)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.Controls.Add($top, 0, 0)

$title = New-Object System.Windows.Forms.Label
$title.Text = "SebiLink Hub - v" + $script:AddonVersion
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(0, 0)
$title.Size = New-Object System.Drawing.Size(420, 26)
$top.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Boton a la izquierda, descripcion a la derecha. Clic y se ejecuta en el juego."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.Location = New-Object System.Drawing.Point(2, 28)
$subtitle.Size = New-Object System.Drawing.Size(520, 20)
$top.Controls.Add($subtitle)

$topMostCheck = New-Object System.Windows.Forms.CheckBox
$topMostCheck.Text = "Siempre encima"
$topMostCheck.Location = New-Object System.Drawing.Point(590, 4)
$topMostCheck.Size = New-Object System.Drawing.Size(130, 24)
$topMostCheck.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$top.Controls.Add($topMostCheck)

$tabControl = New-Object System.Windows.Forms.TabControl
$script:MainTabControl = $tabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$root.Controls.Add($tabControl, 0, 1)

$actionGroups = @("Todas", "Teclas", "IA", "Centro Pokemon", "Trucos", "Sistema")
foreach ($group in $actionGroups) {
  if ($group -eq "IA") {
    [void]$tabControl.TabPages.Add((New-AiTab))
    continue
  }
  if ($group -eq "Todas") {
    $seenCommands = @{}
    $items = @()
    foreach ($action in @($script:Actions)) {
      $key = [string]$action.Comando
      if (!$seenCommands.ContainsKey($key)) {
        $seenCommands[$key] = $true
        $items += $action
      }
    }
  } else {
    $items = @($script:Actions | Where-Object { $_.Categoria -eq $group })
  }
  [void]$tabControl.TabPages.Add((New-ActionTab -Name $group -Actions $items))
}
if ($OpenAi -and $null -ne $script:AiTabPage) {
  $tabControl.SelectedTab = $script:AiTabPage
} else {
  $tabControl.SelectedIndex = 0
}

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$script:StatusLabel.Text = ("{0} acciones disponibles. Tab Todas abierto por defecto." -f $script:Actions.Count)
$root.Controls.Add($script:StatusLabel, 0, 2)

$topMostCheck.Add_CheckedChanged({ $form.TopMost = $topMostCheck.Checked })

Initialize-GameMonitor

$gameMonitorTimer = New-Object System.Windows.Forms.Timer
$gameMonitorTimer.Interval = 1500
$gameMonitorTimer.Add_Tick({
  if (!(Test-GameStillRunning)) {
    $script:ClosingBecauseGameClosed = $true
    Stop-ExternalProcesses
    $form.Close()
  }
})
$gameMonitorTimer.Start()

$form.Add_Shown({ Start-AiWarmup })
$form.Add_FormClosing({
  try { $gameMonitorTimer.Stop() } catch {}
  try { if ($null -ne $script:AiPollTimer) { $script:AiPollTimer.Stop() } } catch {}
  try {
    if ($null -ne $script:AiPendingRequest -and $null -ne $script:AiPendingRequest.Process -and !$script:AiPendingRequest.Process.HasExited) {
      Stop-ProcessTree -ProcessId $script:AiPendingRequest.Process.Id
    }
    $script:AiPendingRequest = $null
  } catch {}
  Stop-ExternalProcesses
})

[void]$form.ShowDialog()
