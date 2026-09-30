param(
  [switch]$QuickTab,
  [switch]$SelfTest
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
if (!(Test-Path -LiteralPath $script:SebiLinkConfigRoot)) {
  [void](New-Item -ItemType Directory -Path $script:SebiLinkConfigRoot -Force)
}
$script:RuntimeDir = Join-Path $script:SebiLinkConfigRoot "save-manager\runtime"
Copy-SebiLinkLegacyRuntime -OldPath (Join-Path $script:BaseDir "runtime") -NewPath $script:RuntimeDir
$script:IndexPath = Join-Path $script:RuntimeDir "index.json"
$script:CommandPath = Join-Path $script:RuntimeDir "commands.txt"
$script:ResultPath = Join-Path $script:RuntimeDir "last_result.json"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:GameIcon = $null
$script:IndexData = $null
$script:RefreshTimer = $null
$script:RefreshTicks = 0
$script:PreviewRefreshTicks = 0
$script:RefreshingLists = $false
$script:PreviewPath = Join-Path $script:RuntimeDir "selected_preview.json"
$script:LocationPicture = $null
$script:PartyPreviewSlots = @()
$script:PcPreviewSlots = @()
$script:PcPreviewLabel = $null
$script:SelectedPreview = $null
$script:SelectedPcBoxIndex = 0
$script:StartOnQuickTab = [bool]$QuickTab
$script:LastPreviewPath = ""
$script:LoadPage = $null
$script:QuickPage = $null
$script:PreviewRoot = $null
$script:LoadPreviewHost = $null
$script:QuickPreviewHost = $null

try {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SebiSaveManagerNative {
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

function Ensure-ManagerRuntime {
  if (!(Test-Path -LiteralPath $script:RuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:RuntimeDir -Force)
  }
}

function Get-ManagerProp {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Default = ""
  )
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
  return $prop.Value
}

function Get-ManagerString {
  param(
    [object]$Object,
    [string]$Name,
    [string]$Default = ""
  )
  return [string](Get-ManagerProp -Object $Object -Name $Name -Default $Default)
}

function Get-ManagerInt {
  param(
    [object]$Object,
    [string]$Name,
    [int]$Default = 0
  )
  $value = Get-ManagerProp -Object $Object -Name $Name -Default $Default
  $parsed = 0
  if ([int]::TryParse([string]$value, [ref]$parsed)) { return $parsed }
  return $Default
}

function Convert-ManagerArray {
  param([object]$Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
}

function Encode-ManagerValue {
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

function Focus-GameWindow {
  try {
    $proc = Get-Process -Name "Game" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if ($null -ne $proc -and $null -ne ([type]"SebiSaveManagerNative")) {
      [void][SebiSaveManagerNative]::SetForegroundWindow($proc.MainWindowHandle)
    }
  } catch {
  }
}

function Send-ManagerCommand {
  param(
    [string]$Command,
    [hashtable]$Values = @{}
  )
  try {
    Ensure-ManagerRuntime
    $seq = [DateTime]::UtcNow.Ticks.ToString()
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add($seq)
    [void]$parts.Add($Command)
    foreach ($key in $Values.Keys) {
      [void]$parts.Add(("{0}={1}" -f $key, (Encode-ManagerValue ([string]$Values[$key]))))
    }
    [System.IO.File]::AppendAllText($script:CommandPath, (($parts -join "|") + "`n"), $script:Utf8NoBom)
    Focus-GameWindow
    return $seq
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      "No se pudo enviar el comando al juego: " + $_.Exception.Message,
      "Partidas SebiLink",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return $null
  }
}

function Repair-ManagerJsonText {
  param([string]$Json)
  if ([string]::IsNullOrWhiteSpace($Json)) { return $Json }
  return [regex]::Replace($Json, '\\(?!["\\/bfnrtu])', '\\')
}

function Read-ManagerIndex {
  try {
    Ensure-ManagerRuntime
    if (Test-Path -LiteralPath $script:IndexPath) {
      $json = [System.IO.File]::ReadAllText($script:IndexPath, [System.Text.Encoding]::UTF8)
      if (![string]::IsNullOrWhiteSpace($json)) {
        try {
          return ($json | ConvertFrom-Json)
        } catch {
          $repairedJson = Repair-ManagerJsonText -Json $json
          if ($repairedJson -ne $json) {
            return ($repairedJson | ConvertFrom-Json)
          }
        }
      }
    }
  } catch {
  }
  return [pscustomobject]@{
    generatedAt  = ""
    saveFolder   = ""
    backupFolder = ""
    items        = @()
    quickSlots   = @()
  }
}

function Read-ManagerJsonFile {
  param([string]$Path)
  try {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    $json = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    try {
      return ($json | ConvertFrom-Json)
    } catch {
      return ((Repair-ManagerJsonText -Json $json) | ConvertFrom-Json)
    }
  } catch {
    return $null
  }
}

function Load-ManagerImage {
  param([string]$Path)
  try {
    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    $image = [System.Drawing.Image]::FromStream($stream)
    $copy = New-Object System.Drawing.Bitmap($image)
    $image.Dispose()
    $stream.Dispose()
    return $copy
  } catch {
    return $null
  }
}

function Load-PokemonIconImage {
  param([string]$Path)
  $image = Load-ManagerImage -Path $Path
  if ($null -eq $image) { return $null }
  try {
    if ($image.Width -gt $image.Height) {
      $frameWidth = [Math]::Min($image.Height, [int]($image.Width / 2))
      if ($frameWidth -gt 0) {
        $frame = New-Object System.Drawing.Bitmap($frameWidth, $image.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($frame)
        $graphics.DrawImage($image, 0, 0, (New-Object System.Drawing.Rectangle(0, 0, $frameWidth, $image.Height)), [System.Drawing.GraphicsUnit]::Pixel)
        $graphics.Dispose()
        $image.Dispose()
        return $frame
      }
    }
  } catch {
  }
  return $image
}

function Set-ManagerPicture {
  param(
    [System.Windows.Forms.PictureBox]$PictureBox,
    [System.Drawing.Image]$Image
  )
  if ($null -eq $PictureBox) { return }
  $old = $PictureBox.Image
  $PictureBox.Image = $Image
  if ($null -ne $old) { $old.Dispose() }
}

function Get-PokemonIconPath {
  param([object]$Pokemon)
  $species = Get-ManagerInt -Object $Pokemon -Name "species" -Default 0
  if ($species -le 0) { return "" }
  $iconsDir = Join-Path $script:GameDir "Graphics\Icons"
  $normal = Join-Path $iconsDir ("icon{0:D3}.png" -f $species)
  $shiny = Join-Path $iconsDir ("icon{0:D3}s.png" -f $species)
  $isShiny = (Get-ManagerString -Object $Pokemon -Name "shiny") -ieq "true"
  if ($isShiny -and (Test-Path -LiteralPath $shiny)) { return $shiny }
  if (Test-Path -LiteralPath $normal) { return $normal }
  $empty = Join-Path $iconsDir "icon000.png"
  if (Test-Path -LiteralPath $empty) { return $empty }
  return ""
}

function Set-Tip {
  param($Control, [string]$Text)
  if ($null -eq $script:ToolTip) {
    $script:ToolTip = New-Object System.Windows.Forms.ToolTip
  }
  $script:ToolTip.SetToolTip($Control, $Text)
}

function Set-PreviewSlot {
  param(
    [System.Windows.Forms.PictureBox]$PictureBox,
    [object]$Pokemon
  )
  if ($null -eq $PictureBox) { return }
  if ($null -eq $Pokemon) {
    Set-ManagerPicture -PictureBox $PictureBox -Image $null
    $PictureBox.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
    $PictureBox.Tag = $null
    return
  }
  $icon = Get-PokemonIconPath -Pokemon $Pokemon
  Set-ManagerPicture -PictureBox $PictureBox -Image (Load-PokemonIconImage -Path $icon)
  $PictureBox.BackColor = [System.Drawing.Color]::FromArgb(229, 241, 236)
  $name = Get-ManagerString -Object $Pokemon -Name "name"
  $level = Get-ManagerInt -Object $Pokemon -Name "level" -Default 0
  $PictureBox.Tag = $Pokemon
  Set-Tip $PictureBox ("{0} Nv.{1}" -f $name, $level)
}

function New-PreviewSlotBox {
  $box = New-Object System.Windows.Forms.PictureBox
  $box.Dock = [System.Windows.Forms.DockStyle]::Fill
  $box.Margin = New-Object System.Windows.Forms.Padding(2)
  $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $box.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
  $box.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
  return $box
}

function Clear-SelectedPreview {
  $script:SelectedPreview = $null
  $script:SelectedPcBoxIndex = 0
  $script:LastPreviewPath = ""
  Set-ManagerPicture -PictureBox $script:LocationPicture -Image $null
  if ($null -ne $script:PcPreviewLabel) { $script:PcPreviewLabel.Text = "Caja PC" }
  foreach ($slot in $script:PartyPreviewSlots) { Set-PreviewSlot -PictureBox $slot -Pokemon $null }
  foreach ($slot in $script:PcPreviewSlots) { Set-PreviewSlot -PictureBox $slot -Pokemon $null }
}

function Get-PreviewBoxes {
  param([object]$Storage)
  $boxes = Convert-ManagerArray (Get-ManagerProp -Object $Storage -Name "boxes" -Default @())
  if ($boxes.Count -gt 0) { return @($boxes) }
  $currentBox = Get-ManagerInt -Object $Storage -Name "currentBox" -Default 0
  return @([pscustomobject]@{
    index = $currentBox
    name = Get-ManagerString -Object $Storage -Name "boxName" -Default "Caja PC"
    length = Get-ManagerInt -Object $Storage -Name "length" -Default 30
    pokemon = Convert-ManagerArray (Get-ManagerProp -Object $Storage -Name "pokemon" -Default @())
  })
}

function Update-PcPreviewSlots {
  if ($null -eq $script:SelectedPreview) {
    foreach ($slot in $script:PcPreviewSlots) { Set-PreviewSlot -PictureBox $slot -Pokemon $null }
    return
  }
  $storage = Get-ManagerProp -Object $script:SelectedPreview -Name "storage"
  $boxes = @(Get-PreviewBoxes -Storage $storage)
  if ($boxes.Count -eq 0) {
    foreach ($slot in $script:PcPreviewSlots) { Set-PreviewSlot -PictureBox $slot -Pokemon $null }
    return
  }
  if ($script:SelectedPcBoxIndex -lt 0) { $script:SelectedPcBoxIndex = 0 }
  if ($script:SelectedPcBoxIndex -ge $boxes.Count) { $script:SelectedPcBoxIndex = $boxes.Count - 1 }
  $box = $boxes[$script:SelectedPcBoxIndex]
  $boxIndex = Get-ManagerInt -Object $box -Name "index" -Default $script:SelectedPcBoxIndex
  $boxName = Get-ManagerString -Object $box -Name "name" -Default ("Caja " + ($boxIndex + 1))
  if ($null -ne $script:PcPreviewLabel) { $script:PcPreviewLabel.Text = ("{0} ({1})" -f $boxName, ($boxIndex + 1)) }
  $boxPokemon = Convert-ManagerArray (Get-ManagerProp -Object $box -Name "pokemon" -Default @())
  for ($i = 0; $i -lt $script:PcPreviewSlots.Count; $i++) {
    $pokemon = $null
    foreach ($p in $boxPokemon) {
      if ((Get-ManagerInt -Object $p -Name "slot" -Default -1) -eq $i) { $pokemon = $p; break }
    }
    Set-PreviewSlot -PictureBox $script:PcPreviewSlots[$i] -Pokemon $pokemon
  }
}

function Move-PcPreviewBox {
  param([int]$Delta)
  if ($null -eq $script:SelectedPreview) { return }
  $storage = Get-ManagerProp -Object $script:SelectedPreview -Name "storage"
  $boxes = @(Get-PreviewBoxes -Storage $storage)
  if ($boxes.Count -le 1) { return }
  $script:SelectedPcBoxIndex += $Delta
  if ($script:SelectedPcBoxIndex -lt 0) { $script:SelectedPcBoxIndex = $boxes.Count - 1 }
  if ($script:SelectedPcBoxIndex -ge $boxes.Count) { $script:SelectedPcBoxIndex = 0 }
  Update-PcPreviewSlots
}

function Read-SelectedPreview {
  param([object]$Item)
  if ($null -eq $Item) { return $null }
  $itemPath = Get-ManagerString -Object $Item -Name "path"
  $sidecar = Get-ManagerString -Object $Item -Name "previewPath"
  $preview = Read-ManagerJsonFile -Path $sidecar
  if ($null -eq $preview) { $preview = Read-ManagerJsonFile -Path $script:PreviewPath }
  if ($null -eq $preview) { return New-FallbackPreview -Item $Item }
  $previewPath = Get-ManagerString -Object $preview -Name "path"
  if (![string]::IsNullOrWhiteSpace($previewPath) -and $previewPath -ne $itemPath) { return New-FallbackPreview -Item $Item }
  return $preview
}

function New-FallbackPreview {
  param([object]$Item)
  if ($null -eq $Item) { return $null }
  return [pscustomobject]@{
    path = Get-ManagerString -Object $Item -Name "path"
    generatedAt = ""
    locationImage = Get-ManagerString -Object $Item -Name "locationImage"
    trainer = [pscustomobject]@{
      name = Get-ManagerString -Object $Item -Name "trainer"
      money = 0
      badges = 0
    }
    map = [pscustomobject]@{
      id = Get-ManagerInt -Object $Item -Name "mapId" -Default 0
      name = Get-ManagerString -Object $Item -Name "map"
    }
    position = [pscustomobject]@{ x = 0; y = 0; direction = 0 }
    party = @()
    storage = [pscustomobject]@{ currentBox = 0; boxName = "Caja PC"; length = 30; pokemon = @() }
  }
}

function Update-SelectedPreview {
  param([object]$Item)
  if ($null -eq $Item) {
    Clear-SelectedPreview
    return
  }
  $preview = Read-SelectedPreview -Item $Item
  if ($null -eq $preview) {
    Clear-SelectedPreview
    return
  }
  $script:SelectedPreview = $preview
  $script:LastPreviewPath = Get-ManagerString -Object $Item -Name "path"

  $locationImage = Get-ManagerString -Object $preview -Name "locationImage"
  Set-ManagerPicture -PictureBox $script:LocationPicture -Image (Load-ManagerImage -Path $locationImage)

  $storage = Get-ManagerProp -Object $preview -Name "storage"

  $party = Convert-ManagerArray (Get-ManagerProp -Object $preview -Name "party" -Default @())
  for ($i = 0; $i -lt $script:PartyPreviewSlots.Count; $i++) {
    $pokemon = $null
    foreach ($p in $party) {
      if ((Get-ManagerInt -Object $p -Name "index" -Default -1) -eq $i) { $pokemon = $p; break }
    }
    Set-PreviewSlot -PictureBox $script:PartyPreviewSlots[$i] -Pokemon $pokemon
  }

  $boxes = @(Get-PreviewBoxes -Storage $storage)
  $currentBox = Get-ManagerInt -Object $storage -Name "currentBox" -Default 0
  $script:SelectedPcBoxIndex = 0
  for ($i = 0; $i -lt $boxes.Count; $i++) {
    if ((Get-ManagerInt -Object $boxes[$i] -Name "index" -Default $i) -eq $currentBox) {
      $script:SelectedPcBoxIndex = $i
      break
    }
  }
  Update-PcPreviewSlots
}

function Request-PreviewForSelected {
  if ($script:RefreshingLists) { return }
  $item = Get-SelectedSave
  if ($null -eq $item) {
    Clear-SelectedPreview
    return
  }
  $path = Get-ManagerString -Object $item -Name "path"
  if ($path -ne "" -and $path -eq $script:LastPreviewPath -and $null -ne $script:SelectedPreview) { return }
  Update-SelectedPreview -Item $item
}

function Request-PreviewForQuickCombo {
  if ($script:RefreshingLists) { return }
  if ($null -ne $script:MainTabs -and $null -ne $script:QuickPage -and $script:MainTabs.SelectedTab -ne $script:QuickPage) { return }
  Move-PreviewRootToHost $script:QuickPreviewHost
  $item = Get-SelectedQuickSave
  if ($null -eq $item) { Clear-SelectedPreview; return }
  Update-SelectedPreview -Item $item
}

function Request-PreviewForQuickRow {
  if ($script:RefreshingLists) { return }
  if ($null -ne $script:MainTabs -and $null -ne $script:QuickPage -and $script:MainTabs.SelectedTab -ne $script:QuickPage) { return }
  Move-PreviewRootToHost $script:QuickPreviewHost
  $item = Get-SelectedQuickSlotSave
  if ($null -eq $item) { $item = Get-SelectedQuickSave }
  if ($null -eq $item) { Clear-SelectedPreview; return }
  Update-SelectedPreview -Item $item
}

function Get-ManagerTypeLabel {
  param([string]$Type)
  if ($Type -ieq "save") { return "Partida" }
  if ($Type -ieq "backup") { return "Respaldo" }
  return $Type
}

function Get-ManagerKeyName {
  param([int]$Code)
  if ($Code -eq 0) { return "Sin tecla" }
  try {
    return ([System.Windows.Forms.Keys]$Code).ToString()
  } catch {
    return ("0x{0:X2}" -f $Code)
  }
}

function Format-ManagerItemLabel {
  param([object]$Item)
  if ($null -eq $Item) { return "" }
  $type = Get-ManagerTypeLabel (Get-ManagerString -Object $Item -Name "type")
  $slot = Get-ManagerInt -Object $Item -Name "slot" -Default 0
  $time = Get-ManagerString -Object $Item -Name "timestamp"
  $trainer = Get-ManagerString -Object $Item -Name "trainer"
  $description = Get-ManagerString -Object $Item -Name "description"
  $name = Get-ManagerString -Object $Item -Name "name"
  $label = "{0} {1} | {2}" -f $type, $slot, $time
  if (![string]::IsNullOrWhiteSpace($trainer) -and $trainer -ne "?") {
    $label += " | " + $trainer
  }
  if (![string]::IsNullOrWhiteSpace($description)) {
    $label += " | " + $description
  }
  if (![string]::IsNullOrWhiteSpace($name)) {
    $label += " | " + $name
  }
  return $label
}

function Set-ManagerStatus {
  param([string]$Text)
  if ($null -ne $script:StatusLabel) {
    $script:StatusLabel.Text = $Text
  }
}

function Start-DelayedRefresh {
  if ($null -eq $script:RefreshTimer) { return }
  $script:RefreshTicks = 0
  $script:PreviewRefreshTicks = 0
  $script:LastPreviewPath = ""
  $script:RefreshTimer.Stop()
  $script:RefreshTimer.Start()
}

function Find-ManagerItemByPath {
  param([string]$Path, [object]$Fallback = $null)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $items = Convert-ManagerArray (Get-ManagerProp -Object $script:IndexData -Name "items" -Default @())
  foreach ($item in $items) {
    if ((Get-ManagerString -Object $item -Name "path") -eq $Path) { return $item }
  }
  if ($null -ne $Fallback) {
    return [pscustomobject]@{
      path = $Path
      type = "quick"
      name = Get-ManagerString -Object $Fallback -Name "label"
      timestamp = ""
      description = Get-ManagerString -Object $Fallback -Name "label"
    }
  }
  return $null
}

function Get-SelectedQuickSlotSave {
  $slotData = Get-SelectedQuickSlot
  if ($null -eq $slotData) { return $null }
  $path = Get-ManagerString -Object $slotData -Name "path"
  return Find-ManagerItemByPath -Path $path -Fallback $slotData
}

function Get-SelectedSave {
  if ($null -ne $script:MainTabs -and $null -ne $script:QuickPage -and $script:MainTabs.SelectedTab -eq $script:QuickPage) {
    $quickSlotItem = Get-SelectedQuickSlotSave
    if ($null -ne $quickSlotItem) { return $quickSlotItem }
    return Get-SelectedQuickSave
  }
  if ($null -ne $script:LoadList -and $script:LoadList.SelectedItems.Count -gt 0) {
    return $script:LoadList.SelectedItems[0].Tag
  }
  if ($null -ne $script:QuickSaveCombo -and $null -ne $script:QuickSaveCombo.SelectedItem) {
    return $script:QuickSaveCombo.SelectedItem.Item
  }
  return $null
}

function Move-PreviewRootToHost {
  param($TargetHost)
  if ($null -eq $TargetHost -or $null -eq $script:PreviewRoot) { return }
  if ($script:PreviewRoot.Parent -ne $TargetHost) {
    if ($null -ne $script:PreviewRoot.Parent) {
      $script:PreviewRoot.Parent.Controls.Remove($script:PreviewRoot)
    }
    $TargetHost.Controls.Add($script:PreviewRoot)
  }
  $script:PreviewRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
}

function Get-SelectedQuickSave {
  if ($null -ne $script:QuickSaveCombo -and $null -ne $script:QuickSaveCombo.SelectedItem) {
    return $script:QuickSaveCombo.SelectedItem.Item
  }
  return $null
}

function Get-SelectedQuickSlot {
  if ($null -eq $script:QuickList -or $script:QuickList.SelectedItems.Count -eq 0) { return $null }
  return $script:QuickList.SelectedItems[0].Tag
}

function Get-DisplayQuickSlots {
  param([object[]]$Slots)
  $bySlot = @{}
  foreach ($slotData in @($Slots)) {
    $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
    if ($slot -ge 1 -and $slot -le 9) { $bySlot[$slot] = $slotData }
  }
  $ret = @()
  for ($slot = 1; $slot -le 9; $slot++) {
    if ($bySlot.ContainsKey($slot)) {
      $ret += $bySlot[$slot]
    } else {
      $ret += [pscustomobject]@{
        slot = $slot
        path = ""
        exists = $false
        key = 0
        keyName = "Sin tecla"
        label = ""
      }
    }
  }
  return @($ret)
}

function Refresh-ManagerLists {
  $script:IndexData = Read-ManagerIndex
  $items = Convert-ManagerArray (Get-ManagerProp -Object $script:IndexData -Name "items" -Default @())
  $slots = Get-DisplayQuickSlots -Slots (Convert-ManagerArray (Get-ManagerProp -Object $script:IndexData -Name "quickSlots" -Default @()))

  if ($null -ne $script:LoadList) {
    $selectedPath = ""
    if ($script:LoadList.SelectedItems.Count -gt 0) {
      $selectedPath = Get-ManagerString -Object $script:LoadList.SelectedItems[0].Tag -Name "path"
    }
    $script:RefreshingLists = $true
    $script:LoadList.BeginUpdate()
    try {
      $script:LoadList.Items.Clear()
      foreach ($item in $items) {
        $type = Get-ManagerTypeLabel (Get-ManagerString -Object $item -Name "type")
        $row = New-Object System.Windows.Forms.ListViewItem($type)
        [void]$row.SubItems.Add((Get-ManagerString -Object $item -Name "name"))
        [void]$row.SubItems.Add((Get-ManagerString -Object $item -Name "timestamp"))
        [void]$row.SubItems.Add((Get-ManagerString -Object $item -Name "description"))
        $row.Tag = $item
        [void]$script:LoadList.Items.Add($row)
        if ((Get-ManagerString -Object $item -Name "path") -eq $selectedPath) {
          $row.Selected = $true
        }
      }
    } finally {
      $script:LoadList.EndUpdate()
      $script:RefreshingLists = $false
    }
  }

  if ($null -ne $script:QuickSaveCombo) {
    $oldPath = ""
    if ($null -ne $script:QuickSaveCombo.SelectedItem) {
      $oldPath = [string]$script:QuickSaveCombo.SelectedItem.Path
    }
    $script:QuickSaveCombo.Items.Clear()
    foreach ($item in $items) {
      $entry = [pscustomobject]@{
        Text = Format-ManagerItemLabel -Item $item
        Path = Get-ManagerString -Object $item -Name "path"
        Item = $item
      }
      [void]$script:QuickSaveCombo.Items.Add($entry)
      if ($entry.Path -eq $oldPath) {
        $script:QuickSaveCombo.SelectedItem = $entry
      }
    }
    if ($script:QuickSaveCombo.Items.Count -gt 0 -and $null -eq $script:QuickSaveCombo.SelectedItem) {
      $script:QuickSaveCombo.SelectedIndex = 0
    }
  }

  if ($null -ne $script:QuickList) {
    $selectedSlot = 0
    if ($script:QuickList.SelectedItems.Count -gt 0) {
      $selectedSlot = Get-ManagerInt -Object $script:QuickList.SelectedItems[0].Tag -Name "slot" -Default 0
    }
    $script:QuickList.BeginUpdate()
    try {
      $script:QuickList.Items.Clear()
      foreach ($slotData in $slots) {
        $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
        $label = Get-ManagerString -Object $slotData -Name "label"
        if ([string]::IsNullOrWhiteSpace($label)) { $label = "Sin partida asignada" }
        $row = New-Object System.Windows.Forms.ListViewItem(("Partida rapida {0}" -f $slot))
        [void]$row.SubItems.Add((Get-ManagerString -Object $slotData -Name "keyName" -Default "Sin tecla"))
        [void]$row.SubItems.Add($label)
        $exists = Get-ManagerString -Object $slotData -Name "exists"
        [void]$row.SubItems.Add($(if ((Get-ManagerString -Object $slotData -Name "path") -eq "") { "-" } elseif ($exists -ieq "true") { "Si" } else { "No" }))
        $row.Tag = $slotData
        [void]$script:QuickList.Items.Add($row)
        if ($slot -eq $selectedSlot) {
          $row.Selected = $true
        }
      }
      if ($script:QuickList.Items.Count -gt 0 -and $script:QuickList.SelectedItems.Count -eq 0) {
        $script:QuickList.Items[0].Selected = $true
      }
    } finally {
      $script:QuickList.EndUpdate()
    }
  }

  $generatedAt = Get-ManagerString -Object $script:IndexData -Name "generatedAt"
  if ([string]::IsNullOrWhiteSpace($generatedAt)) {
    Set-ManagerStatus "Sin lista del juego. Abre esta ventana desde Pokemon Z para cargar los datos."
  } else {
    Set-ManagerStatus ("Lista actualizada: {0}. {1} partidas y respaldos." -f $generatedAt, @($items).Count)
  }
}

function Show-TextPrompt {
  param(
    [string]$Title,
    [string]$Message,
    [string]$Default = ""
  )

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = $Title
  $dialog.StartPosition = "CenterParent"
  $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.Size = New-Object System.Drawing.Size(430, 160)
  if ($null -ne $script:GameIcon) { $dialog.Icon = $script:GameIcon }

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Message
  $label.Location = New-Object System.Drawing.Point(12, 12)
  $label.Size = New-Object System.Drawing.Size(390, 22)
  $dialog.Controls.Add($label)

  $textBox = New-Object System.Windows.Forms.TextBox
  $textBox.Location = New-Object System.Drawing.Point(12, 38)
  $textBox.Size = New-Object System.Drawing.Size(390, 24)
  $textBox.Text = $Default
  $textBox.MaxLength = 160
  $dialog.Controls.Add($textBox)

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = "Aceptar"
  $ok.Location = New-Object System.Drawing.Point(226, 82)
  $ok.Size = New-Object System.Drawing.Size(82, 28)
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($ok)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "Cancelar"
  $cancel.Location = New-Object System.Drawing.Point(320, 82)
  $cancel.Size = New-Object System.Drawing.Size(82, 28)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancel)

  $dialog.AcceptButton = $ok
  $dialog.CancelButton = $cancel

  if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
    return $textBox.Text
  }
  return $null
}

function Show-KeyPrompt {
  param(
    [int]$CurrentKey = 0
  )

  $state = [pscustomobject]@{ Key = $CurrentKey }
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "Tecla de partida rapida"
  $dialog.StartPosition = "CenterParent"
  $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.KeyPreview = $true
  $dialog.Size = New-Object System.Drawing.Size(390, 165)
  if ($null -ne $script:GameIcon) { $dialog.Icon = $script:GameIcon }

  $label = New-Object System.Windows.Forms.Label
  $label.Text = "Pulsa una tecla para este acceso rapido."
  $label.Location = New-Object System.Drawing.Point(12, 12)
  $label.Size = New-Object System.Drawing.Size(350, 22)
  $dialog.Controls.Add($label)

  $keyLabel = New-Object System.Windows.Forms.Label
  $keyLabel.Text = "Tecla: " + (Get-ManagerKeyName -Code $CurrentKey)
  $keyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
  $keyLabel.Location = New-Object System.Drawing.Point(12, 42)
  $keyLabel.Size = New-Object System.Drawing.Size(350, 28)
  $dialog.Controls.Add($keyLabel)

  $use = New-Object System.Windows.Forms.Button
  $use.Text = "Usar tecla"
  $use.Location = New-Object System.Drawing.Point(86, 88)
  $use.Size = New-Object System.Drawing.Size(88, 28)
  $use.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($use)

  $clear = New-Object System.Windows.Forms.Button
  $clear.Text = "Sin tecla"
  $clear.Location = New-Object System.Drawing.Point(180, 88)
  $clear.Size = New-Object System.Drawing.Size(82, 28)
  $clear.Add_Click({
    $state.Key = 0
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $dialog.Controls.Add($clear)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "Cancelar"
  $cancel.Location = New-Object System.Drawing.Point(268, 88)
  $cancel.Size = New-Object System.Drawing.Size(82, 28)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancel)

  $dialog.CancelButton = $cancel
  $dialog.Add_KeyDown({
    param($sender, $eventArgs)
    $state.Key = [int]$eventArgs.KeyValue
    $keyLabel.Text = "Tecla: " + (Get-ManagerKeyName -Code $state.Key)
    $eventArgs.SuppressKeyPress = $true
  })

  if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
    return [int]$state.Key
  }
  return $null
}

function Show-LoadConfirm {
  param([string]$SaveLabel)

  $state = [pscustomobject]@{ Choice = "cancel" }
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "Cargar partida"
  $dialog.StartPosition = "CenterParent"
  $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false
  $dialog.Size = New-Object System.Drawing.Size(540, 175)
  if ($null -ne $script:GameIcon) { $dialog.Icon = $script:GameIcon }

  $label = New-Object System.Windows.Forms.Label
  $label.Text = "Seguro que quieres cargar esta partida? Se perderan los cambios no guardados de la partida actual."
  $label.Location = New-Object System.Drawing.Point(14, 12)
  $label.Size = New-Object System.Drawing.Size(498, 38)
  $dialog.Controls.Add($label)

  $saveText = New-Object System.Windows.Forms.Label
  $saveText.Text = $SaveLabel
  $saveText.Location = New-Object System.Drawing.Point(14, 52)
  $saveText.Size = New-Object System.Drawing.Size(498, 22)
  $saveText.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
  $dialog.Controls.Add($saveText)

  $yes = New-Object System.Windows.Forms.Button
  $yes.Text = "Si"
  $yes.Location = New-Object System.Drawing.Point(158, 92)
  $yes.Size = New-Object System.Drawing.Size(72, 30)
  $yes.Add_Click({
    $state.Choice = "load"
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $dialog.Controls.Add($yes)

  $backup = New-Object System.Windows.Forms.Button
  $backup.Text = "Si y copia antes"
  $backup.Location = New-Object System.Drawing.Point(238, 92)
  $backup.Size = New-Object System.Drawing.Size(126, 30)
  $backup.Add_Click({
    $state.Choice = "backup"
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $dialog.Controls.Add($backup)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = "Cancelar"
  $cancel.Location = New-Object System.Drawing.Point(372, 92)
  $cancel.Size = New-Object System.Drawing.Size(88, 30)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancel)

  $dialog.AcceptButton = $backup
  $dialog.CancelButton = $cancel
  [void]$dialog.ShowDialog($script:Form)
  return $state.Choice
}

function Request-ManagerRefresh {
  [void](Send-ManagerCommand -Command "refresh_index")
  Set-ManagerStatus "Actualizacion solicitada al juego..."
  Start-DelayedRefresh
}

function Invoke-LoadSelectedSave {
  $item = Get-SelectedSave
  if ($null -eq $item) {
    Set-ManagerStatus "Selecciona una partida o respaldo."
    return
  }
  $path = Get-ManagerString -Object $item -Name "path"
  if ([string]::IsNullOrWhiteSpace($path)) { return }
  $choice = Show-LoadConfirm -SaveLabel (Format-ManagerItemLabel -Item $item)
  if ($choice -eq "cancel") { return }
  [void](Send-ManagerCommand -Command "restore_path" -Values @{ path = $path; backupCurrent = $(if ($choice -eq "backup") { "true" } else { "false" }) })
  Set-ManagerStatus "Carga enviada al juego..."
  Start-DelayedRefresh
}

function Invoke-CreateBackup {
  $description = Show-TextPrompt -Title "Crear respaldo" -Message "Descripcion opcional:" -Default ""
  if ($null -eq $description) { return }
  [void](Send-ManagerCommand -Command "create_backup" -Values @{ description = $description })
  Set-ManagerStatus "Respaldo manual solicitado..."
  Start-DelayedRefresh
}

function Invoke-EditDescription {
  $item = Get-SelectedSave
  if ($null -eq $item) {
    Set-ManagerStatus "Selecciona una partida o respaldo."
    return
  }
  $path = Get-ManagerString -Object $item -Name "path"
  $current = Get-ManagerString -Object $item -Name "description"
  $description = Show-TextPrompt -Title "Descripcion" -Message "Descripcion de esta partida:" -Default $current
  if ($null -eq $description) { return }
  [void](Send-ManagerCommand -Command "set_description" -Values @{ path = $path; description = $description })
  Set-ManagerStatus "Descripcion enviada al juego..."
  Start-DelayedRefresh
}

function Invoke-EditSelectedSave {
  $item = Get-SelectedSave
  if ($null -eq $item) {
    Set-ManagerStatus "Selecciona una partida para editar."
    return
  }
  $path = Get-ManagerString -Object $item -Name "path"
  if ([string]::IsNullOrWhiteSpace($path)) { return }
  $result = [System.Windows.Forms.MessageBox]::Show(
    $script:Form,
    "Se abrira esta partida en SebiHeX sin cargarla en el juego. Al guardar, SebiHeX escribira sobre el mismo archivo seleccionado.",
    "Editar partida",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
  if ($result -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  [void](Send-ManagerCommand -Command "edit_path" -Values @{ path = $path })
  Set-ManagerStatus "Abriendo partida seleccionada en SebiHeX..."
  Start-DelayedRefresh
}

function Invoke-AssignQuickSlot {
  $slotData = Get-SelectedQuickSlot
  $item = Get-SelectedQuickSave
  if ($null -eq $slotData) {
    Set-ManagerStatus "Selecciona una partida rapida."
    return
  }
  if ($null -eq $item) {
    Set-ManagerStatus "Selecciona una partida o respaldo para asignar."
    return
  }
  $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
  $path = Get-ManagerString -Object $item -Name "path"
  [void](Send-ManagerCommand -Command "assign_quick_slot" -Values @{ slot = $slot; path = $path })
  Set-ManagerStatus ("Asignando partida rapida {0}..." -f $slot)
  Start-DelayedRefresh
}

function Invoke-LoadQuickSlot {
  $slotData = Get-SelectedQuickSlot
  if ($null -eq $slotData) {
    Set-ManagerStatus "Selecciona una partida rapida."
    return
  }
  $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
  $choice = Show-LoadConfirm -SaveLabel ("Partida rapida {0}" -f $slot)
  if ($choice -eq "cancel") { return }
  [void](Send-ManagerCommand -Command "load_quick_slot" -Values @{ slot = $slot; backupCurrent = $(if ($choice -eq "backup") { "true" } else { "false" }) })
  Set-ManagerStatus ("Carga rapida {0} enviada..." -f $slot)
  Start-DelayedRefresh
}

function Invoke-ChangeQuickKey {
  $slotData = Get-SelectedQuickSlot
  if ($null -eq $slotData) {
    Set-ManagerStatus "Selecciona una partida rapida."
    return
  }
  $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
  $currentKey = Get-ManagerInt -Object $slotData -Name "key" -Default 0
  $newKey = Show-KeyPrompt -CurrentKey $currentKey
  if ($null -eq $newKey) { return }
  [void](Send-ManagerCommand -Command "set_quick_key" -Values @{ slot = $slot; key = [int]$newKey })
  Set-ManagerStatus ("Cambiando tecla de partida rapida {0}..." -f $slot)
  Start-DelayedRefresh
}

function Invoke-ClearQuickSlot {
  $slotData = Get-SelectedQuickSlot
  if ($null -eq $slotData) {
    Set-ManagerStatus "Selecciona una partida rapida."
    return
  }
  $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
  [void](Send-ManagerCommand -Command "clear_quick_slot" -Values @{ slot = $slot })
  Set-ManagerStatus ("Limpiando partida rapida {0}..." -f $slot)
  Start-DelayedRefresh
}

function Invoke-MoveQuickSlot {
  param([int]$Direction)
  $slotData = Get-SelectedQuickSlot
  if ($null -eq $slotData) {
    Set-ManagerStatus "Selecciona una partida rapida."
    return
  }
  $slot = Get-ManagerInt -Object $slotData -Name "slot" -Default 0
  [void](Send-ManagerCommand -Command "move_quick_slot" -Values @{ slot = $slot; direction = $Direction })
  Set-ManagerStatus ("Moviendo partida rapida {0}..." -f $slot)
  Start-DelayedRefresh
}

if ($SelfTest) {
  Ensure-ManagerRuntime
  $encoded = Encode-ManagerValue "a b|c"
  if ($encoded -ne "a+b%7Cc") {
    throw "La codificacion de comandos del gestor de partidas no es correcta."
  }
  $repaired = Repair-ManagerJsonText '{"path":"C:\Test\Saved Games"}'
  $parsed = $repaired | ConvertFrom-Json
  if ($parsed.path -ne "C:\Test\Saved Games") {
    throw "La reparacion de rutas Windows del indice no es correcta."
  }
  $testSlots = Get-DisplayQuickSlots -Slots @()
  if (@($testSlots).Count -ne 9) {
    throw "La vista de partidas rapidas no rellena los 9 slots vacios."
  }
  Write-Host "SebiSaveManager.ps1 OK"
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = "Partidas SebiLink"
$script:Form.StartPosition = "CenterScreen"
$script:Form.Size = New-Object System.Drawing.Size(860, 780)
$script:Form.MinimumSize = New-Object System.Drawing.Size(760, 660)
$script:Form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 248)
if ($null -ne $script:GameIcon) {
  $script:Form.Icon = $script:GameIcon
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount = 3
$root.Padding = New-Object System.Windows.Forms.Padding(10)
[void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$script:Form.Controls.Add($root)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.Controls.Add($top, 0, 0)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Partidas SebiLink"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(0, 0)
$title.Size = New-Object System.Drawing.Size(260, 28)
$top.Controls.Add($title)

$topMostCheck = New-Object System.Windows.Forms.CheckBox
$topMostCheck.Text = "Siempre encima"
$topMostCheck.Location = New-Object System.Drawing.Point(668, 3)
$topMostCheck.Size = New-Object System.Drawing.Size(130, 24)
$topMostCheck.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$top.Controls.Add($topMostCheck)

$script:MainTabs = New-Object System.Windows.Forms.TabControl
$script:MainTabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.Controls.Add($script:MainTabs, 0, 1)

$loadPage = New-Object System.Windows.Forms.TabPage
$loadPage.Text = "Cargar partida"
$script:LoadPage = $loadPage
[void]$script:MainTabs.TabPages.Add($loadPage)

$quickPage = New-Object System.Windows.Forms.TabPage
$quickPage.Text = "Partidas rapidas"
$script:QuickPage = $quickPage
[void]$script:MainTabs.TabPages.Add($quickPage)

$loadTab = New-Object System.Windows.Forms.Panel
$loadTab.Dock = [System.Windows.Forms.DockStyle]::Fill
$loadTab.Padding = New-Object System.Windows.Forms.Padding(8)
$loadPage.Controls.Add($loadTab)

$loadLayout = New-Object System.Windows.Forms.TableLayoutPanel
$loadLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$loadLayout.ColumnCount = 1
$loadLayout.RowCount = 3
[void]$loadLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 54)))
[void]$loadLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$loadLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 46)))
$loadTab.Controls.Add($loadLayout)

$script:LoadList = New-Object System.Windows.Forms.ListView
$script:LoadList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LoadList.View = [System.Windows.Forms.View]::Details
$script:LoadList.FullRowSelect = $true
$script:LoadList.HideSelection = $false
$script:LoadList.MultiSelect = $false
$script:LoadList.GridLines = $true
[void]$script:LoadList.Columns.Add("Tipo", 78)
[void]$script:LoadList.Columns.Add("Archivo", 230)
[void]$script:LoadList.Columns.Add("Fecha", 140)
[void]$script:LoadList.Columns.Add("Descripcion", 315)
$script:LoadList.Add_SelectedIndexChanged({ Request-PreviewForSelected })
$script:LoadList.Add_DoubleClick({ Request-PreviewForSelected })
$loadLayout.Controls.Add($script:LoadList, 0, 0)

$loadButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$loadButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
$loadButtons.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$loadButtons.WrapContents = $false
$loadLayout.Controls.Add($loadButtons, 0, 1)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Actualizar"
$refreshButton.Size = New-Object System.Drawing.Size(96, 28)
$refreshButton.Add_Click({ Request-ManagerRefresh })
[void]$loadButtons.Controls.Add($refreshButton)

$loadButton = New-Object System.Windows.Forms.Button
$loadButton.Text = "Cargar seleccion"
$loadButton.Size = New-Object System.Drawing.Size(128, 28)
$loadButton.Add_Click({ Invoke-LoadSelectedSave })
[void]$loadButtons.Controls.Add($loadButton)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "Crear respaldo"
$backupButton.Size = New-Object System.Drawing.Size(112, 28)
$backupButton.Add_Click({ Invoke-CreateBackup })
[void]$loadButtons.Controls.Add($backupButton)

$descriptionButton = New-Object System.Windows.Forms.Button
$descriptionButton.Text = "Descripcion"
$descriptionButton.Size = New-Object System.Drawing.Size(104, 28)
$descriptionButton.Add_Click({ Invoke-EditDescription })
[void]$loadButtons.Controls.Add($descriptionButton)

$editButton = New-Object System.Windows.Forms.Button
$editButton.Text = "Editar partida"
$editButton.Size = New-Object System.Drawing.Size(112, 28)
$editButton.Add_Click({ Invoke-EditSelectedSave })
[void]$loadButtons.Controls.Add($editButton)

$script:LoadPreviewHost = New-Object System.Windows.Forms.Panel
$script:LoadPreviewHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$loadLayout.Controls.Add($script:LoadPreviewHost, 0, 2)

$previewRoot = New-Object System.Windows.Forms.TableLayoutPanel
$previewRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
$previewRoot.ColumnCount = 3
$previewRoot.RowCount = 2
$previewRoot.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
[void]$previewRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 36)))
[void]$previewRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 14)))
[void]$previewRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$previewRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 26)))
[void]$previewRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:PreviewRoot = $previewRoot
$script:LoadPreviewHost.Controls.Add($previewRoot)

