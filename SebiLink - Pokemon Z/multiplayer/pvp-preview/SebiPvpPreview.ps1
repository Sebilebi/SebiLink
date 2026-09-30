param(
  [string]$StatePath,
  [string]$ResultPath,
  [switch]$SelfTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseDir = $PSScriptRoot
$script:MultiplayerDir = Split-Path $script:BaseDir -Parent
$script:GameDir = Split-Path $script:MultiplayerDir -Parent
$script:Confirmed = $false
$script:CurrentImage = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-PreviewState {
  if ([string]::IsNullOrWhiteSpace($StatePath) -or !(Test-Path -LiteralPath $StatePath)) {
    return $null
  }
  for ($i = 0; $i -lt 3; $i++) {
    try {
      $stream = New-Object System.IO.FileStream(
        $StatePath,
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

function Write-PreviewResult {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($ResultPath)) { return }
  $dir = Split-Path $ResultPath -Parent
  if (!(Test-Path -LiteralPath $dir)) {
    [void](New-Item -ItemType Directory -Path $dir -Force)
  }
  [System.IO.File]::WriteAllText($ResultPath, $Value, $script:Utf8NoBom)
}

function Get-PokemonName {
  param([object]$Pokemon)
  $name = [string]$Pokemon.speciesName
  if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$Pokemon.nickname }
  if ([string]::IsNullOrWhiteSpace($name)) { $name = "Pokemon" }
  return $name
}

function Get-IconPath {
  param([object]$Pokemon)
  $species = [int]$Pokemon.species
  $path = Join-Path $script:GameDir ("Graphics\Icons\icon{0:D3}.png" -f $species)
  if (Test-Path -LiteralPath $path) { return $path }
  return $null
}

function Set-PreviewIcon {
  param([object]$Pokemon)
  if ($null -ne $script:CurrentImage) {
    try { $script:CurrentImage.Dispose() } catch {}
    $script:CurrentImage = $null
  }
  $script:IconBox.Image = $null
  $path = Get-IconPath -Pokemon $Pokemon
  if ($null -eq $path) { return }
  try {
    $source = [System.Drawing.Image]::FromFile($path)
    try {
      $size = [Math]::Min($source.Height, $source.Width)
      $bitmap = New-Object System.Drawing.Bitmap($size, $size)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.DrawImage($source, 0, 0, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)), [System.Drawing.GraphicsUnit]::Pixel)
      } finally {
        $graphics.Dispose()
      }
      $script:CurrentImage = $bitmap
      $script:IconBox.Image = $bitmap
    } finally {
      $source.Dispose()
    }
  } catch {
  }
}

