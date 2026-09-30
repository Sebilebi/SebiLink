param(
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
$script:RuntimeDir = Join-Path $script:SebiLinkConfigRoot "level-review\runtime"
Copy-SebiLinkLegacyRuntime -OldPath (Join-Path $script:BaseDir "runtime") -NewPath $script:RuntimeDir
$script:StatePath = Join-Path $script:RuntimeDir "state.json"
$script:CommandPath = Join-Path $script:RuntimeDir "commands.txt"
$script:ResultPath = Join-Path $script:RuntimeDir "last_result.json"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:State = $null
$script:GameIcon = $null
$script:PokemonList = $null
$script:LearnedList = $null
$script:CurrentList = $null
$script:LearnedDetails = $null
$script:CurrentDetails = $null
$script:StatusLabel = $null
$script:RefreshTimer = $null
$script:PendingCommandSeq = ""
$script:PendingRefreshTicks = 0
$script:PokemonIconCache = @{}
$script:TypeIconCache = @{}
$script:CategoryIconCache = @{}
$script:MetricIconCache = @{}
$script:BlankIcon = $null
$script:PokemonImages = $null

try {
  if (Test-Path -LiteralPath $script:GameExePath) {
    $script:GameIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:GameExePath)
  }
} catch {
  $script:GameIcon = $null
}

function Ensure-Runtime {
  if (!(Test-Path -LiteralPath $script:RuntimeDir)) {
    [void](New-Item -ItemType Directory -Path $script:RuntimeDir -Force)
  }
}

