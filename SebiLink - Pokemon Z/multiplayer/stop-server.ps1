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
if (!(Test-Path -LiteralPath $PidFile) -and (Test-Path -LiteralPath $legacyPid)) {
  Copy-Item -LiteralPath $legacyPid -Destination $PidFile -Force -ErrorAction SilentlyContinue
}

if (Test-Path $PidFile) {
  $pidValue = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pidValue) {
    $proc = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
    if ($proc) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $legacyPid -Force -ErrorAction SilentlyContinue
}
