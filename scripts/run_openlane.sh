#!/usr/bin/env bash
# Run the full RTL->GDSII flow with OpenLane 2 and collect the key results.
#   pip install openlane          (needs Docker, or use the Nix install)
#   ./scripts/run_openlane.sh
set -euo pipefail
cd "$(dirname "$0")/../openlane"
mkdir -p src && cp ../rtl/*.v src/   # container can only read files inside this folder

openlane --dockerized config.json "$@"

RUN=$(ls -d runs/* | sort | tail -1)
echo "=== Run directory: $RUN"
echo "=== GDSII:"; ls -lh "$RUN"/final/gds/*.gds 2>/dev/null || true
echo "=== Signoff summary:"
cat "$RUN"/final/metrics.csv 2>/dev/null | head -5 || true
python3 - "$RUN" <<'PY'
import json, sys, pathlib
m = pathlib.Path(sys.argv[1]) / "final" / "metrics.json"
if m.exists():
    d = json.loads(m.read_text())
    keys = ["design__instance__area", "design__instance__count", "design__core__area",
            "design__instance__utilization", "timing__setup__ws", "timing__hold__ws",
            "timing__setup_vio__count", "timing__hold_vio__count", "power__total",
            "route__drc_errors", "design__lvs_error__count", "antenna__violating__nets",
            "magic__drc_error__count", "klayout__drc_error__count"]
    for k in keys:
        if k in d: print(f"{k:34s} {d[k]}")
PY