$previewTitle = New-Object System.Windows.Forms.Label
$previewTitle.Text = "Datos de la partida seleccionada"
$previewTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$previewTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$previewTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
[void]$previewRoot.Controls.Add($previewTitle, 0, 0)

$partyTitle = New-Object System.Windows.Forms.Label
$partyTitle.Text = "Equipo"
$partyTitle.Dock = [System.Windows.Forms.DockStyle]::Fill
$partyTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
[void]$previewRoot.Controls.Add($partyTitle, 1, 0)

$script:PcPreviewLabel = New-Object System.Windows.Forms.Label
$script:PcPreviewLabel.Text = "Caja PC"
$script:PcPreviewLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PcPreviewLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
[void]$previewRoot.Controls.Add($script:PcPreviewLabel, 2, 0)

$script:LocationPicture = New-Object System.Windows.Forms.PictureBox
$script:LocationPicture.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LocationPicture.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$script:LocationPicture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:LocationPicture.BackColor = [System.Drawing.Color]::FromArgb(246, 247, 249)
$script:LocationPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$previewRoot.Controls.Add($script:LocationPicture, 0, 1)

$partyPanel = New-Object System.Windows.Forms.TableLayoutPanel
$partyPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$partyPanel.ColumnCount = 2
$partyPanel.RowCount = 3
for ($i = 0; $i -lt 2; $i++) { [void]$partyPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) }
for ($i = 0; $i -lt 3; $i++) { [void]$partyPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 33.33))) }
for ($i = 0; $i -lt 6; $i++) {
  $slotBox = New-PreviewSlotBox
  $script:PartyPreviewSlots += $slotBox
  [void]$partyPanel.Controls.Add($slotBox, ($i % 2), [Math]::Floor($i / 2))
}
[void]$previewRoot.Controls.Add($partyPanel, 1, 1)

