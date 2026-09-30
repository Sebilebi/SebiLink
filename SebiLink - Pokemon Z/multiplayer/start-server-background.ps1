param(
  [int]$Port = 54545,
  [string]$BindHost = "0.0.0.0"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$profile = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($profile)) {
  $profile = [Environment]::GetFolderPath("UserProfile")
}
if ([string]::IsNullOrWhiteSpace($profile)) {
  $ServerRuntimeDir = Join-Path $ScriptDir "runtime"
} else {
  $ServerRuntimeDir = Join-Path (Join-Path (Join-Path (Join-Path $profile "Saved Games") "Pokemon Z") "SebiLinkConfig") "server"
}
if (!(Test-Path -LiteralPath $ServerRuntimeDir)) {
  [void](New-Item -ItemType Directory -Path $ServerRuntimeDir -Force)
}
$legacyPid = Join-Path $ScriptDir "server.pid"
$PidFile = Join-Path $ServerRuntimeDir "server.pid"
$OutLog = Join-Path $ServerRuntimeDir "server.out.log"
$ErrLog = Join-Path $ServerRuntimeDir "server.err.log"
if (!(Test-Path -LiteralPath $PidFile) -and (Test-Path -LiteralPath $legacyPid)) {
  Copy-Item -LiteralPath $legacyPid -Destination $PidFile -Force -ErrorAction SilentlyContinue
}

if (Test-Path $PidFile) {
  $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($oldPid) {
    $oldProcess = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    if ($oldProcess) {
      Stop-Process -Id $oldProcess.Id -Force -ErrorAction SilentlyContinue
      Start-Sleep -Milliseconds 300
    }
  }
}

$env:SEBI_MULTIPLAYER_BIND_HOST = $BindHost
$nodeArgs = @("server.js", $Port)
$proc = Start-Process -FilePath "node" `
  -ArgumentList $nodeArgs `
  -WorkingDirectory $ScriptDir `
  -WindowStyle Hidden `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog `
  -PassThru

$proc.Id | Set-Content -Path $PidFile -Encoding ASCII
