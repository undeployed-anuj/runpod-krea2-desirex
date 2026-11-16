FROM runpod/comfyui:2.2.1-rc.236-comfyuiv0.44.0-cuda12.8

COPY setup_krea2_desirex.sh /opt/krea2/setup_krea2_desirex.sh
RUN chmod 0755 /opt/krea2/setup_krea2_desirex.sh

# Verified upstream startup order: start.sh initializes/activates .venv-cu128,
# then computes FIXED_ARGS and prints this exact line immediately before main.py.
# Fail closed if the pinned base image does not contain exactly one marker.
RUN python3 - <<'PY'
from pathlib import Path
p = Path("/start.sh")
s = p.read_text()
marker = 'echo "Starting ComfyUI with args: $FIXED_ARGS"'
if s.count(marker) != 1:
    raise SystemExit(f"Expected one startup marker in /start.sh; found {s.count(marker)}")
inject = r"""
# Krea2 / DesireX bootstrap: after ComfyUI venv activation, before main.py.
if [[ "${KREA2_AUTO_SETUP:-1}" == "1" ]]; then
    /bin/bash /opt/krea2/setup_krea2_desirex.sh
else
    echo "KREA2_AUTO_SETUP=0: skipping Krea2 / DesireX setup"
fi

"""
p.write_text(s.replace(marker, inject + marker, 1))
print("Patched /start.sh: bootstrap runs after venv activation and before ComfyUI launch.")
PY