function Read-JsonShared {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { return $null }
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $stream = $null
    $reader = $null
    try {
      $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      $reader = New-Object System.IO.StreamReader($stream, $script:Utf8NoBom, $true)
      $text = $reader.ReadToEnd()
      if (![string]::IsNullOrWhiteSpace($text)) { return $text | ConvertFrom-Json }
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

function Get-Prop {
  param([object]$Object, [string]$Name, [object]$Default = "")
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
  return $prop.Value
}

function Get-String {
  param([object]$Object, [string]$Name, [string]$Default = "")
  return [string](Get-Prop -Object $Object -Name $Name -Default $Default)
}

function Get-Int {
  param([object]$Object, [string]$Name, [int]$Default = 0)
  try { return [int](Get-Prop -Object $Object -Name $Name -Default $Default) } catch { return $Default }
}

function As-Array {
  param($Value)
  if ($null -eq $Value) { return @() }
  return @($Value)
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

function Get-BlankIcon {
  if ($null -eq $script:BlankIcon) {
    $script:BlankIcon = New-Object System.Drawing.Bitmap(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($script:BlankIcon)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.Dispose()
  }
  return $script:BlankIcon
}

function Get-PokemonIconFromEntry {
  param([object]$Entry)
  $species = Get-Int $Entry "species" 0
  if ($species -le 0) { return Get-BlankIcon }
  $form = Get-Int $Entry "form" 0
  $shiny = [bool](Get-Prop -Object $Entry -Name "shiny" -Default $false)
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
  return Get-BlankIcon
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

function Get-TypeIcon {
  param([object]$Move)
  $type = Get-Int $Move "type" -1
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") "types_ico.png"
  return Get-SpriteFrame -Path $path -Index $type -FrameWidth 24 -FrameHeight 28 -Cache $script:TypeIconCache -KeyPrefix "type"
}

function Get-CategoryIcon {
  param([object]$Move)
  $category = Get-Int $Move "category" -1
  $path = Join-Path (Join-Path $script:GameDir "Graphics\Pictures") "category.png"
  return Get-SpriteFrame -Path $path -Index $category -FrameWidth 64 -FrameHeight 28 -Cache $script:CategoryIconCache -KeyPrefix "category"
}

function Get-MetricIcon {
  param([string]$Text, [System.Drawing.Color]$Color)
  $rawText = [string]$Text
  if ([string]::IsNullOrWhiteSpace($rawText)) { $rawText = "-" }
  $width = [Math]::Max(28, [Math]::Min(46, 14 + ($rawText.Length * 7)))
  $key = "metric_{0}_{1}_{2}" -f $rawText, $Color.ToArgb(), $width
  if ($script:MetricIconCache.ContainsKey($key)) { return $script:MetricIconCache[$key] }
  $bitmap = New-Object System.Drawing.Bitmap($width, 18)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.Clear([System.Drawing.Color]::Transparent)
  $brush = New-Object System.Drawing.SolidBrush($Color)
  $graphics.FillRectangle($brush, 0, 0, ($width - 1), 17)
  $brush.Dispose()
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
  $graphics.DrawRectangle($pen, 0, 0, ($width - 1), 17)
  $pen.Dispose()
  $font = New-Object System.Drawing.Font("Segoe UI", 6.5, [System.Drawing.FontStyle]::Bold)
  $format = New-Object System.Drawing.StringFormat
  $format.Alignment = [System.Drawing.StringAlignment]::Center
  $format.LineAlignment = [System.Drawing.StringAlignment]::Center
  $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $rect = New-Object System.Drawing.RectangleF(0, 0, $width, 18)
  $graphics.DrawString($rawText, $font, $textBrush, $rect, $format)
  $textBrush.Dispose()
  $font.Dispose()
  $format.Dispose()
  $graphics.Dispose()
  $script:MetricIconCache[$key] = $bitmap
  return $bitmap
}

function Encode-Field {
  param($Value)
  return [System.Uri]::EscapeDataString([string]$Value)
}

function New-CommandLine {
  param([string]$Seq, [string]$Command, [hashtable]$Values)
  $parts = New-Object System.Collections.Generic.List[string]
  $parts.Add($Seq)
  $parts.Add($Command)
  foreach ($key in $Values.Keys) {
    $parts.Add(("{0}={1}" -f $key, (Encode-Field $Values[$key])))
  }
  return ($parts -join "|")
}

function Send-LevelCommand {
  param([string]$Command, [hashtable]$Values)
  Ensure-Runtime
  $seq = [guid]::NewGuid().ToString("N")
  $line = New-CommandLine -Seq $seq -Command $Command -Values $Values
  [System.IO.File]::AppendAllText($script:CommandPath, ($line + [Environment]::NewLine), $script:Utf8NoBom)
  $script:PendingCommandSeq = $seq
  $script:PendingRefreshTicks = 0
  if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = "Comando enviado al juego..." }
  if ($null -ne $script:RefreshTimer) { $script:RefreshTimer.Start() }
}

function Format-MovePower {
  param([object]$Move)
  $power = Get-Int $Move "power" 0
  if ($power -le 0) { return "-" }
  if ($power -eq 1) { return "???" }
  return [string]$power
}

function Format-MoveAccuracy {
  param([object]$Move)
  $accuracy = Get-Int $Move "accuracy" 0
  if ($accuracy -le 0) { return "-" }
  return [string]$accuracy
}

function Format-MoveDetails {
  param([object]$Move)
  if ($null -eq $Move) { return "Selecciona un movimiento." }
  $name = Get-String $Move "name" "Sin movimiento"
  $id = Get-Int $Move "id" 0
  if ($id -le 0) { return "Hueco vacio." }
  $type = Get-String $Move "typeName"
  $category = Get-String $Move "categoryName"
  $pp = Get-Int $Move "pp" 0
  $power = Format-MovePower $Move
  $accuracy = Format-MoveAccuracy $Move
  $description = Get-String $Move "description"
  return "Movimiento: $name (#$id)`r`nTipo: $type`r`nClase: $category`r`nPotencia: $power    Precision: $accuracy    PP: $pp`r`n`r`n$description"
}

function Add-LevelMoveDetailIconText {
  param($Panel, [int]$X, [int]$Y, $Icon, [string]$Text, [int]$Width, [int]$IconWidth = 24)
  $picture = New-Object System.Windows.Forms.PictureBox
  $picture.Location = New-Object System.Drawing.Point($X, $Y)
  $picture.Size = New-Object System.Drawing.Size($IconWidth, 22)
  $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
  if ($null -ne $Icon) { $picture.Image = $Icon }
  $label = New-Object System.Windows.Forms.Label
  $label.Location = New-Object System.Drawing.Point(($X + $IconWidth + 5), $Y)
  $label.Size = New-Object System.Drawing.Size(($Width - $IconWidth - 5), 22)
  $label.Text = $Text
  $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $label.Font = New-Object System.Drawing.Font("Segoe UI", 8)
  $Panel.Controls.Add($picture)
  $Panel.Controls.Add($label)
}

function Show-LevelMoveDetails {
  param($Panel, [object]$Move)
  if ($null -eq $Panel) { return }
  if ($Panel -is [System.Windows.Forms.TextBox]) {
    $Panel.Text = Format-MoveDetails $Move
    return
  }
  $Panel.SuspendLayout()
  try {
    foreach ($control in @($Panel.Controls)) {
      try { $control.Dispose() } catch {}
    }
    $Panel.Controls.Clear()
    $Panel.BackColor = [System.Drawing.Color]::White
    if ($null -eq $Move -or (Get-Int $Move "id" 0) -le 0) {
      $empty = New-Object System.Windows.Forms.Label
      $empty.Text = "Selecciona un movimiento."
      $empty.Dock = [System.Windows.Forms.DockStyle]::Fill
      $empty.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
      $Panel.Controls.Add($empty)
      return
    }
    $name = Get-String $Move "name" "Sin movimiento"
    $id = Get-Int $Move "id" 0
    $type = Get-String $Move "typeName"
    $category = Get-String $Move "categoryName"
    $power = Format-MovePower $Move
    $accuracy = Format-MoveAccuracy $Move
    $pp = Get-Int $Move "pp" 0
    $description = Get-String $Move "description"

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "{0}  #{1}" -f $name, $id
    $title.Location = New-Object System.Drawing.Point(8, 4)
    $title.Size = New-Object System.Drawing.Size(($Panel.Width - 16), 20)
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 8.8, [System.Drawing.FontStyle]::Bold)
    $title.AutoEllipsis = $true
    $Panel.Controls.Add($title)

    Add-LevelMoveDetailIconText $Panel 8 28 (Get-TypeIcon $Move) $type 160 24
    Add-LevelMoveDetailIconText $Panel 190 28 (Get-CategoryIcon $Move) $category 190 42
    Add-LevelMoveDetailIconText $Panel 8 56 (Get-MetricIcon "POT" ([System.Drawing.Color]::FromArgb(211, 95, 65))) $power 96 30
    Add-LevelMoveDetailIconText $Panel 118 56 (Get-MetricIcon "PRE" ([System.Drawing.Color]::FromArgb(79, 137, 204))) $accuracy 96 30
    Add-LevelMoveDetailIconText $Panel 228 56 (Get-MetricIcon "PP" ([System.Drawing.Color]::FromArgb(88, 158, 98))) ([string]$pp) 86 28

    $desc = New-Object System.Windows.Forms.TextBox
    $desc.Text = $description
    $desc.Location = New-Object System.Drawing.Point(8, 84)
    $desc.Size = New-Object System.Drawing.Size(($Panel.Width - 16), [Math]::Max(26, ($Panel.Height - 90)))
    $desc.Multiline = $true
    $desc.ReadOnly = $true
    $desc.WordWrap = $true
    $desc.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $desc.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $desc.BackColor = [System.Drawing.Color]::White
    $desc.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $Panel.Controls.Add($desc)
  } finally {
    $Panel.ResumeLayout()
  }
}

function Draw-MoveItem {
  param($Sender, $EventArgs)
  if ($null -eq $EventArgs.Item -or $Sender.Columns.Count -le 0) { return }
  $bounds = $EventArgs.Bounds
  $columnWidth = [Math]::Max(30, $Sender.Columns[0].Width)
  $cellBounds = New-Object System.Drawing.Rectangle($bounds.X, $bounds.Y, $columnWidth, $bounds.Height)
  $selected = [bool]$EventArgs.Item.Selected
  $backColor = $(if ($selected) { [System.Drawing.SystemColors]::Highlight } else { $Sender.BackColor })
  $foreColor = $(if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::Black })
  $backBrush = New-Object System.Drawing.SolidBrush($backColor)
  $EventArgs.Graphics.FillRectangle($backBrush, $cellBounds)
  $backBrush.Dispose()
  $rect = New-Object System.Drawing.RectangleF(($cellBounds.X + 5), ($cellBounds.Y + 1), [Math]::Max(8, $cellBounds.Width - 10), ($cellBounds.Height - 2))
  $brush = New-Object System.Drawing.SolidBrush($foreColor)
  $format = New-Object System.Drawing.StringFormat
  $format.LineAlignment = [System.Drawing.StringAlignment]::Center
  $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
  $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
  $EventArgs.Graphics.DrawString([string]$EventArgs.Item.Text, $Sender.Font, $brush, $rect, $format)
  $format.Dispose()
  $brush.Dispose()
  if ($selected) { $EventArgs.DrawFocusRectangle() }
}

function Draw-MoveSubItem {
  param($Sender, $EventArgs)
  if ($EventArgs.ColumnIndex -eq 0) { return }
  $move = $EventArgs.Item.Tag
  $text = [string]$EventArgs.SubItem.Text
  $columnText = ""
  try { $columnText = [string]$Sender.Columns[$EventArgs.ColumnIndex].Text } catch {}
  $bounds = $EventArgs.Bounds
  $selected = [bool]$EventArgs.Item.Selected
  $backColor = $(if ($selected) { [System.Drawing.SystemColors]::Highlight } else { $Sender.BackColor })
  $foreColor = $(if ($selected) { [System.Drawing.SystemColors]::HighlightText } else { [System.Drawing.Color]::Black })
  $backBrush = New-Object System.Drawing.SolidBrush($backColor)
  $EventArgs.Graphics.FillRectangle($backBrush, $bounds)
  $backBrush.Dispose()
  $x = $bounds.X + 4
  $textX = $x
  $icon = $null
  $iconWidth = 0
  $drawText = $true
  if ($columnText -eq "Tipo") {
    $icon = Get-TypeIcon $move
    $iconWidth = 22
  } elseif ($columnText -eq "Clase") {
    $icon = Get-CategoryIcon $move
    $iconWidth = 42
  } elseif ($columnText -eq "Pot.") {
    $icon = Get-MetricIcon $text ([System.Drawing.Color]::FromArgb(211, 95, 65))
    $iconWidth = $icon.Width
    $drawText = $false
  } elseif ($columnText -eq "Prec.") {
    $icon = Get-MetricIcon $text ([System.Drawing.Color]::FromArgb(79, 137, 204))
    $iconWidth = $icon.Width
    $drawText = $false
  } elseif ($columnText -eq "PP") {
    $icon = Get-MetricIcon $text ([System.Drawing.Color]::FromArgb(88, 158, 98))
    $iconWidth = $icon.Width
    $drawText = $false
  }
  if ($null -ne $icon) {
    $drawHeight = [Math]::Min($bounds.Height - 4, 20)
    $drawY = $bounds.Y + [Math]::Max(2, [int](($bounds.Height - $drawHeight) / 2))
    $EventArgs.Graphics.DrawImage($icon, $x, $drawY, $iconWidth, $drawHeight)
    $textX = $x + $iconWidth + 4
  }
  if (!$drawText) { return }
  $rect = New-Object System.Drawing.RectangleF($textX, ($bounds.Y + 1), [Math]::Max(8, $bounds.Right - $textX - 4), ($bounds.Height - 2))
  $brush = New-Object System.Drawing.SolidBrush($foreColor)
  $format = New-Object System.Drawing.StringFormat
  $format.LineAlignment = [System.Drawing.StringAlignment]::Center
  $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
  $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
  $EventArgs.Graphics.DrawString($text, $Sender.Font, $brush, $rect, $format)
  $format.Dispose()
  $brush.Dispose()
}

function Enable-MoveListStyle {
  param($List)
  $List.OwnerDraw = $true
  $List.Add_DrawColumnHeader({ param($sender, $e) $e.DrawDefault = $true })
  $List.Add_DrawItem({ param($sender, $e) Draw-MoveItem $sender $e })
  $List.Add_DrawSubItem({ param($sender, $e) Draw-MoveSubItem $sender $e })
  $images = New-Object System.Windows.Forms.ImageList
  $images.ImageSize = New-Object System.Drawing.Size(1, 26)
  $images.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
  [void]$images.Images.Add((Get-BlankIcon))
  $List.SmallImageList = $images
}

function Resize-MoveColumns {
  param($List)
  if ($null -eq $List -or $List.Columns.Count -eq 0) { return }
  $width = [Math]::Max(320, $List.ClientSize.Width - 4)
  if ($List.Columns.Count -eq 7) {
    $fixed = @(42, 58, 70, 48, 50, 40)
    $nameWidth = [Math]::Max(130, $width - (($fixed | Measure-Object -Sum).Sum) - 2)
    $widths = @($nameWidth) + $fixed
  } else {
    $fixed = @(60, 72, 48, 50, 40)
    $nameWidth = [Math]::Max(150, $width - (($fixed | Measure-Object -Sum).Sum) - 2)
    $widths = @($nameWidth) + $fixed
  }
  for ($i = 0; $i -lt $List.Columns.Count -and $i -lt $widths.Count; $i++) {
    $List.Columns[$i].Width = [int]$widths[$i]
  }
}

function Populate-PokemonList {
  if ($null -eq $script:PokemonList) { return }
  $selectedKey = ""
  if ($script:PokemonList.SelectedItems.Count -gt 0) { $selectedKey = [string]$script:PokemonList.SelectedItems[0].Tag.Key }
  $script:PokemonList.BeginUpdate()
  $script:PokemonList.Items.Clear()
  if ($null -ne $script:PokemonImages) { $script:PokemonImages.Images.Clear() }
  foreach ($entry in As-Array (Get-Prop -Object $script:State -Name "results" -Default @())) {
    $name = Get-String $entry "name"
    $oldLevel = Get-Int $entry "oldLevel" 0
    $newLevel = Get-Int $entry "newLevel" 0
    $learned = @(As-Array (Get-Prop -Object $entry -Name "learnedMoves" -Default @())).Count
    $loc = Get-String $entry "loc"
    $box = Get-Int $entry "box" -1
    $slot = Get-Int $entry "slot" -1
    $index = Get-Int $entry "index" -1
    $key = "{0}:{1}:{2}:{3}" -f $loc, $index, $box, $slot
    $row = New-Object System.Windows.Forms.ListViewItem($name)
    if ($null -ne $script:PokemonImages) {
      $row.ImageIndex = $script:PokemonImages.Images.Count
      [void]$script:PokemonImages.Images.Add((Get-PokemonIconFromEntry $entry))
    }
    [void]$row.SubItems.Add([string]$oldLevel)
    [void]$row.SubItems.Add([string]$newLevel)
    [void]$row.SubItems.Add([string]$learned)
    [void]$row.SubItems.Add($(if ($loc -eq "party") { "Equipo" } else { "Caja $($box + 1) Slot $($slot + 1)" }))
    $row.Tag = [pscustomobject]@{ Entry = $entry; Key = $key }
    [void]$script:PokemonList.Items.Add($row)
    if ($key -eq $selectedKey) { $row.Selected = $true }
  }
  $script:PokemonList.EndUpdate()
  if ($script:PokemonList.Items.Count -gt 0 -and $script:PokemonList.SelectedItems.Count -eq 0) {
    $script:PokemonList.Items[0].Selected = $true
  }
}

function Populate-MoveLists {
  if ($null -eq $script:PokemonList -or $script:PokemonList.SelectedItems.Count -eq 0) { return }
  $entry = $script:PokemonList.SelectedItems[0].Tag.Entry
  $script:LearnedList.BeginUpdate()
  $script:CurrentList.BeginUpdate()
  $script:LearnedList.Items.Clear()
  $script:CurrentList.Items.Clear()
  foreach ($move in As-Array (Get-Prop -Object $entry -Name "learnedMoves" -Default @())) {
    $row = New-Object System.Windows.Forms.ListViewItem((Get-String $move "name"))
    [void]$row.SubItems.Add([string](Get-Int $move "level" 0))
    [void]$row.SubItems.Add((Get-String $move "typeName"))
    [void]$row.SubItems.Add((Get-String $move "categoryName"))
    [void]$row.SubItems.Add((Format-MovePower $move))
    [void]$row.SubItems.Add((Format-MoveAccuracy $move))
    [void]$row.SubItems.Add([string](Get-Int $move "pp" 0))
    $row.Tag = $move
    [void]$script:LearnedList.Items.Add($row)
  }
  foreach ($move in As-Array (Get-Prop -Object $entry -Name "currentMoves" -Default @())) {
    $slot = Get-Int $move "slot" 0
    $name = Get-String $move "name"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Hueco vacio" }
    $row = New-Object System.Windows.Forms.ListViewItem(("{0}. {1}" -f ($slot + 1), $name))
    [void]$row.SubItems.Add((Get-String $move "typeName"))
    [void]$row.SubItems.Add((Get-String $move "categoryName"))
    [void]$row.SubItems.Add((Format-MovePower $move))
    [void]$row.SubItems.Add((Format-MoveAccuracy $move))
    [void]$row.SubItems.Add([string](Get-Int $move "pp" 0))
    $row.Tag = $move
    [void]$script:CurrentList.Items.Add($row)
  }
  $script:LearnedList.EndUpdate()
  $script:CurrentList.EndUpdate()
  if ($script:LearnedList.Items.Count -gt 0) { $script:LearnedList.Items[0].Selected = $true }
  if ($script:CurrentList.Items.Count -gt 0) { $script:CurrentList.Items[0].Selected = $true }
}

function Update-Details {
  if ($null -ne $script:LearnedDetails) {
    $move = $null
    if ($script:LearnedList.SelectedItems.Count -gt 0) { $move = $script:LearnedList.SelectedItems[0].Tag }
    Show-LevelMoveDetails $script:LearnedDetails $move
  }
  if ($null -ne $script:CurrentDetails) {
    $move = $null
    if ($script:CurrentList.SelectedItems.Count -gt 0) { $move = $script:CurrentList.SelectedItems[0].Tag }
    Show-LevelMoveDetails $script:CurrentDetails $move
  }
}

function Load-State {
  $state = Read-JsonShared $script:StatePath
  if ($null -ne $state) {
    $script:State = $state
    Populate-PokemonList
    Populate-MoveLists
    Update-Details
    if ($null -ne $script:StatusLabel) {
      $script:StatusLabel.Text = "Datos actualizados."
    }
  }
}

function Invoke-LearnMove {
  if ($script:PokemonList.SelectedItems.Count -eq 0 -or $script:LearnedList.SelectedItems.Count -eq 0) {
    if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = "Selecciona Pokemon y movimiento nuevo." }
    return
  }
  $entry = $script:PokemonList.SelectedItems[0].Tag.Entry
  $move = $script:LearnedList.SelectedItems[0].Tag
  $replaceSlot = -1
  if ($script:CurrentList.SelectedItems.Count -gt 0) {
    $replaceSlot = Get-Int $script:CurrentList.SelectedItems[0].Tag "slot" -1
  }
  Send-LevelCommand "learn_move" @{
    loc = Get-String $entry "loc"
    index = Get-Int $entry "index" -1
    box = Get-Int $entry "box" -1
    slot = Get-Int $entry "slot" -1
    move = Get-Int $move "id" 0
    replaceSlot = $replaceSlot
  }
}

if ($SelfTest) {
  Ensure-Runtime
  Write-Host "SebiLevelReview.ps1 OK"
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()
Ensure-Runtime

$form = New-Object System.Windows.Forms.Form
$form.Text = "Movimientos aprendidos SebiLink"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1040, 650)
$form.MinimumSize = New-Object System.Drawing.Size(900, 560)
if ($null -ne $script:GameIcon) { $form.Icon = $script:GameIcon }

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 1
$root.RowCount = 4
$root.Padding = New-Object System.Windows.Forms.Padding(10)
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 38)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 62)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
$form.Controls.Add($root)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Revision de movimientos por subida de nivel"
$title.Dock = [System.Windows.Forms.DockStyle]::Fill
$title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$root.Controls.Add($title, 0, 0)