function Join-Values {
  param([object]$Values)
  $items = @($Values | ForEach-Object { [string]$_ } | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
  if ($items.Count -eq 0) { return "-" }
  return ($items -join ", ")
}

function Format-BaseStats {
  param([object]$Stats)
  $values = @($Stats)
  while ($values.Count -lt 6) { $values += 0 }
  return ("HP {0} | Atq {1} | Def {2} | Atq. Esp. {3} | Def. Esp. {4} | Vel {5}" -f $values[0], $values[1], $values[2], $values[3], $values[4], $values[5])
}

function Format-RealStats {
  param([object]$Stats)
  if ($null -eq $Stats) { return "-" }
  return ("HP {0} | Atq {1} | Def {2} | Atq. Esp. {3} | Def. Esp. {4} | Vel {5}" -f $Stats.hp, $Stats.attack, $Stats.defense, $Stats.spatk, $Stats.spdef, $Stats.speed)
}

function Show-RivalDetails {
  param([object]$Pokemon)
  if ($null -eq $Pokemon) { return }
  Set-PreviewIcon -Pokemon $Pokemon
  $name = Get-PokemonName -Pokemon $Pokemon
  $typeValues = @([string]$Pokemon.type1Name)
  if (![string]::IsNullOrWhiteSpace([string]$Pokemon.type2Name) -and [string]$Pokemon.type2Name -ne [string]$Pokemon.type1Name) {
    $typeValues += [string]$Pokemon.type2Name
  }
  $types = Join-Values $typeValues
  $chart = $Pokemon.typeChart
  $lines = @(
    ("{0} | Nv.{1}" -f $name, [int]$Pokemon.level),
    ("Tipos: {0}" -f $types),
    "",
    "Stats base:",
    (Format-BaseStats -Stats $Pokemon.baseStats),
    "",
    ("Debilidades x4: {0}" -f (Join-Values $chart.x4)),
    ("Debilidades x2: {0}" -f (Join-Values $chart.x2)),
    ("Danio normal x1: {0}" -f (Join-Values $chart.x1)),
    ("Resistencias x0.5: {0}" -f (Join-Values $chart.x05)),
    ("Resistencias x0.25: {0}" -f (Join-Values $chart.x025)),
    ("Inmunidades x0: {0}" -f (Join-Values $chart.x0)),
    "",
    "No se muestran stats reales, movimientos, habilidad ni objeto del rival."
  )
  $script:DetailsBox.Text = ($lines -join [Environment]::NewLine)
}

function Show-OwnDetails {
  param([object]$Pokemon)
  if ($null -eq $Pokemon) { return }
  Set-PreviewIcon -Pokemon $Pokemon
  $name = Get-PokemonName -Pokemon $Pokemon
  $moves = @($Pokemon.moves | ForEach-Object { [string]$_.name } | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
  $typeValues = @([string]$Pokemon.type1Name)
  if (![string]::IsNullOrWhiteSpace([string]$Pokemon.type2Name) -and [string]$Pokemon.type2Name -ne [string]$Pokemon.type1Name) {
    $typeValues += [string]$Pokemon.type2Name
  }
  $types = Join-Values $typeValues
  $lines = @(
    ("{0} | Nv.{1}" -f $name, [int]$Pokemon.level),
    ("Tipos: {0}" -f $types),
    ("Habilidad: {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$Pokemon.abilityName)) { "-" } else { [string]$Pokemon.abilityName })),
    ("Objeto: {0}" -f $(if ([string]::IsNullOrWhiteSpace([string]$Pokemon.itemName)) { "-" } else { [string]$Pokemon.itemName })),
    "",
    "Stats reales:",
    (Format-RealStats -Stats $Pokemon.stats),
    "",
    ("Movimientos: {0}" -f (Join-Values $moves))
  )
  $script:DetailsBox.Text = ($lines -join [Environment]::NewLine)
}

function Fill-TeamList {
  param(
    [System.Windows.Forms.ListBox]$List,
    [object]$Party
  )
  $List.Items.Clear()
  foreach ($pokemon in @($Party)) {
    $name = Get-PokemonName -Pokemon $pokemon
    [void]$List.Items.Add(("{0}  Nv.{1}" -f $name, [int]$pokemon.level))
  }
  if ($List.Items.Count -gt 0) { $List.SelectedIndex = 0 }
}

if ($SelfTest) {
  Write-Host "SebiPvpPreview.ps1 OK"
  exit 0
}

$script:State = Read-PreviewState
if ($null -eq $script:State) {
  Write-PreviewResult -Value "CANCEL"
  throw "No se pudo leer el estado de preview PvP."
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "SebiLink | Vista previa de combate"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)
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
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
$form.Controls.Add($root)

$title = New-Object System.Windows.Forms.Label
$title.Text = ("Vista previa contra {0}" -f [string]$script:State.rivalName)
$title.Dock = [System.Windows.Forms.DockStyle]::Fill
$title.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$title.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$root.Controls.Add($title, 0, 0)

$rules = New-Object System.Windows.Forms.Label
$format = if ([string]$script:State.mode -eq "double") { "2vs2" } else { "1vs1" }
$rules.Text = ("Formato {0} | {1} | Confirma tu equipo antes de elegir el Pokemon inicial." -f $format, [string]$script:State.rules)
$rules.Dock = [System.Windows.Forms.DockStyle]::Fill
$rules.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$rules.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$root.Controls.Add($rules, 0, 1)

$body = New-Object System.Windows.Forms.SplitContainer
$body.Dock = [System.Windows.Forms.DockStyle]::Fill
$body.SplitterDistance = 360
$body.Panel1MinSize = 280
$body.Panel2MinSize = 340
$root.Controls.Add($body, 0, 2)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$body.Panel1.Controls.Add($tabs)

$rivalTab = New-Object System.Windows.Forms.TabPage
$rivalTab.Text = "Equipo rival"
$tabs.TabPages.Add($rivalTab)

$ownTab = New-Object System.Windows.Forms.TabPage
$ownTab.Text = "Mi equipo"
$tabs.TabPages.Add($ownTab)

$script:RivalList = New-Object System.Windows.Forms.ListBox
$script:RivalList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:RivalList.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$rivalTab.Controls.Add($script:RivalList)

$script:OwnList = New-Object System.Windows.Forms.ListBox
$script:OwnList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:OwnList.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$ownTab.Controls.Add($script:OwnList)

$detailRoot = New-Object System.Windows.Forms.TableLayoutPanel
$detailRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
$detailRoot.ColumnCount = 1
$detailRoot.RowCount = 2
[void]$detailRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 112)))
[void]$detailRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$body.Panel2.Controls.Add($detailRoot)