$pcArea = New-Object System.Windows.Forms.TableLayoutPanel
$pcArea.Dock = [System.Windows.Forms.DockStyle]::Fill
$pcArea.RowCount = 2
$pcArea.ColumnCount = 1
[void]$pcArea.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$pcArea.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 32)))
[void]$pcArea.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$pcPanel = New-Object System.Windows.Forms.TableLayoutPanel
$pcPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$pcPanel.ColumnCount = 6
$pcPanel.RowCount = 5
for ($i = 0; $i -lt 6; $i++) { [void]$pcPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 16.66))) }
for ($i = 0; $i -lt 5; $i++) { [void]$pcPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20))) }
for ($i = 0; $i -lt 30; $i++) {
  $slotBox = New-PreviewSlotBox
  $script:PcPreviewSlots += $slotBox
  [void]$pcPanel.Controls.Add($slotBox, ($i % 6), [Math]::Floor($i / 6))
}
[void]$pcArea.Controls.Add($pcPanel, 0, 0)

$pcButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$pcButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
$pcButtons.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$pcButtons.WrapContents = $false
$pcButtons.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
[void]$pcArea.Controls.Add($pcButtons, 0, 1)

$prevBoxButton = New-Object System.Windows.Forms.Button
$prevBoxButton.Text = "Caja anterior"
$prevBoxButton.Size = New-Object System.Drawing.Size(108, 26)
$prevBoxButton.Add_Click({ Move-PcPreviewBox -Delta -1 })
[void]$pcButtons.Controls.Add($prevBoxButton)