$script:PokemonList = New-Object System.Windows.Forms.ListView
$script:PokemonList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:PokemonList.View = [System.Windows.Forms.View]::Details
$script:PokemonList.FullRowSelect = $true
$script:PokemonList.HideSelection = $false
$script:PokemonList.MultiSelect = $false
$script:PokemonList.GridLines = $true
$script:PokemonImages = New-Object System.Windows.Forms.ImageList
$script:PokemonImages.ImageSize = New-Object System.Drawing.Size(32, 28)
$script:PokemonImages.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
$script:PokemonList.SmallImageList = $script:PokemonImages
[void]$script:PokemonList.Columns.Add("Pokemon", 220)
[void]$script:PokemonList.Columns.Add("De", 54)
[void]$script:PokemonList.Columns.Add("A", 54)
[void]$script:PokemonList.Columns.Add("Mov. nuevos", 92)
[void]$script:PokemonList.Columns.Add("Origen", 220)
$script:PokemonList.Add_SelectedIndexChanged({ Populate-MoveLists; Update-Details })
$root.Controls.Add($script:PokemonList, 0, 1)

$movesRoot = New-Object System.Windows.Forms.TableLayoutPanel
$movesRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
$movesRoot.ColumnCount = 2
$movesRoot.RowCount = 2
[void]$movesRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$movesRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$movesRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
[void]$movesRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
$root.Controls.Add($movesRoot, 0, 2)