$script:IconBox = New-Object System.Windows.Forms.PictureBox
$script:IconBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:IconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
$detailRoot.Controls.Add($script:IconBox, 0, 0)

$script:DetailsBox = New-Object System.Windows.Forms.RichTextBox
$script:DetailsBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:DetailsBox.ReadOnly = $true
$script:DetailsBox.BackColor = [System.Drawing.Color]::White
$script:DetailsBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$detailRoot.Controls.Add($script:DetailsBox, 0, 1)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttons.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$buttons.WrapContents = $false
$root.Controls.Add($buttons, 0, 3)

$confirm = New-Object System.Windows.Forms.Button
$confirm.Text = "Confirmar equipo"
$confirm.AutoSize = $true
$confirm.Height = 34
$confirm.Add_Click({
  $script:Confirmed = $true
  Write-PreviewResult -Value "CONFIRM"
  $form.Close()
})
$buttons.Controls.Add($confirm)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = "Cancelar combate"
$cancel.AutoSize = $true
$cancel.Height = 34
$cancel.Add_Click({
  Write-PreviewResult -Value "CANCEL"
  $form.Close()
})
$buttons.Controls.Add($cancel)

Fill-TeamList -List $script:RivalList -Party $script:State.rivalParty
Fill-TeamList -List $script:OwnList -Party $script:State.ownParty

$script:RivalList.Add_SelectedIndexChanged({
  $index = $script:RivalList.SelectedIndex
  if ($index -ge 0) { Show-RivalDetails -Pokemon @($script:State.rivalParty)[$index] }
})
$script:OwnList.Add_SelectedIndexChanged({
  $index = $script:OwnList.SelectedIndex
  if ($index -ge 0) { Show-OwnDetails -Pokemon @($script:State.ownParty)[$index] }
})
$tabs.Add_SelectedIndexChanged({
  if ($tabs.SelectedTab -eq $ownTab) {
    $index = $script:OwnList.SelectedIndex
    if ($index -ge 0) { Show-OwnDetails -Pokemon @($script:State.ownParty)[$index] }
  } else {
    $index = $script:RivalList.SelectedIndex
    if ($index -ge 0) { Show-RivalDetails -Pokemon @($script:State.rivalParty)[$index] }
  }
})

$form.Add_Shown({
  if ($script:RivalList.SelectedIndex -ge 0) {
    Show-RivalDetails -Pokemon @($script:State.rivalParty)[$script:RivalList.SelectedIndex]
  }
})
$form.Add_FormClosed({
  if (!$script:Confirmed) {
    try { Write-PreviewResult -Value "CANCEL" } catch {}
  }
  if ($null -ne $script:CurrentImage) {
    try { $script:CurrentImage.Dispose() } catch {}
  }
})

[void]$form.ShowDialog()
