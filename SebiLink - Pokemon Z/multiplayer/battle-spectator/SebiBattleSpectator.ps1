param(
  [switch]$SelfTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseDir = $PSScriptRoot
$script:MultiplayerDir = Split-Path $script:BaseDir -Parent
$script:GameDir = Split-Path $script:MultiplayerDir -Parent
$profile = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($profile)) {
  $profile = [Environment]::GetFolderPath("UserProfile")
}
$script:RuntimeDir = Join-Path (Join-Path (Join-Path (Join-Path $profile "Saved Games") "Pokemon Z") "SebiLinkConfig") "battle-spectator\runtime"
$script:StatePath = Join-Path $script:RuntimeDir "state.json"
$script:LastWrite = [DateTime]::MinValue

function Read-SpectatorState {
  if (!(Test-Path -LiteralPath $script:StatePath)) { return $null }
  for ($i = 0; $i -lt 3; $i++) {
    try {
      $stream = New-Object System.IO.FileStream(
        $script:StatePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
      )
      try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
      } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stream.Dispose()
      }
      if (![string]::IsNullOrWhiteSpace($text)) {
        return ($text | ConvertFrom-Json)
      }
    } catch {
      Start-Sleep -Milliseconds 40
    }
  }
  return $null
}

function Format-PokemonLine {
  param(
    [object]$Pokemon,
    [bool]$Active = $false
  )
  if ($null -eq $Pokemon) { return "" }
  $name = [string]$Pokemon.speciesName
  if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$Pokemon.name }
  $level = [int]$Pokemon.level
  $hp = [int]$Pokemon.hp
  $total = [int]$Pokemon.totalhp
  $status = [string]$Pokemon.statusName
  if ([string]::IsNullOrWhiteSpace($status) -or $status -eq "Normal") { $status = "" } else { $status = " | " + $status }
  $prefix = if ($Active) { "> " } else { "  " }
  return ("{0}{1}  Nv.{2}  HP {3}/{4}{5}" -f $prefix, $name, $level, $hp, $total, $status)
}

function Update-SpectatorView {
  param([object]$Data)
  if ($null -eq $Data) { return }
  if ($Data.ended -eq $true) {
    $script:StatusLabel.Text = "Finalizado: " + [string]$Data.message
  } else {
    $mode = if ($Data.pvpBattle -eq $true) { "PvP" } else { "Normal" }
    if ($Data.doubleBattle -eq $true) { $mode += " doble" }
    $script:StatusLabel.Text = ("Turno {0} | {1} | {2}" -f [int]$Data.turn, $mode, [string]$Data.event)
  }
  if ($null -eq $Data.state) { return }
  $script:PlayerTitle.Text = if ([string]::IsNullOrWhiteSpace([string]$Data.playerName)) { "Jugador" } else { [string]$Data.playerName }
  $script:OpponentTitle.Text = if ([string]::IsNullOrWhiteSpace([string]$Data.opponentName)) { "Rival" } else { [string]$Data.opponentName }

  $script:PlayerList.Items.Clear()
  $script:OpponentList.Items.Clear()
  $playerActive = @{}
  $opponentActive = @{}
  foreach ($battler in @($Data.state.activeBattlers)) {
    $partyIndex = [string]$battler.partyIndex
    if ([string]$battler.side -eq "jugador") {
      $playerActive[$partyIndex] = $true
    } elseif ([string]$battler.side -eq "rival") {
      $opponentActive[$partyIndex] = $true
    }
  }
  foreach ($pokemon in @($Data.state.playerParty)) {
    [void]$script:PlayerList.Items.Add((Format-PokemonLine -Pokemon $pokemon -Active ($playerActive.ContainsKey([string]$pokemon.index))))
  }
  foreach ($pokemon in @($Data.state.opponentParty)) {
    [void]$script:OpponentList.Items.Add((Format-PokemonLine -Pokemon $pokemon -Active ($opponentActive.ContainsKey([string]$pokemon.index))))
  }

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($message in @($Data.recentMessages)) {
    $text = [string]$message.text
    if (![string]::IsNullOrWhiteSpace($text)) {
      $lines.Add(("T{0}: {1}" -f [int]$message.turn, $text))
    }
  }
  $script:LogBox.Text = ($lines -join [Environment]::NewLine)
  $script:LogBox.SelectionStart = $script:LogBox.TextLength
  $script:LogBox.ScrollToCaret()
}

if ($SelfTest) {
  Write-Host "SebiBattleSpectator.ps1 OK"
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "SebiLink | Espectador de combate"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(820, 590)
$form.MinimumSize = New-Object System.Drawing.Size(680, 480)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 248)

try {
  $gamePath = Join-Path $script:GameDir "Game.exe"
  if (Test-Path -LiteralPath $gamePath) {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($gamePath)
  }
} catch {
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.Padding = New-Object System.Windows.Forms.Padding(10)
$root.ColumnCount = 1
$root.RowCount = 4
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 48)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 52)))
$form.Controls.Add($root)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Espectador de combate"
$title.Dock = [System.Windows.Forms.DockStyle]::Fill
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$root.Controls.Add($title, 0, 0)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Esperando estado del combate..."
$script:StatusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$root.Controls.Add($script:StatusLabel, 0, 1)

$teams = New-Object System.Windows.Forms.TableLayoutPanel
$teams.Dock = [System.Windows.Forms.DockStyle]::Fill
$teams.ColumnCount = 2
$teams.RowCount = 2
[void]$teams.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$teams.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$teams.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
[void]$teams.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$root.Controls.Add($teams, 0, 2)

$script:PlayerTitle = New-Object System.Windows.Forms.Label
$script:PlayerTitle.Text = "Jugador"
$script:PlayerTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PlayerTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:PlayerTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$teams.Controls.Add($script:PlayerTitle, 0, 0)

$script:OpponentTitle = New-Object System.Windows.Forms.Label
$script:OpponentTitle.Text = "Rival"
$script:OpponentTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:OpponentTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$script:OpponentTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$teams.Controls.Add($script:OpponentTitle, 1, 0)

$script:PlayerList = New-Object System.Windows.Forms.ListBox
$script:PlayerList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PlayerList.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:PlayerList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 6)
$teams.Controls.Add($script:PlayerList, 0, 1)

$script:OpponentList = New-Object System.Windows.Forms.ListBox
$script:OpponentList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:OpponentList.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:OpponentList.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 6)
$teams.Controls.Add($script:OpponentList, 1, 1)

$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "Registro reciente"
$logGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.Controls.Add($logGroup, 0, 3)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::White
$script:LogBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$logGroup.Controls.Add($script:LogBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400
$timer.Add_Tick({
  try {
    if (Test-Path -LiteralPath $script:StatePath) {
      $item = Get-Item -LiteralPath $script:StatePath
      if ($item.LastWriteTime -ne $script:LastWrite) {
        $script:LastWrite = $item.LastWriteTime
        Update-SpectatorView -Data (Read-SpectatorState)
      }
    }
  } catch {
  }
})
$timer.Start()

$form.Add_Shown({
  Update-SpectatorView -Data (Read-SpectatorState)
})
$form.Add_FormClosed({
  try { $timer.Stop() } catch {}
  try { $timer.Dispose() } catch {}
})

[void]$form.ShowDialog()