$script:LearnedList = New-Object System.Windows.Forms.ListView
$script:LearnedList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LearnedList.View = [System.Windows.Forms.View]::Details
$script:LearnedList.FullRowSelect = $true
$script:LearnedList.HideSelection = $false
$script:LearnedList.MultiSelect = $false
$script:LearnedList.GridLines = $true
$script:LearnedList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
[void]$script:LearnedList.Columns.Add("Movimientos nuevos", 180)
[void]$script:LearnedList.Columns.Add("Nv.", 45)
[void]$script:LearnedList.Columns.Add("Tipo", 70)
[void]$script:LearnedList.Columns.Add("Clase", 74)
[void]$script:LearnedList.Columns.Add("Pot.", 50)
[void]$script:LearnedList.Columns.Add("Prec.", 50)
[void]$script:LearnedList.Columns.Add("PP", 48)
Enable-MoveListStyle $script:LearnedList
$script:LearnedList.Add_SelectedIndexChanged({ Update-Details })
$script:LearnedList.Add_Resize({ Resize-MoveColumns $script:LearnedList })
$movesRoot.Controls.Add($script:LearnedList, 0, 0)

$script:CurrentList = New-Object System.Windows.Forms.ListView
$script:CurrentList.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:CurrentList.View = [System.Windows.Forms.View]::Details
$script:CurrentList.FullRowSelect = $true
$script:CurrentList.HideSelection = $false
$script:CurrentList.MultiSelect = $false
$script:CurrentList.GridLines = $true
$script:CurrentList.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
[void]$script:CurrentList.Columns.Add("Movimientos actuales", 190)
[void]$script:CurrentList.Columns.Add("Tipo", 70)
[void]$script:CurrentList.Columns.Add("Clase", 74)
[void]$script:CurrentList.Columns.Add("Pot.", 50)
[void]$script:CurrentList.Columns.Add("Prec.", 50)
[void]$script:CurrentList.Columns.Add("PP", 48)
Enable-MoveListStyle $script:CurrentList
$script:CurrentList.Add_SelectedIndexChanged({ Update-Details })
$script:CurrentList.Add_Resize({ Resize-MoveColumns $script:CurrentList })
$movesRoot.Controls.Add($script:CurrentList, 1, 0)

