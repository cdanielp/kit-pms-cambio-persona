# =====================================================================
#  Kit PMS · Cambio de Persona · control del pod de RunPod (Windows)
#  Prompt Models Studio
#  Lo corre tu IA (Claude Code o Codex). Tú no tienes que escribir nada.
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 revisar
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 crear
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 esperar
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 reintentar
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 estado
#    powershell -ExecutionPolicy Bypass -File .\scripts\pod.ps1 borrar
# =====================================================================
param([Parameter(Position = 0)][ValidateSet('revisar', 'crear', 'esperar', 'reintentar', 'estado', 'borrar')][string]$Accion = 'revisar')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$API      = if ($env:RUNPOD_API_BASE) { $env:RUNPOD_API_BASE } else { 'https://rest.runpod.io/v1' }
$GQL      = if ($env:RUNPOD_GQL_URL) { $env:RUNPOD_GQL_URL } else { 'https://api.runpod.io/graphql' }
$PROXY    = if ($env:RUNPOD_PROXY_FMT) { $env:RUNPOD_PROXY_FMT } else { 'https://{0}-{1}.proxy.runpod.net' }
$NOMBRE   = 'pms-cambio-persona'
$CLUB     = 'https://promptmodelsstudio.com/comfyclub'
$POD_SH   = 'https://raw.githubusercontent.com/cdanielp/kit-pms-cambio-persona/main/pod/pod.sh'
$COMANDO  = 'curl -fsSL https://github.com/cdanielp/kit-pms-cambio-persona/raw/main/pod/pod.sh | bash'
$KITDIR   = Split-Path -Parent $PSScriptRoot
$ESTADO   = Join-Path $KITDIR '.pod.json'

# Al arrancar, el pod baja el instalador y lo corre solo; luego sigue el arranque normal de RunPod
$ARRANQUE = @('bash', '-c', "for i in 1 2 3 4 5 6; do curl -fsSL $POD_SH -o /tmp/pms-pod.sh && break; sleep 10; done; MODO=fondo bash /tmp/pms-pod.sh > /var/log/pms-arranque.log 2>&1; exec /start.sh")

# Intentos en orden: si no hay 4090 en la nube segura, se prueba la comunitaria y luego L40S
$INTENTOS = @(
    @{ gpu = 'NVIDIA GeForce RTX 4090'; nube = 'SECURE';    nota = 'RTX 4090 (24 GB) en nube segura' },
    @{ gpu = 'NVIDIA GeForce RTX 4090'; nube = 'COMMUNITY'; nota = 'RTX 4090 (24 GB) en nube comunitaria' },
    @{ gpu = 'NVIDIA L40S';             nube = 'SECURE';    nota = 'L40S (48 GB) en nube segura, cuesta un poco más' }
)

function OK($t)    { Write-Host "   [OK] $t" -ForegroundColor Green }
function INFO($t)  { Write-Host "   ... $t" }
function AVISO($t) { Write-Host "   [AVISO] $t" -ForegroundColor Yellow }
function FALLO($t) { Write-Host "   [FALLO] $t" -ForegroundColor Red; exit 1 }

function Llave {
    $k = $env:RUNPOD_API_KEY
    if (-not $k) { $k = [Environment]::GetEnvironmentVariable('RUNPOD_API_KEY', 'User') }
    if (-not $k) { FALLO 'No encuentro tu API key de RunPod. Cierra tu IA y vuelve a pegar el comando del PASO 3 del PDF: te la pide de nuevo.' }
    return $k.Trim()
}
$KEY = Llave
$H = @{ Authorization = "Bearer $KEY" }

