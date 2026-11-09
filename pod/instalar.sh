#!/bin/bash
# =====================================================================
#  Kit PMS · Cambio de Persona (Qwen Image 2.1) · instalador del pod
#  Prompt Models Studio · Corre DENTRO del pod de RunPod.
#  No lo corras a mano: lo lanza pod.sh con un solo comando.
# =====================================================================
set -u

# ---------- configuración (rutas absolutas) ----------
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/cdanielp/kit-pms-cambio-persona/main}"
SLIM="${SLIM:-/workspace/runpod-slim}"
COMFY="$SLIM/ComfyUI"
KIT="${KIT:-/workspace/pms-kit}"
COMFY_TAG="${COMFY_TAG:-v0.38.0}"        # versión probada por el autor del workflow
COMFY_MIN="0.38.0"
CLUB_URL="${CLUB_URL:-https://promptmodelsstudio.com/comfyclub}"
AUSBOSS_VER="${AUSBOSS_VER:-2.23.0}"
AUSBOSS_ZIP="${AUSBOSS_ZIP:-https://cdn.comfy.org/ausboss/ausboss-nodes/${AUSBOSS_VER}/node.zip}"
WF_TITULO="Qwen 2.1 Cambio de Persona (PMS)"
WF_NOMBRE="$WF_TITULO.json"
LOG_COMFY="$SLIM/comfyui.log"
# Para pruebas: SKIP_PIP=1 SKIP_MODELOS=1 SKIP_REINICIO=1
SKIP_PIP="${SKIP_PIP:-0}"; SKIP_MODELOS="${SKIP_MODELOS:-0}"; SKIP_REINICIO="${SKIP_REINICIO:-0}"

# repo | archivo en el repo | carpeta destino | bytes exactos
MODELOS=(
  "Comfy-Org/Qwen-Image-2.1|diffusion_models/qwen_image_2.1_int8_convrot.safetensors|diffusion_models|7256783064"
  "Comfy-Org/Qwen-Image-2.1|text_encoders/qwen3vl_8b_int8_convrot.safetensors|text_encoders|9350798360"
  "Comfy-Org/Qwen-Image-2.1|vae/qwen_image_2.1_vae_bf16.safetensors|vae|675509688"
  "Alissonerdx/BFS-Best-Face-Swap|bfs_body_swap_v1.0_qwen_2.1.safetensors|loras|209753576"
  "Alissonerdx/BFS-Best-Face-Swap|bfs_head_v1.1_qwen_2.1.safetensors|loras|260096144"
  "t8star/Pruna-Qwen-Image-2.1-Comfy|p_qwen_image_2.1_8step_v0.1-comfyui-T8.safetensors|loras|335633936"
)
NODOS_CLAVE=(TextEncodeQwenImage21 QwenImage21Cache ComfySwitchNode AUSBOSS_NODES_LoraLoader AUSBOSS_NODES_WorkflowNote)

TOTAL=7
ok()    { echo "   [OK] $*"; }
info()  { echo "   ... $*"; }
aviso() { echo "   [AVISO] $*"; }
paso()  { echo; echo "=================================================="; echo " PASO $1 de $TOTAL · $2"; echo "=================================================="; }
falla() {
  echo
  echo "   [FALLO] $*"
  echo
  echo "   La instalación se detuvo aquí. Tu IA (Claude Code o Codex) ya"
  echo "   puede ver este mensaje: pídele \"revisa qué falló\"."
  echo "##FIN_FALLO##"
  exit 1
}
ver_a_num() { echo "$1" | sed 's/^v//' | awk -F. '{printf "%d%03d%03d", $1, $2, $3}'; }
tam() { stat -c %s "$1" 2>/dev/null || echo 0; }

echo
echo "  Kit PMS · Cambio de Persona en RunPod"
echo "  Prompt Models Studio · Menos teoría. Más terminal."
echo "  Inicio: $(date '+%H:%M:%S')"