$nextBoxButton = New-Object System.Windows.Forms.Button
$nextBoxButton.Text = "Caja siguiente"
$nextBoxButton.Size = New-Object System.Drawing.Size(112, 26)
$nextBoxButton.Add_Click({ Move-PcPreviewBox -Delta 1 })
[void]$pcButtons.Controls.Add($nextBoxButton)

[void]$previewRoot.Controls.Add($pcArea, 2, 1)

$quickPanel = New-Object System.Windows.Forms.Panel
$quickPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$quickPanel.Padding = New-Object System.Windows.Forms.Padding(8)
$quickPage.Controls.Add($quickPanel)

$quickLayout = New-Object System.Windows.Forms.TableLayoutPanel
$quickLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$quickLayout.ColumnCount = 1
$quickLayout.RowCount = 5
[void]$quickLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
[void]$quickLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 232)))
[void]$quickLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
[void]$quickLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$quickLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$quickPanel.Controls.Add($quickLayout)

$quickLabel = New-Object System.Windows.Forms.Label
$quickLabel.Text = "Accesos rapidos de partida"
$quickLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$quickLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$quickLayout.Controls.Add($quickLabel, 0, 0)

$script:QuickList = New-Object System.Windows.Forms.ListView
$script:QuickList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:QuickList.View = [System.Windows.Forms.View]::Details
$script:QuickList.FullRowSelect = $true
$script:QuickList.HideSelection = $false
$script:QuickList.MultiSelect = $false
$script:QuickList.GridLines = $true
$script:QuickList.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$script:QuickList.UseCompatibleStateImageBehavior = $false
$quickRowImages = New-Object System.Windows.Forms.ImageList
$quickRowImages.ImageSize = New-Object System.Drawing.Size(1, 22)
$quickRowImages.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
[void]$quickRowImages.Images.Add((New-Object System.Drawing.Bitmap(1, 22)))
$script:QuickList.SmallImageList = $quickRowImages
[void]$script:QuickList.Columns.Add("Slot", 124)
[void]$script:QuickList.Columns.Add("Tecla", 92)
[void]$script:QuickList.Columns.Add("Partida", 455)
[void]$script:QuickList.Columns.Add("Existe", 64)
$script:QuickList.Add_SelectedIndexChanged({ Request-PreviewForQuickRow })
$quickLayout.Controls.Add($script:QuickList, 0, 1)

