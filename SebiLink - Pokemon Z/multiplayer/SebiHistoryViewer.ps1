param(
  [ValidateSet('Library','Install','View')][string]$Mode = 'View',
  [string]$ConfigDir,
  [string]$HistoryFile,
  [string]$KeyFile
)
# Public viewer code. No passwords, decrypted records, or private key material.
$ErrorActionPreference = 'Stop'

function Install-SebiHistoryViewer([string]$Directory) {
  $target = Join-Path $Directory 'history-viewer'
  [void][IO.Directory]::CreateDirectory($target)
  foreach ($name in @('SebiHistoryViewer.ps1','SebiActivityCrypto.ps1')) {
    $from = Join-Path $PSScriptRoot $name
    $to = Join-Path $target $name
    if (![IO.File]::Exists($from) -and [IO.File]::Exists($to)) { $from = $to }
    if ([IO.Path]::GetFullPath($from) -eq [IO.Path]::GetFullPath($to)) { continue }
    $bytes = [IO.File]::ReadAllBytes($from)
    if ([IO.File]::Exists($to) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($to)) -eq [Convert]::ToBase64String($bytes)) { continue }
    $temp = $to + '.tmp'
    try {
      [IO.File]::WriteAllBytes($temp,$bytes)
      if ([IO.File]::Exists($to)) { [IO.File]::Replace($temp,$to,[NullString]::Value) } else { [IO.File]::Move($temp,$to) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
  }
  $launcher = @'
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0history-viewer\SebiHistoryViewer.ps1" -Mode View -ConfigDir "%~dp0."
endlocal
'@
  [IO.File]::WriteAllText((Join-Path $Directory 'Ver historial SebiLink.bat'),$launcher.Replace("`n","`r`n"),[Text.Encoding]::ASCII)
}

function Get-SebiHistoryField($Object,[string]$Name,$Default = '') {
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-SebiHistoryIds($Object) {
  $ids = New-Object 'Collections.Generic.List[string]'
  function Add-HistoryIds($Value) {
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
    if ($Value -is [array]) { foreach ($child in $Value) { Add-HistoryIds $child }; return }
    foreach ($property in $Value.PSObject.Properties) {
      if ($property.Name -match '(?i)(^id$|_id$|Id$|^@sebilink_activity_id$)' -and $null -ne $property.Value -and ($property.Value -is [string] -or $property.Value -is [ValueType])) { $ids.Add([string]$property.Value) }
      Add-HistoryIds $property.Value
    }
  }
  Add-HistoryIds $Object
  return (@($ids | Select-Object -Unique) -join ' | ')
}

function Get-SebiPokemonLabel($Pokemon) {
  if ($null -eq $Pokemon -or $Pokemon -eq '') { return '' }
  $name = Get-SebiHistoryField $Pokemon 'speciesName' (Get-SebiHistoryField $Pokemon 'nickname' (Get-SebiHistoryField $Pokemon 'species' 'Pokemon'))
  $nickname = Get-SebiHistoryField $Pokemon 'nickname'
  if ($nickname -and $nickname -ne $name) { $name = "$nickname ($name)" }
  if ((Get-SebiHistoryField $Pokemon 'eggsteps' 0) -gt 0) { $name = "Huevo: $name" }
  $level = Get-SebiHistoryField $Pokemon 'level'
  if ($level -ne '') { $name += " Nv. $level" }
  return [string]$name
}

$script:SebiHistoryLabels = @{
  wild_encounter='Encuentro salvaje'; pokemon_captured='Captura'; wild_defeated='Salvaje derrotado'; wild_result='Resultado salvaje'
  pokemon_death='Muerte'; pokemon_fainted='Debilitamiento'; item_obtained='Objeto obtenido'; item_purchased='Compra'
  setting_changed='Ajuste cambiado'; settings_snapshot='Configuracion inicial'; pokemon_healed='Curacion'; pokemon_traded='Intercambio'
  pokemon_trade_failed='Intercambio fallido'; item_used='Objeto usado'; sebilink_option_selected='Opcion seleccionada'
  sebilink_action_started='Accion iniciada'; sebilink_action='Accion realizada'; sebilink_action_failed='Accion fallida'
}

function Get-SebiHistorySummary($Record) {
  $event = Get-SebiHistoryField $Record 'event'
  switch ($event) {
    'setting_changed' {
      $field = Get-SebiHistoryField $Record 'field'
      if ($field -eq 'wild_shiny_percent') { $field = 'Probabilidad shiny' }
      return "$field`: $(Get-SebiHistoryField $Record 'old_display' (Get-SebiHistoryField $Record 'old_value' 'sin configurar')) -> $(Get-SebiHistoryField $Record 'new_display' (Get-SebiHistoryField $Record 'new_value' 'sin configurar'))"
    }
    'pokemon_healed' { return "PS $(Get-SebiHistoryField (Get-SebiHistoryField $Record 'before') 'hp') -> $(Get-SebiHistoryField (Get-SebiHistoryField $Record 'after') 'hp'); $(Get-SebiHistoryField $Record 'method'); cambio: $(Get-SebiHistoryField $Record 'changed')" }
    'pokemon_traded' { return "$(Get-SebiPokemonLabel (Get-SebiHistoryField $Record 'sent' $null)) -> $(Get-SebiPokemonLabel (Get-SebiHistoryField $Record 'received' $null)); $(Get-SebiHistoryField $Record 'partner')" }
    { $_ -in @('item_obtained','item_purchased','item_used') } {
      $item = Get-SebiHistoryField $Record 'item'
      $text = "$(Get-SebiHistoryField $item 'name') x$(Get-SebiHistoryField $item 'quantity' 1)"
      if ($event -eq 'item_purchased') { $text += "; precio: $(Get-SebiHistoryField $Record 'total_price')" }
      return $text
    }
    'sebilink_option_selected' { return "$(Get-SebiHistoryField $Record 'menu'): $(Get-SebiHistoryField $Record 'selected_option' 'Cancelado')" }
    default { return [string](Get-SebiHistoryField $Record 'action' (Get-SebiHistoryField $Record 'outcome' (Get-SebiPokemonLabel (Get-SebiHistoryField $Record 'pokemon' $null)))) }
  }
}

function ConvertTo-SebiHistoryTable([string]$Text) {
  $table = New-Object Data.DataTable 'Historial'
  $table.CaseSensitive = $false
  [void]$table.Columns.Add('Numero',[int]); [void]$table.Columns.Add('Fecha',[datetime])
  foreach ($name in @('Evento','Resumen','Pokemon','IDs','Ruta','Origen','Jugador','Partida','Tipo','Buscar','JSON')) { [void]$table.Columns.Add($name,[string]) }
  $index = 0
  foreach ($line in ($Text -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $record = $line | ConvertFrom-Json
    $row = $table.NewRow(); $row.Numero = ++$index
    $stamp = Get-SebiHistoryField $record 'timestamp'
    if ($stamp -match '(\d{2})(\d{2})$' -and $stamp -notmatch '[+-]\d{2}:\d{2}$') { $stamp = $stamp -replace '([+-]\d{2})(\d{2})$','$1:$2' }
    $date = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($stamp,[ref]$date)) { $row.Fecha = $date.LocalDateTime }
    else {
      # MKXP on Windows can emit the localized timezone name for Ruby %z.
      # Preserve the recorded wall-clock date/time when its offset is unknown.
      $localStamp = "$(Get-SebiHistoryField $record 'date') $(Get-SebiHistoryField $record 'time')"
      $localDate = [datetime]::MinValue
      if ([datetime]::TryParseExact($localStamp,'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$localDate)) { $row.Fecha = $localDate }
    }
    $row.Tipo = Get-SebiHistoryField $record 'event' 'desconocido'
    $row.Evento = if ($script:SebiHistoryLabels.ContainsKey($row.Tipo)) { $script:SebiHistoryLabels[$row.Tipo] } else { $row.Tipo }
    $row.Resumen = Get-SebiHistorySummary $record
    $row.Pokemon = Get-SebiPokemonLabel (Get-SebiHistoryField $record 'pokemon' $null)
    if (!$row.Pokemon) { $row.Pokemon = (@('sent','received') | ForEach-Object { Get-SebiPokemonLabel (Get-SebiHistoryField $record $_ $null) } | Where-Object { $_ }) -join ' -> ' }
    $row.IDs = Get-SebiHistoryIds $record
    $observed = Get-SebiHistoryField $record 'observed_context' $null
    $location = Get-SebiHistoryField $record 'location' (Get-SebiHistoryField $observed 'location' $null)
    $row.Ruta = Get-SebiHistoryField $location 'map_name'
    $map = Get-SebiHistoryField $location 'map_id'
    if ($map -ne '') { $row.Ruta += " [mapa $map]" }
    if ($observed -and !(Get-SebiHistoryField $record 'location' $null)) { $row.Ruta += ' (observada)' }
    $source = Get-SebiHistoryField $record 'source'
    if ($source -is [string]) { $row.Origen = $source }
    else { $row.Origen = (@('via','kind','action') | ForEach-Object { Get-SebiHistoryField $source $_ } | Where-Object { $_ }) -join ' / ' }
    $trainer = Get-SebiHistoryField $record 'trainer' (Get-SebiHistoryField $observed 'trainer' $null)
    $row.Jugador = Get-SebiHistoryField $trainer 'name'
    $row.Partida = Get-SebiHistoryField $record 'save_file' (Get-SebiHistoryField $observed 'save_file')
    $row.Buscar = $line; $row.JSON = $line
    $table.Rows.Add($row)
  }
  return ,$table
}

function ConvertTo-SebiHistoryLike([string]$Value) {
  $text = New-Object Text.StringBuilder
  foreach ($char in $Value.ToCharArray()) {
    switch ([string]$char) { "'" { [void]$text.Append("''") }; '[' { [void]$text.Append('[[]') }; ']' { [void]$text.Append('[]]') }; '%' { [void]$text.Append('[%]') }; '*' { [void]$text.Append('[*]') }; default { [void]$text.Append($char) } }
  }
  return $text.ToString()
}

function Set-SebiHistoryFilter($View,[string]$Search,[string]$Id,[string]$Event,[string]$Route,$From=$null,$To=$null) {
  $filters = New-Object 'Collections.Generic.List[string]'
  foreach ($pair in @(@('Buscar',$Search),@('IDs',$Id),@('Ruta',$Route))) {
    if ($pair[1]) { $filters.Add("[$($pair[0])] LIKE '%$(ConvertTo-SebiHistoryLike $pair[1])%'") }
  }
  if ($Event) { $filters.Add("[Tipo] = '$($Event.Replace("'","''"))'") }
  if ($null -ne $From) { $filters.Add("[Fecha] >= #$($From.Date.ToString('MM/dd/yyyy',[Globalization.CultureInfo]::InvariantCulture))#") }
  if ($null -ne $To) { $filters.Add("[Fecha] < #$($To.Date.AddDays(1).ToString('MM/dd/yyyy',[Globalization.CultureInfo]::InvariantCulture))#") }
  $View.RowFilter = $filters -join ' AND '
}

function Add-SebiHistoryTreeNode($Nodes,[string]$Name,$Value,[int]$Depth=0) {
  if ($Depth -gt 100) { [void]$Nodes.Add($Name + ': (consultar JSON completo)'); return }
  if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { [void]$Nodes.Add($Name + ': ' + [string]$Value); return }
  $node = $Nodes.Add($Name)
  if ($Value -is [array]) { for ($i=0;$i -lt $Value.Length;$i++) { Add-SebiHistoryTreeNode $node.Nodes "[$i]" $Value[$i] ($Depth+1) } }
  else { foreach ($property in $Value.PSObject.Properties) { Add-SebiHistoryTreeNode $node.Nodes $property.Name $property.Value ($Depth+1) } }
}

function New-SebiHistoryWindow {
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Data
  $ui = @{}
  $ui.Window = New-Object Windows.Forms.Form
  $ui.Window.Text='SebiLink - Historial verificado'; $ui.Window.Size=New-Object Drawing.Size(1320,850)
  $ui.Window.MinimumSize=New-Object Drawing.Size(900,620); $ui.Window.StartPosition='CenterScreen'
  $ui.Window.Font=New-Object Drawing.Font('Segoe UI',10); $ui.Window.BackColor=[Drawing.Color]::White
  $layout=New-Object Windows.Forms.TableLayoutPanel; $layout.Dock='Fill'; $layout.ColumnCount=1; $layout.RowCount=4
  [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',120)))
  [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))
  [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',235)))
  [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',28)))
  $ui.Window.Controls.Add($layout)
  $header=New-Object Windows.Forms.FlowLayoutPanel; $header.Dock='Fill'; $header.Padding=New-Object Windows.Forms.Padding(8); $header.WrapContents=$true
  $ui.Path=New-Object Windows.Forms.Label; $ui.Path.AutoSize=$false; $ui.Path.Width=850; $ui.Path.Height=26
  $ui.Open=New-Object Windows.Forms.Button; $ui.Open.Text='Abrir historial'; $ui.Open.Width=125
  $ui.Reload=New-Object Windows.Forms.Button; $ui.Reload.Text='Recargar'; $ui.Reload.Width=90
  $ui.Clear=New-Object Windows.Forms.Button; $ui.Clear.Text='Limpiar filtros'; $ui.Clear.Width=125
  $header.Controls.AddRange(@($ui.Path,$ui.Open,$ui.Reload,$ui.Clear)); $header.SetFlowBreak($ui.Clear,$true)
  foreach ($pair in @(@('Search','Buscar en todo',280),@('Id','ID',235),@('Route','Ruta',205))) {
    $label=New-Object Windows.Forms.Label; $label.Text=$pair[1]; $label.AutoSize=$true; $label.Margin=New-Object Windows.Forms.Padding(6,7,3,0)
    $box=New-Object Windows.Forms.TextBox; $box.Width=$pair[2]; $ui[$pair[0]]=$box; $header.Controls.AddRange(@($label,$box))
  }
  $ui.Event=New-Object Windows.Forms.ComboBox; $ui.Event.DropDownStyle='DropDownList'; $ui.Event.Width=230; $header.Controls.Add($ui.Event); $header.SetFlowBreak($ui.Event,$true)
  foreach ($pair in @(@('From','Desde'),@('To','Hasta'))) {
    $label=New-Object Windows.Forms.Label; $label.Text=$pair[1]; $label.AutoSize=$true; $label.Margin=New-Object Windows.Forms.Padding(6,7,3,0)
    $date=New-Object Windows.Forms.DateTimePicker; $date.Format='Short'; $date.ShowCheckBox=$true; $date.Checked=$false; $date.Width=150
    $ui[$pair[0]]=$date; $header.Controls.AddRange(@($label,$date))
  }
  $tip=New-Object Windows.Forms.Label; $tip.Text='Clic en una columna para ordenar. Selecciona una fila para consultar todos sus datos.'; $tip.AutoSize=$true; $tip.Margin=New-Object Windows.Forms.Padding(12,7,0,0); $header.Controls.Add($tip)
  $layout.Controls.Add($header,0,0)
  $ui.Grid=New-Object Windows.Forms.DataGridView; $ui.Grid.Dock='Fill'; $ui.Grid.ReadOnly=$true
  $ui.Grid.AllowUserToAddRows=$false; $ui.Grid.AllowUserToDeleteRows=$false; $ui.Grid.AllowUserToOrderColumns=$true
  $ui.Grid.AutoGenerateColumns=$false; $ui.Grid.SelectionMode='FullRowSelect'; $ui.Grid.MultiSelect=$false; $ui.Grid.RowHeadersVisible=$false
  $ui.Grid.BackgroundColor=[Drawing.Color]::White; $ui.Grid.BorderStyle='None'; $ui.Grid.AutoSizeRowsMode='None'
  $ui.Grid.AlternatingRowsDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(245,248,251)
  foreach ($pair in @(@('Numero',55),@('Fecha',185),@('Evento',150),@('Resumen',350),@('Pokemon',200),@('IDs',240),@('Ruta',190),@('Origen',190),@('Jugador',130),@('Partida',140))) {
    $column=New-Object Windows.Forms.DataGridViewTextBoxColumn; $column.Name=$pair[0]; $column.DataPropertyName=$pair[0]; $column.HeaderText=$pair[0]; $column.Width=$pair[1]; $column.SortMode='Automatic'
    if ($pair[0] -eq 'Fecha') { $column.HeaderText='Fecha y hora'; $column.DefaultCellStyle.Format='dd/MM/yyyy HH:mm:ss' }
    [void]$ui.Grid.Columns.Add($column)
  }
  $layout.Controls.Add($ui.Grid,0,1)
  $tabs=New-Object Windows.Forms.TabControl; $tabs.Dock='Fill'
  $details=New-Object Windows.Forms.TabPage 'Detalle completo'; $json=New-Object Windows.Forms.TabPage 'Datos originales'
  $ui.Tree=New-Object Windows.Forms.TreeView; $ui.Tree.Dock='Fill'; $ui.Tree.HideSelection=$false; $details.Controls.Add($ui.Tree)
  $ui.Json=New-Object Windows.Forms.RichTextBox; $ui.Json.Dock='Fill'; $ui.Json.ReadOnly=$true; $ui.Json.WordWrap=$false; $ui.Json.Font=New-Object Drawing.Font('Consolas',10); $json.Controls.Add($ui.Json)
  $tabs.TabPages.AddRange(@($details,$json)); $layout.Controls.Add($tabs,0,2)
  $ui.Status=New-Object Windows.Forms.Label; $ui.Status.Dock='Fill'; $ui.Status.Padding=New-Object Windows.Forms.Padding(10,3,0,0); $layout.Controls.Add($ui.Status,0,3)
  $ui.Apply = {
    if (!$ui.View) { return }
    $from=$null; $to=$null; if ($ui.From.Checked) { $from=$ui.From.Value }; if ($ui.To.Checked) { $to=$ui.To.Value }
    $event=''; if ($ui.Event.SelectedItem) { $event=$ui.Event.SelectedItem.Code }
    Set-SebiHistoryFilter $ui.View $ui.Search.Text $ui.Id.Text $event $ui.Route.Text $from $to
    $ui.Status.Text="$($ui.View.Count) de $($ui.Table.Rows.Count) registros | Integridad verificada | Solo lectura"
    if ($ui.View.Count -eq 0) { $ui.Tree.Nodes.Clear(); $ui.Json.Clear() }
  }.GetNewClosure()
  foreach ($box in @($ui.Search,$ui.Id,$ui.Route)) { $box.Add_TextChanged($ui.Apply) }
  $ui.Event.Add_SelectedIndexChanged($ui.Apply); $ui.From.Add_ValueChanged($ui.Apply); $ui.To.Add_ValueChanged($ui.Apply)
  $ui.Clear.Add_Click({ $ui.Search.Clear(); $ui.Id.Clear(); $ui.Route.Clear(); $ui.From.Checked=$false; $ui.To.Checked=$false; if ($ui.Event.Items.Count) { $ui.Event.SelectedIndex=0 }; & $ui.Apply }.GetNewClosure())
  $ui.Grid.Add_SelectionChanged({
    $ui.Tree.Nodes.Clear(); $ui.Json.Clear()
    if (!$ui.Grid.CurrentRow -or !$ui.Grid.CurrentRow.DataBoundItem) { return }
    $row=$ui.Grid.CurrentRow.DataBoundItem
    $record=$row['JSON'] | ConvertFrom-Json
    foreach ($property in $record.PSObject.Properties) { Add-SebiHistoryTreeNode $ui.Tree.Nodes $property.Name $property.Value }
    foreach ($node in $ui.Tree.Nodes) { if ($node.Text -in @('pokemon','sent','received','before','after','pokemon_changes','fields_before','fields_after')) { $node.Expand() } }
    $ui.Json.Text=($record | ConvertTo-Json -Depth 100)
  }.GetNewClosure())
  return $ui
}

function Set-SebiHistoryWindowData($Ui,$Table,[string]$Path) {
  $Ui.Grid.DataSource=$null
  if ($Ui.Table) { $Ui.Table.Clear(); $Ui.Table.Dispose() }
  $Ui.Table=$Table; $Ui.View=$Table.DefaultView; $Ui.View.Sort='Fecha DESC, Numero DESC'
  $Ui.Grid.DataSource=$Ui.View; $Ui.Path.Text=[IO.Path]::GetFileName($Path); $Ui.HistoryFile=$Path
  $Ui.Event.Items.Clear()
  [void]$Ui.Event.Items.Add([pscustomobject]@{Label='Todos los eventos';Code=''})
  foreach ($event in @($Table.Rows | ForEach-Object { $_.Tipo } | Sort-Object -Unique)) {
    $label=if ($script:SebiHistoryLabels.ContainsKey($event)) { $script:SebiHistoryLabels[$event] } else { $event }
    [void]$Ui.Event.Items.Add([pscustomobject]@{Label=$label;Code=$event})
  }
  $Ui.Event.DisplayMember='Label'; $Ui.Event.SelectedIndex=0; & $Ui.Apply
}

function Read-SebiViewerPassword {
  $dialog=New-Object Windows.Forms.Form; $dialog.Text='SebiLink - Acceso al historial'; $dialog.Size=New-Object Drawing.Size(480,185)
  $dialog.StartPosition='CenterScreen'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
  $dialog.Font=New-Object Drawing.Font('Segoe UI',10)
  $label=New-Object Windows.Forms.Label; $label.Text='Introduce la contrasena de tu clave privada:'; $label.SetBounds(18,16,425,24)
  $box=New-Object Windows.Forms.TextBox; $box.UseSystemPasswordChar=$true; $box.SetBounds(18,48,425,27)
  $ok=New-Object Windows.Forms.Button; $ok.Text='Desbloquear'; $ok.SetBounds(328,91,115,32); $ok.DialogResult='OK'
  $cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancelar'; $cancel.SetBounds(207,91,110,32); $cancel.DialogResult='Cancel'
  $dialog.Controls.AddRange(@($label,$box,$ok,$cancel)); $dialog.AcceptButton=$ok; $dialog.CancelButton=$cancel
  try { if ($dialog.ShowDialog() -ne 'OK') { return $null }; return ConvertTo-SecureString $box.Text -AsPlainText -Force }
  finally { $box.Clear(); $dialog.Dispose() }
}

function Select-SebiHistoryFile([string]$Directory,[bool]$Private=$false) {
  $dialog=New-Object Windows.Forms.OpenFileDialog
  $dialog.InitialDirectory=$Directory
  if ($Private) { $dialog.Title='Seleccionar tu clave privada cifrada'; $dialog.Filter='Clave SebiLink (*.sebikey)|*.sebikey' }
  else { $dialog.Title='Abrir historial de cualquier jugador'; $dialog.Filter='Historial SebiLink (*.sebilog)|*.sebilog' }
  try { if ($dialog.ShowDialog() -eq 'OK') { return $dialog.FileName }; return '' } finally { $dialog.Dispose() }
}

function Read-SebiViewerTable([string]$Path,[string]$PrivateKey) {
  # Loading in a function prevents crypto parameters from replacing viewer paths.
  if (!('SebiHistoryVault' -as [type])) { . (Join-Path $PSScriptRoot 'SebiActivityCrypto.ps1') -Mode Library }
  $secure=Read-SebiViewerPassword
  if ($null -eq $secure) { return $null }
  $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $clear=$null
  try {
    $clear=[SebiHistoryVault]::ReadFile($Path,$PrivateKey,[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))
    return ConvertTo-SebiHistoryTable $clear
  } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose(); $clear=$null }
}

if ($Mode -eq 'Library') { return }
if (!$ConfigDir) { throw 'Falta la carpeta del historial.' }
function Initialize-SebiViewerDirectory([string]$Directory) {
  # A legacy launcher may move its own folder; load crypto before migrating.
  if (!('SebiHistoryVault' -as [type])) { . (Join-Path $PSScriptRoot 'SebiActivityCrypto.ps1') -Mode Library }
  return [SebiHistoryVault]::PrepareDirectory($Directory)
}
$ConfigDir = Initialize-SebiViewerDirectory $ConfigDir
if ($Mode -eq 'Install') { Install-SebiHistoryViewer $ConfigDir; return }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Data
[Windows.Forms.Application]::EnableVisualStyles()
try {
  if (!$HistoryFile) { $HistoryFile=Join-Path $ConfigDir 'historial.sebilog' }
  if (!(Test-Path -LiteralPath $HistoryFile -PathType Leaf)) { $HistoryFile=Select-SebiHistoryFile $ConfigDir; if (!$HistoryFile) { return } }
  if (!$KeyFile) { $KeyFile=Join-Path $ConfigDir 'historial-admin.sebikey' }
  if (!(Test-Path -LiteralPath $KeyFile -PathType Leaf)) { $KeyFile=Select-SebiHistoryFile $ConfigDir $true; if (!$KeyFile) { return } }
  $table=Read-SebiViewerTable $HistoryFile $KeyFile
  if ($null -eq $table) { return }
  $ui=New-SebiHistoryWindow
  Set-SebiHistoryWindowData $ui $table $HistoryFile
  $ui.Load = {
    param([bool]$Choose)
    try {
      $path=$ui.HistoryFile
      if ($Choose) { $path=Select-SebiHistoryFile ([IO.Path]::GetDirectoryName($path)); if (!$path) { return } }
      $new=Read-SebiViewerTable $path $KeyFile
      if ($null -ne $new) { Set-SebiHistoryWindowData $ui $new $path }
    } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.GetBaseException().Message,'No se pudo abrir el historial','OK','Error') }
  }.GetNewClosure()
  $ui.Open.Add_Click({ & $ui.Load $true }.GetNewClosure()); $ui.Reload.Add_Click({ & $ui.Load $false }.GetNewClosure())
  try { [void]$ui.Window.ShowDialog() }
  finally { $ui.Grid.DataSource=$null; $ui.Tree.Nodes.Clear(); $ui.Json.Clear(); $ui.Table.Clear(); $ui.Table.Dispose(); $ui.Window.Dispose() }
} catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.GetBaseException().Message,'SebiLink - Historial','OK','Error') }