# ---------------------------------------------------------------------
paso 1 "Revisar el pod"
command -v nvidia-smi >/dev/null && GPU="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)" || GPU=""
[ -n "$GPU" ] && ok "GPU: $GPU" || aviso "No pude leer la GPU (sigo de todos modos)"
info "Esperando a que RunPod termine de preparar ComfyUI (máximo 12 min)..."
arriba=0
for _ in $(seq 1 144); do
  curl -fs -m 5 --noproxy "*" http://127.0.0.1:8188/system_stats >/dev/null 2>&1 && { arriba=1; break; }
  sleep 5
done
[ -f "$COMFY/main.py" ] || falla "No encuentro ComfyUI en $COMFY. ¿El pod se creó con la imagen runpod/comfyui?"
[ $arriba = 1 ] && ok "ComfyUI de RunPod listo en $COMFY" || aviso "ComfyUI no respondió todavía, sigo con la instalación de todos modos"
if [ -x "$COMFY/.venv-cu128/bin/python" ]; then PY="$COMFY/.venv-cu128/bin/python"; else PY="$(command -v python3)"; fi
ok "Python: $PY"
LIBRE_GB=$(df -BG --output=avail /workspace 2>/dev/null | tail -1 | tr -dc '0-9')
info "Espacio libre reportado en /workspace: ${LIBRE_GB:-?} GB (se necesitan unos 25 GB)"
mkdir -p "$KIT" || falla "No pude crear $KIT"

# ---------------------------------------------------------------------
paso 2 "Actualizar ComfyUI a $COMFY_TAG (el workflow lo necesita)"
VER_ACTUAL="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$COMFY/comfyui_version.py" 2>/dev/null | head -1)"
info "Versión instalada: ${VER_ACTUAL:-desconocida}"
if [ -n "$VER_ACTUAL" ] && [ "$(ver_a_num "$VER_ACTUAL")" -ge "$(ver_a_num "$COMFY_MIN")" ]; then
  ok "Ya tiene $VER_ACTUAL, no hace falta actualizar"
else
  TMPD="$(mktemp -d)"
  info "Descargando ComfyUI $COMFY_TAG..."
  curl -fsSL "${COMFY_TARBALL:-https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFY_TAG}.tar.gz}" -o "$TMPD/comfy.tar.gz" \
    || falla "No se pudo descargar ComfyUI $COMFY_TAG de GitHub"
  NUEVO="$SLIM/ComfyUI.nuevo"; VIEJO="$SLIM/ComfyUI.anterior"
  rm -rf "$NUEVO" "$VIEJO"; mkdir -p "$NUEVO"
  tar xzf "$TMPD/comfy.tar.gz" --strip-components=1 -C "$NUEVO" || falla "El archivo de ComfyUI llegó dañado"
  [ -f "$NUEVO/main.py" ] || falla "El archivo de ComfyUI no trae main.py"
  # historial git mínimo, igual que lo hace la imagen de RunPod
  ( cd "$NUEVO" && git init -q && git -c user.name=pms -c user.email=pms@local add -A >/dev/null 2>&1 \
      && git -c user.name=pms -c user.email=pms@local commit -qm "ComfyUI $COMFY_TAG" && git tag "$COMFY_TAG" \
      && git remote add origin https://github.com/comfyanonymous/ComfyUI.git ) >/dev/null 2>&1 \
    || aviso "No pude crear el historial git (no afecta al workflow)"
  # se conserva todo lo del usuario: entorno, nodos, modelos, entradas, salidas, ajustes
  for d in .venv-cu128 .venv custom_nodes models input output user extra_model_paths.yaml .runpod-bundle-version; do
    if [ -e "$COMFY/$d" ]; then rm -rf "${NUEVO:?}/$d"; mv "$COMFY/$d" "$NUEVO/$d" || falla "No pude mover $d"; fi
  done
  mv "$COMFY" "$VIEJO" && mv "$NUEVO" "$COMFY" || falla "No pude cambiar la carpeta de ComfyUI"
  rm -rf "$VIEJO" "$TMPD"
  VER_NUEVA="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$COMFY/comfyui_version.py" | head -1)"
  [ "$(ver_a_num "$VER_NUEVA")" -ge "$(ver_a_num "$COMFY_MIN")" ] || falla "La versión quedó en $VER_NUEVA"
  ok "Código de ComfyUI actualizado a $VER_NUEVA"
  if [ "$SKIP_PIP" = "1" ]; then aviso "SKIP_PIP=1: no instalo dependencias (modo prueba)"; else
    info "Instalando dependencias de ComfyUI (2 a 4 min)..."
    CONS=""; [ -f /opt/comfyui-runtime-constraints.txt ] && CONS="-c /opt/comfyui-runtime-constraints.txt"
    # shellcheck disable=SC2086
    "$PY" -m pip install -q --disable-pip-version-check -r "$COMFY/requirements.txt" $CONS > "$KIT/pip-comfyui.log" 2>&1 \
      || { tail -15 "$KIT/pip-comfyui.log"; falla "Fallaron las dependencias de ComfyUI (detalle en $KIT/pip-comfyui.log)"; }
    ok "Dependencias instaladas"
  fi
