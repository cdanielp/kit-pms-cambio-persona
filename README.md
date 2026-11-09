# Kit PMS · Cambio de Persona en RunPod

Workflow gratis de Prompt Models Studio: abre **Qwen Image 2.1 Person Swap** (traducido al español) en RunPod pegando un solo comando. El kit crea el pod, lo instala solo y abre ComfyUI. Instrucciones paso a paso en el PDF.

¿Quieres más workflows así cada mes? **ComfyClub**, $10 USD al mes: https://promptmodelsstudio.com/comfyclub

## El único comando (PowerShell en Windows)

```
irm https://github.com/cdanielp/kit-pms-cambio-persona/raw/main/k.ps1 | iex
```

## Plan B: comando manual para la terminal del pod (JupyterLab)

```
curl -fsSL https://github.com/cdanielp/kit-pms-cambio-persona/raw/main/pod/pod.sh | bash
```

## Qué hay aquí

| Archivo | Para qué |
|---|---|
| `CLAUDE.md` / `AGENTS.md` | Instrucciones para Claude Code y Codex (mismo contenido) |
| `k.ps1` | El comando único: baja el kit y arranca `scripts/inicio.ps1` |
| `scripts/inicio.ps1` | Modo automático (sin IA) o abre Claude Code / Codex |
| `scripts/pod.ps1` | Revisar, crear, esperar, reintentar, estado y borrar el pod |
| `.claude/settings.json` | Permisos para que Claude Code corra `pod.ps1` sin preguntar |
| `pod/pod.sh` | Arranque dentro del pod (el pod lo corre solo al encender) |
| `pod/instalar.sh` | Instalador: ComfyUI v0.38.0, AusBoss nodes, 6 modelos (18.1 GB), workflow |
| `workflow/` | Workflow en español |

## Créditos y licencias

- Workflow original: **AusBoss** (Civitai, "Qwen Image 2.1 Person Swap | Head or Full Body"). Traducción y notas en español: Prompt Models Studio.
- LoRAs BFS: **Alissonerdx** (MIT). Speed LoRA: PrunaAI, conversión de t8star.
- **Qwen Image 2.1** y la Speed LoRA: Qwen Research License, **uso no comercial**.
- Usa solo fotos de personas que dieron su permiso.
