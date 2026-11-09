# =====================================================================
#  Kit PMS · Cambio de Persona · arranque en Windows (un solo comando)
#  Prompt Models Studio
#  Lo lanza k.ps1. Hace todo en orden y se detiene si algo falla:
#    1. Pregunta el modo: automático (sin IA) o con Claude Code / Codex
#    2. Guarda tu API key de RunPod (solo la primera vez)
#    3. Automático: crea el pod, espera y abre ComfyUI. Con IA: abre tu IA con la petición escrita
# =====================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$KIT      = Split-Path -Parent $PSScriptRoot
$API      = if ($env:RUNPOD_API_BASE) { $env:RUNPOD_API_BASE } else { 'https://rest.runpod.io/v1' }
$AFILIADO = 'https://runpod.io?ref=niyj2mry'
$PETICION = 'Ábreme el workflow en RunPod'

function OK($t)    { Write-Host "   [OK] $t" -ForegroundColor Green }
function INFO($t)  { Write-Host "   ... $t" }
function FALLO($t) { Write-Host "   [FALLO] $t" -ForegroundColor Red; exit 1 }
function Paso($n, $t) { Write-Host ''; Write-Host " PASO $n de 3 · $t" -ForegroundColor Cyan }
function RefrescarPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') +
                ";$HOME\.local\bin;$env:LOCALAPPDATA\Programs\codex;$env:APPDATA\npm"
}
function Tiene($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

Write-Host ''
Write-Host '  Kit PMS · Cambio de Persona en RunPod' -ForegroundColor White
Write-Host '  Prompt Models Studio · Menos teoría. Más terminal.'

# ---------------------------------------------------------------------
Paso 1 'Cómo lo quieres hacer'
Write-Host '     1) Automático: el kit hace todo solo (recomendado, no necesitas nada más)'
Write-Host '     2) Con Claude Code (necesitas Claude Pro o superior)'
Write-Host '     3) Con Codex (necesitas ChatGPT Plus o superior)'
$op = (Read-Host '   Escribe 1, 2 o 3 y presiona Enter').Trim()
$ia = switch ($op) { '2' { 'claude' } '3' { 'codex' } default { 'auto' } }
if ($ia -eq 'auto') { OK 'Modo automático' } else {
    RefrescarPath
    $nombreIA = if ($ia -eq 'claude') { 'Claude Code' } else { 'Codex' }
    if (Tiene $ia) { OK "Ya tienes $nombreIA" } else {
        INFO "Instalando $nombreIA (1 a 3 minutos)..."
        $url = if ($ia -eq 'claude') { 'https://claude.ai/install.ps1' } else { 'https://chatgpt.com/codex/install.ps1' }
        try { Invoke-RestMethod $url | Invoke-Expression } catch { FALLO "No se pudo instalar ${nombreIA}: $($_.Exception.Message)" }
        RefrescarPath
        if (-not (Tiene $ia)) { FALLO 'Se instaló, pero esta ventana todavía no la ve. Cierra PowerShell, ábrelo de nuevo y vuelve a pegar el mismo comando.' }
        OK "$nombreIA instalado"
    }
}

# ---------------------------------------------------------------------
Paso 2 'Tu llave de RunPod'
function Probar($k) {
    try { $null = Invoke-RestMethod -Uri "$API/pods" -Headers @{ Authorization = "Bearer $k" } -UseBasicParsing; return $true } catch { return $false }
}
$k = [Environment]::GetEnvironmentVariable('RUNPOD_API_KEY', 'User')
if ($k -and (Probar $k.Trim())) {
    OK 'Tu llave ya estaba guardada y funciona'
} else {
    if ($k) { Write-Host '   La llave guardada ya no funciona. Pega una nueva.' -ForegroundColor Yellow }
    Write-Host "   Si todavía no tienes cuenta de RunPod, créala aquí: $AFILIADO"
    Write-Host '   Pega tu API key de RunPod (PASO 2 del PDF) y presiona Enter.'
    Write-Host '   No se ve lo que pegas: es normal, es para cuidarla.'
    for ($intento = 1; $intento -le 3; $intento++) {
        $seguro = Read-Host '   API key' -AsSecureString
        $k = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)).Trim()
        if ($k -and (Probar $k)) { break }
        Write-Host '   RunPod no aceptó esa llave. Cópiala completa y pégala otra vez.' -ForegroundColor Yellow
        $k = $null
    }
    if (-not $k) { FALLO 'No se pudo guardar la llave. Crea una nueva con permiso All (PASO 2 del PDF) y vuelve a pegar el comando.' }
    [Environment]::SetEnvironmentVariable('RUNPOD_API_KEY', $k, 'User')
    OK 'Llave guardada y probada'
}
$env:RUNPOD_API_KEY = $k.Trim()

# ---------------------------------------------------------------------
Set-Location $KIT
$POD = Join-Path $PSScriptRoot 'pod.ps1'
function Pod($accion) { $global:LASTEXITCODE = 0; & $POD $accion | Out-Host; return $global:LASTEXITCODE }

if ($ia -eq 'auto') {
    Paso 3 'Crear el pod e instalar todo (20 a 30 minutos)'
    if ((Pod 'revisar') -ne 0) { FALLO 'Arregla lo que dice arriba y vuelve a pegar el mismo comando.' }
    if ((Pod 'crear') -ne 0) { exit 1 }
    Write-Host ''
    Write-Host '   Ya puedes dejar esta ventana abierta e irte por un café.' -ForegroundColor Cyan
    Write-Host '   Cuando termine, se abre ComfyUI solo en tu navegador.' -ForegroundColor Cyan
    $reintentos = 0
    while ($true) {
        $r = Pod 'esperar'
        if ($r -eq 0) { break }
        if ($r -eq 1) {
            if ($reintentos -ge 1) { FALLO 'La instalación falló dos veces. Borra el pod con el comando del PASO 5 del PDF y vuelve a intentarlo más tarde.' }
            $reintentos++
            $null = Pod 'reintentar'
        }
    }
    Write-Host '   Para BORRAR el pod cuando termines (deja de cobrar), pega en PowerShell:' -ForegroundColor Yellow
    Write-Host '   powershell -ep Bypass -File $HOME\kit-pms-cambio-persona\scripts\pod.ps1 borrar' -ForegroundColor Yellow
    Write-Host ''
} else {
    Paso 3 'Abrir tu IA'
    OK "Carpeta del kit: $KIT"
    Write-Host '   La primera vez se abre el navegador para que inicies sesión.'
    Write-Host '   Si te pregunta si confías en la carpeta o pide permiso, elige Yes.'
    Write-Host ''
    if ($ia -eq 'claude') {
        & claude $PETICION
    } else {
        # Codex necesita internet dentro de su sandbox para hablar con RunPod
        & codex --sandbox danger-full-access --ask-for-approval on-request $PETICION
    }
}
