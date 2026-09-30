param(
  [ValidateSet('Check','Prepare')][string]$Mode = 'Check',
  [Parameter(Mandatory=$true)][string]$GameDir,
  [Parameter(Mandatory=$true)][string]$RuntimeDir,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9-]+$')][string]$RequestId,
  [string]$Commit = '',
  [string]$ExpectedVersion = '',
  [int]$ParentPid = 0
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'SebiUpdateCore.ps1')
$GameDir = [IO.Path]::GetFullPath($GameDir)
$RuntimeDir = [IO.Path]::GetFullPath($RuntimeDir)
[void](New-Item -ItemType Directory -Path $RuntimeDir -Force)
$resultPath = Resolve-SebiChild $RuntimeDir ($Mode.ToLowerInvariant() + '-' + $RequestId + '.ini')
$gameExited = $false
$finished = $false

function Write-UpdateResult {
  param([string]$Status, [string]$Version='', [string]$Sha='', [string]$Message='')
  $safeMessage = $Message -replace '[\r\n]+',' '
  $lines = @("request_id=$RequestId", "status=$Status", "version=$Version", "commit=$Sha", "message=$safeMessage")
  $tmp = $resultPath + '.tmp'
  [IO.File]::WriteAllLines($tmp, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $resultPath) { [IO.File]::Replace($tmp,$resultPath,[NullString]::Value) } else { [IO.File]::Move($tmp,$resultPath) }
}

function Start-UpdatedGame {
  # The user requested reopening the interactive game, so its window is visible.
  Start-Process -FilePath (Join-Path $GameDir 'Game.exe') -WorkingDirectory $GameDir -WindowStyle Normal | Out-Null
}

try {
  $source = Get-SebiSource $GameDir
  if ($Mode -eq 'Check') {
    $remote = Get-SebiRemote $source
    $status = if ((ConvertTo-SebiVersion $remote.version) -gt (ConvertTo-SebiVersion $source.version)) { 'available' } else { 'current' }
    Write-UpdateResult $status $remote.version $remote.commit
  } else {
    if ($Commit -notmatch '^[a-f0-9]{40}$' -or (ConvertTo-SebiVersion $ExpectedVersion) -le (ConvertTo-SebiVersion $source.version)) { throw 'Solicitud de actualizacion invalida.' }
    $parent = Get-Process -Id $ParentPid -ErrorAction Stop
    if (![string]::Equals([IO.Path]::GetFullPath($parent.Path), (Join-Path $GameDir 'Game.exe'), [StringComparison]::OrdinalIgnoreCase)) { throw 'El proceso solicitado no es este Pokemon Z.' }
    $jobDir = Resolve-SebiChild $RuntimeDir ('job-' + $RequestId)
    [void](New-Item -ItemType Directory -Path $jobDir -Force)
    # Persist a private copy of the running installer before replacing its source.
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $jobDir 'worker-used.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SebiUpdateCore.ps1') -Destination (Join-Path $jobDir 'core-used.ps1') -Force
    $rawBase = "https://raw.githubusercontent.com/$($source.owner)/$($source.repo)/$Commit"
    $readmeVersion = Get-SebiReadmeVersion (Invoke-SebiText "$rawBase/README.md") $source.package_path
    if ($readmeVersion -ne $ExpectedVersion) { throw 'La version confirmada no coincide con ese commit.' }
    $remote = [PSCustomObject]@{version=$ExpectedVersion; commit=$Commit; raw_base=$rawBase}
    $stage = Get-SebiStage $source $remote $jobDir
    Write-UpdateResult 'ready' $ExpectedVersion $Commit
    # Ruby authorizes restart only after the save succeeded and staging was checked.
    $ack = Resolve-SebiChild $RuntimeDir ('restart-' + $RequestId + '.txt')
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (!(Test-Path -LiteralPath $ack)) {
      if ($parent.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Reinicio no autorizado; no se ha instalado la descarga.' }
      Start-Sleep -Milliseconds 100
      $parent.Refresh()
    }
    if ([IO.File]::ReadAllText($ack).Trim() -ne $RequestId) { throw 'Confirmacion de reinicio invalida.' }
    if (!$parent.WaitForExit(30000)) { throw 'El juego sigue abierto; no se han sustituido archivos.' }
    $gameExited = $true
    Install-SebiStage $GameDir $stage $jobDir $ExpectedVersion
    $finished = $true
    Write-UpdateResult 'installed' $ExpectedVersion $Commit
    Start-UpdatedGame
  }
} catch {
  $message = $_.Exception.Message
  Write-UpdateResult 'error' '' '' $message
  if ($gameExited) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($message, 'Actualizacion SebiLink - Pokemon Z')
    # A failed install has rolled back; a launch error can be retried manually.
    if (!$finished) { Start-UpdatedGame }
  }
  exit 1
}
