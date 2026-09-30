$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = if ($args.Count -gt 0 -and $args[0] -match '^\d+$') { $args[0] } else { "54545" }
$TailscaleIp = $null
try {
  $TailscaleIp = (& tailscale ip -4 2>$null | Select-Object -First 1)
} catch {
  $TailscaleIp = $null
}
if (-not $TailscaleIp) {
  try {
    $TailscaleIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
      $_.InterfaceAlias -like "*Tailscale*" -or $_.IPAddress -like "100.*"
    } | Select-Object -First 1 -ExpandProperty IPAddress)
  } catch {
    $TailscaleIp = $null
  }
}
Write-Host ""
Write-Host "SebiLink servidor multijugador"
Write-Host "Puerto: $Port"
if ($TailscaleIp) {
  Write-Host "IP Tailscale de este PC: $TailscaleIp"
  Write-Host "Los otros jugadores deben poner en SebiLinkConfig\multiplayer.ini o unirse desde el menu SebiLink:"
  Write-Host "host=$TailscaleIp"
  Write-Host "port=$Port"
} else {
  Write-Host "No he podido detectar una IP de Tailscale. Abre Tailscale y comprueba que esta conectado."
}
Write-Host ""
Write-Host "Deja esta ventana abierta mientras jugais."
Write-Host ""
node "$ScriptDir\server.js" @args
