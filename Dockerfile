# Pinned to the user's CUDA 12.8 RunPod ComfyUI base image.
FROM runpod/comfyui:2.2.1-rc.236-comfyuiv0.44.0-cuda12.8

COPY setup_krea2_desirex.sh /opt/krea2/setup_krea2_desirex.sh
RUN chmod 0755 /opt/krea2/setup_krea2_desirex.sh

# Keep RunPod's official entrypoint and insert the bootstrap immediately
# before the actual ComfyUI launch command. The previous package looked for
# a log-message string that is not present in this pinned image.
# Accept both the older background launch and newer foreground exec form,
# but fail closed unless exactly one main.py launch line is found.
RUN python3 - <<'PY'
from pathlib import Path
import re

path = Path('/start.sh')
source = path.read_text()
pattern = re.compile(r'(?m)^[ \t]*(?:exec[ \t]+)?python(?:3(?:\.12)?)?[ \t]+main\.py[^\n]*$')
matches = list(pattern.finditer(source))
if len(matches) != 1:
    raise SystemExit(
        'Build stopped safely: expected exactly one ComfyUI main.py launch '
        f'line in /start.sh; found {len(matches)}. No startup script was changed.'
    )

injection = r'''# ---- Krea2 / DesireX automatic bootstrap (injected by custom image) ----
if [[ "${KREA2_AUTO_SETUP:-1}" == "1" ]]; then
    echo "Running Krea2 / DesireX setup before ComfyUI starts..."
    /bin/bash /opt/krea2/setup_krea2_desirex.sh
else
    echo "KREA2_AUTO_SETUP=0: skipping Krea2 / DesireX setup."
fi
# ---- End Krea2 / DesireX automatic bootstrap ----

'''
start = matches[0].start()
path.write_text(source[:start] + injection + source[start:])
print('Patched /start.sh immediately before its unique ComfyUI main.py launch line.')
PY