$script:QuickSaveCombo = New-Object System.Windows.Forms.ComboBox
$script:QuickSaveCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:QuickSaveCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:QuickSaveCombo.DisplayMember = "Text"
$script:QuickSaveCombo.Add_SelectedIndexChanged({ Request-PreviewForQuickCombo })
$quickLayout.Controls.Add($script:QuickSaveCombo, 0, 2)

$quickButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$quickButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
$quickButtons.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$quickButtons.WrapContents = $false
$quickLayout.Controls.Add($quickButtons, 0, 3)

$script:QuickPreviewHost = New-Object System.Windows.Forms.Panel
$script:QuickPreviewHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:QuickPreviewHost.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
$quickLayout.Controls.Add($script:QuickPreviewHost, 0, 4)

$assignButton = New-Object System.Windows.Forms.Button
$assignButton.Text = "Crear/asignar"
$assignButton.Size = New-Object System.Drawing.Size(128, 28)
$assignButton.Add_Click({ Invoke-AssignQuickSlot })
[void]$quickButtons.Controls.Add($assignButton)

$quickLoadButton = New-Object System.Windows.Forms.Button
$quickLoadButton.Text = "Cargar slot"
$quickLoadButton.Size = New-Object System.Drawing.Size(94, 28)
$quickLoadButton.Add_Click({ Invoke-LoadQuickSlot })
[void]$quickButtons.Controls.Add($quickLoadButton)