function MensajeError($e) {
    $m = $null
    try { $m = $e.ErrorDetails.Message } catch {}
    if (-not $m) { $m = $e.Exception.Message }
    try { $j = $m | ConvertFrom-Json; if ($j.error) { $m = [string]$j.error } elseif ($j.message) { $m = [string]$j.message } } catch {}
    return ($m -replace '\s+', ' ').Trim()
}
function CodigoError($e) { try { return [int]$e.Exception.Response.StatusCode } catch { return 0 } }
function Api($metodo, $ruta, $cuerpo) {
    $p = @{ Uri = "$API$ruta"; Method = $metodo; Headers = $H; ContentType = 'application/json'; UseBasicParsing = $true }
    if ($null -ne $cuerpo) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($cuerpo | ConvertTo-Json -Depth 6 -Compress)) }
    return Invoke-RestMethod @p
}
function Pods {
    $r = Api 'GET' '/pods' $null
    if ($null -eq $r) { return @() }
    if ($r -is [array]) { return $r }
    if ($r.PSObject.Properties.Name -contains 'pods') { return @($r.pods) }
    return @($r)
}
function MiPod { return @(Pods | Where-Object { $_.name -eq $NOMBRE -and $_.desiredStatus -ne 'TERMINATED' }) | Select-Object -First 1 }
function Saldo {
    try {
        $q = @{ query = 'query { myself { clientBalance currentSpendPerHr } }' } | ConvertTo-Json -Compress
        return (Invoke-RestMethod -Uri $GQL -Method Post -Headers $H -ContentType 'application/json' -Body $q -UseBasicParsing).data.myself
    } catch { return $null }
}
function Url($id, $puerto) { return ($PROXY -f $id, $puerto) }
function Responde($url) {
    try { $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 5; return $true } catch {
        $c = CodigoError $_; return ($c -eq 401 -or $c -eq 403)
    }
}
function Estado { if (Test-Path $ESTADO) { try { return (Get-Content $ESTADO -Raw | ConvertFrom-Json) } catch {} }; return $null }
function Guardar($pod, $token) {
    @{ id = $pod.id; token = $token; creado = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -Path $ESTADO -Encoding UTF8
}
function LeerLog($id, $tok) {
    if (-not $tok) { return $null }
    try {
        $u = (Url $id 8888) + "/api/contents/pms-kit/instalacion.log?content=1&type=file&format=text&token=$tok"
        return (Invoke-RestMethod -Uri $u -Headers @{ Authorization = "token $tok" } -UseBasicParsing -TimeoutSec 20).content
    } catch { return $null }
}
function Final($id) {
    Write-Host ''
    Write-Host '   ============================================================' -ForegroundColor Green
    Write-Host '   LISTO. Abre ComfyUI aquí:' -ForegroundColor Green
    Write-Host "   $(Url $id 8188)" -ForegroundColor Green
    Write-Host '   ============================================================' -ForegroundColor Green
    Write-Host '   En el menú de la izquierda: Workflows > Qwen 2.1 Cambio de Persona (PMS)'
    Write-Host '   El pod cobra mientras exista. Cuando termines, bórralo (PASO 5 del PDF).'
    Write-Host ''
    Write-Host "   ¿Te gustó? Cada mes subo workflows así en ComfyClub por `$10 USD al mes: $CLUB"
    Write-Host ''
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { try { Start-Process (Url $id 8188) } catch {} }
}
function Manual($id, $tok) {
    $jup = (Url $id 8888) + '/lab'; if ($tok) { $jup = "$jup`?token=$tok" }
    Write-Host ''
    Write-Host '   Plan B (solo si la instalación no arrancó sola):'
    Write-Host "   1) Abre: $jup"
    Write-Host '   2) File > New > Terminal, pega esto y presiona Enter:'
    Write-Host "      $COMANDO"
    Write-Host ''
}

switch ($Accion) {

'revisar' {
    Write-Host ''; Write-Host ' REVISAR CUENTA DE RUNPOD'
    try { $null = Pods } catch {
        $c = CodigoError $_
        if ($c -eq 401 -or $c -eq 403) { FALLO 'RunPod rechazó tu API key. Crea otra con permiso All (PASO 2 del PDF) y vuelve a pegar el comando del PASO 3.' }
        FALLO "No pude hablar con RunPod: $(MensajeError $_)"
    }
    OK 'Tu API key funciona'
    $s = Saldo
    if ($s) {
        $b = [math]::Round([double]$s.clientBalance, 2)
        if ($b -lt 2) { AVISO "Tu saldo es `$$b USD. Recarga `$10 en https://console.runpod.io/user/billing y vuelve a pedirlo."; exit 1 }
        OK "Saldo: `$$b USD (alcanza para unas $([math]::Floor($b / 0.7)) horas de RTX 4090)"
    } else { AVISO 'No pude leer tu saldo (no es grave). Si no has recargado, recarga $10 en Billing.' }
    $p = MiPod
    if ($p) { AVISO "Ya tienes un pod del kit ($($p.id), estado $($p.desiredStatus)). No hace falta crear otro." } else { OK 'No tienes pods del kit cobrando' }
}

'crear' {
    Write-Host ''; Write-Host ' CREAR EL POD'
    $existente = MiPod
    if ($existente) {
        AVISO "Ya tienes un pod del kit ($($existente.id)). Uso ese para no cobrarte doble."
        if ($existente.desiredStatus -ne 'RUNNING') {
            try { $null = Api 'POST' "/pods/$($existente.id)/start" $null; INFO 'Lo estoy encendiendo...' } catch { AVISO "No pude encenderlo: $(MensajeError $_)" }
        }
        $pod = $existente
    } else {
        $token = -join ((48..57) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
        $pod = $null; $ultimoError = ''
        foreach ($i in $INTENTOS) {
            INFO "Probando $($i.nota)..."
            $cuerpo = [ordered]@{
                name                = $NOMBRE
                imageName           = 'runpod/comfyui:cuda12.8'
                gpuTypeIds          = @($i.gpu)
                gpuCount            = 1
                cloudType           = $i.nube
                containerDiskInGb   = 30
                volumeInGb          = 60
                volumeMountPath     = '/workspace'
                ports               = @('8188/http', '8888/http', '8080/http', '22/tcp')
                allowedCudaVersions = @('12.8', '12.9', '13.0')
                dockerEntrypoint    = $ARRANQUE
                env                 = @{ JUPYTER_PASSWORD = $token; FILEBROWSER_PASSWORD = $token }
            }
            try { $pod = Api 'POST' '/pods' $cuerpo } catch { $ultimoError = MensajeError $_; AVISO "No hubo: $ultimoError"; continue }
            if ($pod.id) {
                if ($i -ne $INTENTOS[0]) { AVISO "No había RTX 4090 en nube segura. Se usó: $($i.nota)." }
                break
            }
        }
        if (-not $pod -or -not $pod.id) { FALLO "RunPod no tiene GPUs disponibles ahorita. Espera 10 a 20 minutos y vuelve a pedirlo. Mientras no se crea, no cobra nada. Último mensaje: $ultimoError" }
        Guardar $pod $token
        OK "Pod creado: $($pod.id) (cuesta `$$($pod.costPerHr) USD por hora)"
    }
    OK 'El pod se va a instalar solo: ComfyUI, nodos, 18 GB de modelos y el workflow.'
    INFO 'Ahora se instala solo. Te muestro el avance.'
}

'esperar' {
    $p = MiPod
    if (-not $p) { FALLO 'No tienes ningún pod del kit. Pide primero que lo cree.' }
    $e = Estado; $tok = if ($e -and $e.id -eq $p.id) { $e.token } else { $null }
    $creado = if ($e -and $e.creado) { [datetime]$e.creado } else { Get-Date }
    Write-Host ''; Write-Host " INSTALANDO EN EL POD $($p.id) (de 20 a 30 minutos en total)"
    $ultimo = ''; $ultimaBarra = ''
    $fin = (Get-Date).AddSeconds(100)
    while ((Get-Date) -lt $fin) {
        $log = LeerLog $p.id $tok
        if ($log) {
            $lineas = $log -split "`r?`n"
            if ($log -match '##FIN_OK##') { OK 'Instalación terminada'; Final $p.id; exit 0 }
            if ($log -match '##FIN_FALLO##') {
                Write-Host '   [FALLO] La instalación se detuvo. Últimas líneas:' -ForegroundColor Red
                $lineas | Where-Object { $_ -and $_ -notmatch '##FIN_' } | Select-Object -Last 15 | ForEach-Object { Write-Host "      $_" }
                Manual $p.id $tok; exit 1
            }
            $paso = $lineas | Where-Object { $_ -match 'PASO \d de \d' } | Select-Object -Last 1
            $barra = $lineas | Where-Object { $_ -match '\[[#-]{20}\]' } | Select-Object -Last 1
            if ("$paso" -ne $ultimo) {
                INFO ("{0} · {1}" -f (Get-Date -Format 'HH:mm:ss'), ($paso -replace '^\s+', ''))
                $ultimo = "$paso"
            }
            if ($barra -and "$barra" -ne $ultimaBarra -and "$paso" -match 'PASO 5') {
                Write-Host "      $($barra.Trim())"
                $ultimaBarra = "$barra"
            }
        } else {
            $min = [math]::Round(((Get-Date) - $creado).TotalMinutes)
            if ($min -ge 15 -and $tok) { AVISO "Pasaron $min minutos y la instalación no aparece."; Manual $p.id $tok; exit 1 }
            INFO ("{0} · el pod está arrancando ({1} min)..." -f (Get-Date -Format 'HH:mm:ss'), $min)
        }
        Start-Sleep -Seconds 20
    }
    INFO 'Sigue instalando (normal). Vuelve a correr: pod.ps1 esperar'
    exit 2
}

'reintentar' {
    $p = MiPod
    if (-not $p) { FALLO 'No tienes ningún pod del kit. Pide primero que lo cree.' }
    INFO "Reiniciando el pod $($p.id) para repetir la instalación (lo que ya bajó no se vuelve a bajar)..."
    try { $null = Api 'POST' "/pods/$($p.id)/restart" $null } catch {
        try { $null = Api 'POST' "/pods/$($p.id)/stop" $null; Start-Sleep -Seconds 10; $null = Api 'POST' "/pods/$($p.id)/start" $null } catch { FALLO "No pude reiniciar el pod: $(MensajeError $_)" }
    }
    Start-Sleep -Seconds 45
    OK 'Pod reiniciado. Sigue con: pod.ps1 esperar'
}

'estado' {
    $p = MiPod
    if (-not $p) { OK 'No tienes ningún pod del kit. No te está cobrando nada.'; exit 0 }
    Write-Host ''; Write-Host " POD $($p.id): $($p.desiredStatus) · `$$($p.costPerHr) USD por hora"
    $listo = $false
    try { $listo = (Invoke-WebRequest -Uri "$(Url $p.id 8188)/object_info/TextEncodeQwenImage21" -UseBasicParsing -TimeoutSec 15).Content -match 'TextEncodeQwenImage21' } catch {}
    if ($listo) { Final $p.id } else { AVISO 'ComfyUI todavía no está listo. Corre "pod.ps1 esperar" para ver el avance.' }
}

'borrar' {
    $todos = @(Pods | Where-Object { $_.name -eq $NOMBRE -and $_.desiredStatus -ne 'TERMINATED' })
    if ($todos.Count -eq 0) { OK 'No hay pods del kit. No te está cobrando nada.'; if (Test-Path $ESTADO) { Remove-Item $ESTADO -Force }; exit 0 }
    foreach ($p in $todos) {
        try { $null = Api 'DELETE' "/pods/$($p.id)" $null; INFO "Borrando $($p.id)..." } catch { FALLO "No pude borrar $($p.id): $(MensajeError $_)" }
    }
    Start-Sleep -Seconds 20
    $quedan = @(Pods | Where-Object { $_.name -eq $NOMBRE -and $_.desiredStatus -ne 'TERMINATED' })
    if ($quedan.Count -gt 0) { FALLO 'RunPod todavía muestra el pod. Bórralo en https://console.runpod.io/pods con el botón Terminate.' }
    if (Test-Path $ESTADO) { Remove-Item $ESTADO -Force }
    OK 'Pod borrado. Ya no te cobra nada.'
    Write-Host "   Para la próxima, vuelve a pegar el comando del PASO 3. Y si quieres más workflows así: $CLUB"
}
}
exit 0