$script:LearnedDetails = New-Object System.Windows.Forms.Panel
$script:LearnedDetails.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LearnedDetails.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:LearnedDetails.BackColor = [System.Drawing.Color]::White
$movesRoot.Controls.Add($script:LearnedDetails, 0, 1)

$script:CurrentDetails = New-Object System.Windows.Forms.Panel
$script:CurrentDetails.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:CurrentDetails.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:CurrentDetails.BackColor = [System.Drawing.Color]::White
$movesRoot.Controls.Add($script:CurrentDetails, 1, 1)

$bottom = New-Object System.Windows.Forms.FlowLayoutPanel
$bottom.Dock = [System.Windows.Forms.DockStyle]::Fill
$bottom.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$bottom.WrapContents = $false
$root.Controls.Add($bottom, 0, 3)

$learnButton = New-Object System.Windows.Forms.Button
$learnButton.Text = "Aprender movimiento"
$learnButton.Size = New-Object System.Drawing.Size(150, 28)
$learnButton.Add_Click({ Invoke-LearnMove })
[void]$bottom.Controls.Add($learnButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Actualizar"
$refreshButton.Size = New-Object System.Drawing.Size(90, 28)
$refreshButton.Add_Click({ Load-State })
[void]$bottom.Controls.Add($refreshButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Cerrar"
$closeButton.Size = New-Object System.Drawing.Size(80, 28)
$closeButton.Add_Click({ $form.Close() })
[void]$bottom.Controls.Add($closeButton)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Selecciona un Pokemon."
$script:StatusLabel.AutoSize = $false
$script:StatusLabel.Size = New-Object System.Drawing.Size(620, 28)
$script:StatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
[void]$bottom.Controls.Add($script:StatusLabel)

$script:RefreshTimer = New-Object System.Windows.Forms.Timer
$script:RefreshTimer.Interval = 900
$script:RefreshTimer.Add_Tick({
  $script:PendingRefreshTicks += 1
  $result = Read-JsonShared $script:ResultPath
  $matchesPending = $false
  if ($null -ne $result) {
    $matchesPending = [string]::IsNullOrWhiteSpace($script:PendingCommandSeq) -or ([string]$result.seq -eq $script:PendingCommandSeq)
  }
  if ($matchesPending) {
    Load-State
    if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = [string]$result.message }
    $script:PendingCommandSeq = ""
    $script:PendingRefreshTicks = 0
    $script:RefreshTimer.Stop()
  } elseif ($script:PendingRefreshTicks -ge 10) {
    if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = "El juego aun no respondio al comando." }
    $script:PendingCommandSeq = ""
    $script:PendingRefreshTicks = 0
    $script:RefreshTimer.Stop()
  }
})

Load-State
Resize-MoveColumns $script:LearnedList
Resize-MoveColumns $script:CurrentList
[void]$form.ShowDialog()
