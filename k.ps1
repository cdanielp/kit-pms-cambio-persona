# Kit PMS - Cambio de Persona en RunPod - un solo comando (Windows)
# Uso en PowerShell:
#   irm https://github.com/cdanielp/kit-pms-cambio-persona/raw/main/k.ps1 | iex
# Descarga el kit y arranca scripts\inicio.ps1 (instala tu IA, guarda tu llave y la abre).
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$pmsDestino = Join-Path $HOME 'kit-pms-cambio-persona'
$pmsZip = Join-Path $env:TEMP 'kit-pms-cambio-persona.zip'
$pmsTmp = Join-Path $env:TEMP 'kit-pms-cambio-persona'
$pmsListo = $false
try {
    Write-Host '   ... Descargando el kit'
    Invoke-WebRequest 'https://github.com/cdanielp/kit-pms-cambio-persona/archive/refs/heads/main.zip' -OutFile $pmsZip -UseBasicParsing
    if (Test-Path $pmsTmp) { Remove-Item $pmsTmp -Recurse -Force }
    Expand-Archive -Path $pmsZip -DestinationPath $pmsTmp -Force
    $pmsOrigen = Get-ChildItem $pmsTmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Path $pmsDestino -Force | Out-Null
    if (Test-Path $pmsDestino) { Get-ChildItem $pmsDestino -Force | Where-Object { $_.Name -ne '.pod.json' } | Remove-Item -Recurse -Force }
    Get-ChildItem $pmsOrigen.FullName -Force | Copy-Item -Destination $pmsDestino -Recurse -Force
    try { Get-ChildItem $pmsDestino -Recurse -File | Unblock-File } catch {}
    Remove-Item $pmsZip, $pmsTmp -Recurse -Force -ErrorAction SilentlyContinue
    if ((Test-Path (Join-Path $pmsDestino 'CLAUDE.md')) -and (Test-Path (Join-Path $pmsDestino 'scripts\inicio.ps1'))) {
        Write-Host "   [OK] Kit listo en $pmsDestino" -ForegroundColor Green
        $pmsListo = $true
    } else {
        Write-Host '   [FALLO] El kit se descargo incompleto. Vuelve a pegar el comando.' -ForegroundColor Red
    }
} catch {
    Write-Host "   [FALLO] No se pudo descargar el kit: $($_.Exception.Message)" -ForegroundColor Red
}
if ($pmsListo) {
    Set-Location $pmsDestino
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pmsDestino 'scripts\inicio.ps1')
}