$keyButton = New-Object System.Windows.Forms.Button
$keyButton.Text = "Cambiar tecla"
$keyButton.Size = New-Object System.Drawing.Size(112, 28)
$keyButton.Add_Click({ Invoke-ChangeQuickKey })
[void]$quickButtons.Controls.Add($keyButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "Eliminar acceso"
$clearButton.Size = New-Object System.Drawing.Size(118, 28)
$clearButton.Add_Click({ Invoke-ClearQuickSlot })
[void]$quickButtons.Controls.Add($clearButton)

$quickUpButton = New-Object System.Windows.Forms.Button
$quickUpButton.Text = "Subir"
$quickUpButton.Size = New-Object System.Drawing.Size(72, 28)
$quickUpButton.Add_Click({ Invoke-MoveQuickSlot -Direction -1 })
[void]$quickButtons.Controls.Add($quickUpButton)

$quickDownButton = New-Object System.Windows.Forms.Button
$quickDownButton.Text = "Bajar"
$quickDownButton.Size = New-Object System.Drawing.Size(72, 28)
$quickDownButton.Add_Click({ Invoke-MoveQuickSlot -Direction 1 })
[void]$quickButtons.Controls.Add($quickDownButton)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$root.Controls.Add($script:StatusLabel, 0, 2)

$script:RefreshTimer = New-Object System.Windows.Forms.Timer
$script:RefreshTimer.Interval = 900
$script:RefreshTimer.Add_Tick({
  Refresh-ManagerLists
  if ($script:MainTabs.SelectedTab -eq $script:QuickPage) {
    Move-PreviewRootToHost $script:QuickPreviewHost
  } else {
    Move-PreviewRootToHost $script:LoadPreviewHost
  }
  Update-SelectedPreview -Item (Get-SelectedSave)
  $script:RefreshTicks = 0
  $script:PreviewRefreshTicks = 0
  $script:RefreshTimer.Stop()
})

$script:MainTabs.Add_SelectedIndexChanged({
  if ($script:MainTabs.SelectedTab -eq $script:QuickPage) {
    Move-PreviewRootToHost $script:QuickPreviewHost
  } else {
    Move-PreviewRootToHost $script:LoadPreviewHost
  }
  if ($script:RefreshTimer.Enabled) { return }
  Refresh-ManagerLists
  Request-PreviewForSelected
})
$quickPage.Add_Enter({
  Move-PreviewRootToHost $script:QuickPreviewHost
  if ($script:RefreshTimer.Enabled) { return }
  Refresh-ManagerLists
  Request-PreviewForQuickRow
})

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'SebiLinkSettings.ps1')
$script:IniPath = Join-Path $script:SebiLinkConfigRoot 'sebilink.ini'
$topMostCheck.Checked = Get-SebiSettingBool -Path $script:IniPath -Name 'save_manager_topmost' -Default $false
$script:Form.TopMost = $topMostCheck.Checked
$topMostCheck.Add_CheckedChanged({
  $script:Form.TopMost = $topMostCheck.Checked
  Set-SebiSetting -Path $script:IniPath -Name 'save_manager_topmost' -Value ([string]$topMostCheck.Checked).ToLowerInvariant()
})
if ($script:StartOnQuickTab) {
  $script:MainTabs.SelectedTab = $quickPage
} else {
  $script:MainTabs.SelectedTab = $loadPage
}
if ($script:MainTabs.SelectedTab -eq $script:QuickPage) {
  Move-PreviewRootToHost $script:QuickPreviewHost
} else {
  Move-PreviewRootToHost $script:LoadPreviewHost
}
Refresh-ManagerLists
Request-PreviewForSelected

[void]$script:Form.ShowDialog()