fi

# ---------------------------------------------------------------------
paso 3 "Instalar AusBoss nodes $AUSBOSS_VER"
DEST_AB="$COMFY/custom_nodes/ausboss-nodes"
if [ -f "$DEST_AB/.pms-version" ] && [ "$(cat "$DEST_AB/.pms-version")" = "$AUSBOSS_VER" ]; then
  ok "Ya estaban instalados ($AUSBOSS_VER)"
else
  # quitar copias anteriores con otro nombre para que no se carguen dos veces
  for d in "$COMFY"/custom_nodes/ComfyUI-AusBoss "$COMFY"/custom_nodes/comfyui-ausboss; do [ -d "$d" ] && rm -rf "$d"; done
  TMPZ="$(mktemp -d)"
  curl -fsSL "$AUSBOSS_ZIP" -o "$TMPZ/node.zip" || falla "No se pudo descargar AusBoss nodes del registro de Comfy"
  rm -rf "$DEST_AB"; mkdir -p "$DEST_AB"
  "$PY" -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMPZ/node.zip" "$DEST_AB" \
    || falla "No se pudo descomprimir AusBoss nodes"
  rm -rf "$TMPZ"
  [ -f "$DEST_AB/__init__.py" ] || falla "AusBoss nodes quedó incompleto (no hay __init__.py)"
  if [ -f "$DEST_AB/requirements.txt" ] && [ "$SKIP_PIP" != "1" ]; then
    CONS=""; [ -f /opt/comfyui-runtime-constraints.txt ] && CONS="-c /opt/comfyui-runtime-constraints.txt"
    # shellcheck disable=SC2086
    "$PY" -m pip install -q --disable-pip-version-check -r "$DEST_AB/requirements.txt" $CONS > "$KIT/pip-ausboss.log" 2>&1 \
      || aviso "Algunas dependencias opcionales de AusBoss no se instalaron (no afectan a este workflow)"
  fi
  echo "$AUSBOSS_VER" > "$DEST_AB/.pms-version"
  ok "AusBoss nodes $AUSBOSS_VER instalado en custom_nodes/ausboss-nodes"
fi

# ---------------------------------------------------------------------
paso 4 "Preparar el descargador de modelos"
HFV="${HFV:-$SLIM/hf-venv}"
if [ "$SKIP_MODELOS" = "1" ]; then aviso "SKIP_MODELOS=1: no preparo el descargador (modo prueba)"; else
  if [ ! -x "$HFV/bin/hf" ]; then
    python3 -m venv "$HFV" >/dev/null 2>&1 || falla "No pude crear el entorno del descargador"
    "$HFV/bin/pip" install -q --disable-pip-version-check -U "huggingface_hub[hf_xet]" > "$KIT/pip-hf.log" 2>&1 \
      || falla "No pude instalar el descargador de HuggingFace"
  fi
  [ -x "$HFV/bin/hf" ] || falla "El descargador no quedó instalado"
  ok "Descargador listo (modo rápido de HuggingFace)"
