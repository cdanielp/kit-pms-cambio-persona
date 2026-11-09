#!/bin/bash
# Kit PMS · Cambio de Persona · arranque dentro del pod de RunPod
# Se usa con UN comando en la terminal de Jupyter:
#   curl -fsSL https://github.com/cdanielp/kit-pms-cambio-persona/raw/main/pod/pod.sh | bash
# Lanza la instalación aparte (si cierras la pestaña, sigue corriendo)
# y te muestra el avance. Si lo vuelves a pegar, solo te muestra el avance.
# Con MODO=fondo (así lo usa el pod al arrancar) solo lanza la instalación y sale.
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/cdanielp/kit-pms-cambio-persona/main}"
KIT="${KIT:-/workspace/pms-kit}"
LOG="$KIT/instalacion.log"
mkdir -p "$KIT" || { echo "[FALLO] No pude crear $KIT. ¿Estás en un pod de RunPod?"; exit 1; }

if pgrep -f "$KIT/instalar.sh" >/dev/null 2>&1; then
  echo "La instalación ya está corriendo. Te muestro el avance..."
else
  curl -fsSL "$REPO_RAW/pod/instalar.sh" -o "$KIT/instalar.sh" \
    || { echo "[FALLO] No se pudo descargar el instalador. Revisa tu internet del pod y vuelve a pegar el comando."; exit 1; }
  curl -fsSL "$REPO_RAW/workflow/qwen21-cambio-persona-es.json" -o "$KIT/workflow.json" \
    || { echo "[FALLO] No se pudo descargar el workflow."; exit 1; }
  echo "[OK] Instalador descargado. Arrancando..."
  REPO_RAW="$REPO_RAW" setsid nohup bash "$KIT/instalar.sh" > "$LOG" 2>&1 < /dev/null &
  sleep 2
fi
[ "${MODO:-}" = "fondo" ] && exit 0

tail -n +1 -f "$LOG" &
TP=$!
while ! grep -q '##FIN_' "$LOG" 2>/dev/null; do
  pgrep -f "$KIT/instalar.sh" >/dev/null 2>&1 || { sleep 2; grep -q '##FIN_' "$LOG" || echo "[FALLO] El instalador se detuvo sin terminar. Vuelve a pegar el comando."; break; }
  sleep 3
done
sleep 1
kill $TP 2>/dev/null