fi

# ---------------------------------------------------------------------
paso 5 "Descargar los modelos (18.1 GB en total)"
M="$COMFY/models"
FALTAN=(); META=0
for item in "${MODELOS[@]}"; do
  IFS='|' read -r repo ruta carpeta bytes <<< "$item"
  final="$M/$carpeta/$(basename "$ruta")"
  if [ "$(tam "$final")" = "$bytes" ]; then ok "Ya estaba: $(basename "$ruta")"; else FALTAN+=("$item"); META=$((META + bytes)); fi
done
if [ ${#FALTAN[@]} -eq 0 ]; then ok "Todos los modelos ya estaban completos"
elif [ "$SKIP_MODELOS" = "1" ]; then aviso "SKIP_MODELOS=1: faltan ${#FALTAN[@]} modelos pero no descargo (modo prueba)"
else
  export HF_XET_HIGH_PERFORMANCE=1 HF_HUB_DISABLE_PROGRESS_BARS=1 HF_HUB_DISABLE_TELEMETRY=1
  DL="$SLIM/descargas"; mkdir -p "$DL"
  find "$DL" -name '*.lock' -delete 2>/dev/null
  META_GB=$(awk "BEGIN{printf \"%.1f\", $META/1e9}")
  info "Faltan ${#FALTAN[@]} archivos ($META_GB GB). Verás el avance cada 20 segundos."
  BASE=$(du -sb "$DL" 2>/dev/null | cut -f1)
  (  # monitor: hora, GB de la meta, MB/s y barra
    prev=$BASE
    while sleep 20; do
      now=$(du -sb "$DL" 2>/dev/null | cut -f1); hecho=$((now - BASE)); [ $hecho -lt 0 ] && hecho=0
      [ $hecho -gt "$META" ] && hecho=$META
      pct=$((hecho * 100 / META)); llenos=$((pct / 5))
      barra="$(printf '%*s' "$llenos" '' | tr ' ' '#')$(printf '%*s' $((20 - llenos)) '' | tr ' ' '-')"
      mbs=$(awk "BEGIN{printf \"%.0f\", ($now-$prev)/20/1e6}"); prev=$now
      printf "   %s [%s] %3d%%  %s de %s GB  %s MB/s\n" "$(date +%H:%M:%S)" "$barra" "$pct" \
        "$(awk "BEGIN{printf \"%.1f\", $hecho/1e9}")" "$META_GB" "$mbs"
    done
  ) &
  MON=$!
  trap 'kill $MON 2>/dev/null' EXIT
  n=0
  for item in "${FALTAN[@]}"; do
    n=$((n + 1)); IFS='|' read -r repo ruta carpeta bytes <<< "$item"
    archivo="$(basename "$ruta")"; final="$M/$carpeta/$archivo"
    info "($n/${#FALTAN[@]}) $archivo"
    intento=0
    until [ "$(tam "$DL/$ruta")" = "$bytes" ]; do
      intento=$((intento + 1)); [ $intento -gt 3 ] && break
      [ $intento -gt 1 ] && aviso "Reintento $intento de 3 para $archivo"
      find "$DL" -name '*.lock' -delete 2>/dev/null
      "$HFV/bin/hf" download "$repo" "$ruta" --local-dir "$DL" >> "$KIT/descargas.log" 2>&1
    done
    [ "$(tam "$DL/$ruta")" = "$bytes" ] || { kill $MON 2>/dev/null; tail -5 "$KIT/descargas.log"; falla "$archivo no bajó completo (esperaba $bytes bytes)"; }
    ok "$archivo descargado completo"
  done
  kill $MON 2>/dev/null; trap - EXIT
  # se mueven al final para que el monitor no cuente de menos
  for item in "${FALTAN[@]}"; do
    IFS='|' read -r repo ruta carpeta bytes <<< "$item"
    mkdir -p "$M/$carpeta" && mv -f "$DL/$ruta" "$M/$carpeta/$(basename "$ruta")" || falla "No pude mover $(basename "$ruta") a models/$carpeta"
    ok "$(basename "$ruta") → models/$carpeta"
  done
  rm -rf "$DL"
  for item in "${MODELOS[@]}"; do
    IFS='|' read -r repo ruta carpeta bytes <<< "$item"
    [ "$(tam "$M/$carpeta/$(basename "$ruta")")" = "$bytes" ] || falla "Revisión final: $(basename "$ruta") no tiene el tamaño correcto"
  done
  ok "Los 6 modelos están completos (revisados por tamaño exacto)"
fi

# ---------------------------------------------------------------------
paso 6 "Poner el workflow en el menú de ComfyUI"
WFD="$COMFY/user/default/workflows"; mkdir -p "$WFD"
if [ -f "$KIT/workflow.json" ]; then cp -f "$KIT/workflow.json" "$WFD/$WF_NOMBRE"
else curl -fsSL "$REPO_RAW/workflow/qwen21-cambio-persona-es.json" -o "$WFD/$WF_NOMBRE" || falla "No se pudo descargar el workflow"; fi
"$PY" -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['nodes']" "$WFD/$WF_NOMBRE" 2>/dev/null \
  || falla "El workflow descargado está dañado"
ok "Workflow guardado: Workflows → $WF_TITULO"

# ---------------------------------------------------------------------
paso 7 "Reiniciar ComfyUI y comprobar los nodos"
if [ "$SKIP_REINICIO" = "1" ]; then aviso "SKIP_REINICIO=1: no reinicio (modo prueba)"; else
  pkill -f "main.py --listen" 2>/dev/null; sleep 3; pkill -9 -f "main.py --listen" 2>/dev/null
  ARGS=""; [ -f "$SLIM/comfyui_args.txt" ] && ARGS="$(grep -v '^\s*#' "$SLIM/comfyui_args.txt" | tr '\n' ' ')"
  info "Arrancando ComfyUI (1 a 3 min)..."
  # shellcheck disable=SC2086
  ( cd "$COMFY" && setsid nohup "$PY" main.py --listen 0.0.0.0 --port 8188 --enable-cors-header $ARGS > "$LOG_COMFY" 2>&1 < /dev/null & )
  listo=0
  for _ in $(seq 1 60); do
    curl -fs -m 10 --noproxy "*" http://127.0.0.1:8188/system_stats >/dev/null 2>&1 && { listo=1; break; }
    sleep 5
  done
  [ $listo = 1 ] || { tail -25 "$LOG_COMFY"; falla "ComfyUI no arrancó en 5 minutos (registro: $LOG_COMFY)"; }
  ok "ComfyUI respondiendo en el puerto 8188"
  for nodo in "${NODOS_CLAVE[@]}"; do
    curl -fs -m 10 --noproxy "*" "http://127.0.0.1:8188/object_info/$nodo" | grep -q "\"$nodo\"" \
      || { grep -iE "import failed|error" "$LOG_COMFY" | tail -10; falla "ComfyUI no reconoce el nodo $nodo"; }
  done
  ok "Los ${#NODOS_CLAVE[@]} nodos clave del workflow están cargados"
fi

POD="${RUNPOD_POD_ID:-TU_POD}"
echo
echo "=================================================="
echo " LISTO · $(date '+%H:%M:%S')"
echo "=================================================="
echo
echo "  1. Abre ComfyUI en esta liga:"
echo "     https://${POD}-8188.proxy.runpod.net"
echo "  2. Menú de la izquierda: Workflows → $WF_TITULO"
echo "  3. Carga tus 2 fotos y presiona Run."
echo
echo "  IMPORTANTE: el pod cobra mientras exista. Cuando termines,"
echo "  dile a tu IA: \"borra mi pod\"."
echo
echo "  ¿Te gustó? Cada mes subo workflows así, listos para copiar y pegar,"
echo "  en ComfyClub por \$10 USD al mes: $CLUB_URL"
echo "##FIN_OK##"
