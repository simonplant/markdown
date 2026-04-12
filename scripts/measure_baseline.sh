#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_FILE="$REPO_ROOT/docs/baseline.json"
NUM_RUNS=5

usage() {
    echo "Usage: $0 --capture | --check"
    echo ""
    echo "  --capture   Run measurements and write docs/baseline.json"
    echo "  --check     Run measurements and compare against existing docs/baseline.json"
    echo "              Exits non-zero if any metric regresses >10% in the median."
    echo "              Does NOT overwrite docs/baseline.json."
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

MODE="$1"
if [[ "$MODE" != "--capture" && "$MODE" != "--check" ]]; then
    usage
fi

# Build measurement binary in release mode
echo "Building measurement binary (release)..." >&2
cargo build --bin measure --release --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1 >&2
MEASURE_BIN="$REPO_ROOT/target/release/measure"

if [[ ! -x "$MEASURE_BIN" ]]; then
    echo "ERROR: measure binary not found at $MEASURE_BIN" >&2
    exit 1
fi

# Collect machine metadata as JSON
collect_metadata() {
    python3 -c "
import json, subprocess, platform, socket, os

uname_output = subprocess.check_output(['uname', '-a'], text=True).strip()

os_version = ''
if os.path.isfile('/etc/os-release'):
    with open('/etc/os-release') as f:
        for line in f:
            if line.startswith('PRETTY_NAME='):
                os_version = line.split('=', 1)[1].strip().strip('\"')
                break
else:
    try:
        name = subprocess.check_output(['sw_vers', '-productName'], text=True).strip()
        ver = subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip()
        os_version = f'{name} {ver}'
    except Exception:
        os_version = platform.platform()

cpu_model = ''
if os.path.isfile('/proc/cpuinfo'):
    with open('/proc/cpuinfo') as f:
        for line in f:
            if line.startswith('model name'):
                cpu_model = line.split(':', 1)[1].strip()
                break
else:
    try:
        cpu_model = subprocess.check_output(
            ['sysctl', '-n', 'machdep.cpu.brand_string'], text=True
        ).strip()
    except Exception:
        cpu_model = 'unknown'

memory_total_mb = 0
try:
    out = subprocess.check_output(['free', '-m'], text=True)
    for line in out.splitlines():
        if line.startswith('Mem:'):
            memory_total_mb = int(line.split()[1])
            break
except Exception:
    try:
        mem_bytes = int(subprocess.check_output(
            ['sysctl', '-n', 'hw.memsize'], text=True
        ).strip())
        memory_total_mb = mem_bytes // 1024 // 1024
    except Exception:
        pass

print(json.dumps({
    'hostname': socket.gethostname(),
    'os_version': os_version,
    'uname': uname_output,
    'cpu_model': cpu_model,
    'memory_total_mb': memory_total_mb
}))
"
}

# Run N measurements, output JSON array to stdout
run_measurements() {
    local results=()
    for i in $(seq 1 "$NUM_RUNS"); do
        echo "  Run $i/$NUM_RUNS..." >&2
        local output
        output="$("$MEASURE_BIN")"
        results+=("$output")
    done

    # Build JSON array
    python3 -c "
import json, sys
runs = []
for line in sys.argv[1:]:
    runs.append(json.loads(line))
print(json.dumps(runs))
" "${results[@]}"
}

# ---- CAPTURE MODE ----
if [[ "$MODE" == "--capture" ]]; then
    echo "=== Capture mode: measuring baseline ===" >&2
    echo "Running $NUM_RUNS measurement passes..." >&2

    runs_json="$(run_measurements)"
    metadata_json="$(collect_metadata)"

    mkdir -p "$(dirname "$BASELINE_FILE")"

    python3 -c "
import json, sys, statistics

runs = json.loads(sys.argv[1])
metadata = json.loads(sys.argv[2])
baseline_file = sys.argv[3]
num_runs = int(sys.argv[4])

metrics_keys = ['cold_startup_ms', 'open_small_ms', 'open_10k_ms', 'keystroke_ms', 'save_ms', 'memory_mb']
medians = {}
for key in metrics_keys:
    values = [r[key] for r in runs]
    medians[key] = round(statistics.median(values), 4)

baseline = {
    'metrics': medians,
    'metadata': metadata,
    'measurement': {
        'num_runs': num_runs,
        'method': 'median',
        'regression_threshold': 1.10
    },
    'runs': runs
}

with open(baseline_file, 'w') as f:
    json.dump(baseline, f, indent=2)
    f.write('\n')

print('Baseline written to ' + baseline_file, file=sys.stderr)
print('Medians:', file=sys.stderr)
for key in metrics_keys:
    print(f'  {key}: {medians[key]}', file=sys.stderr)
" "$runs_json" "$metadata_json" "$BASELINE_FILE" "$NUM_RUNS"

    exit 0
fi

# ---- CHECK MODE ----
if [[ "$MODE" == "--check" ]]; then
    echo "=== Check mode: comparing against baseline ===" >&2

    if [[ ! -f "$BASELINE_FILE" ]]; then
        echo "ERROR: Baseline file not found at $BASELINE_FILE" >&2
        echo "Run '$0 --capture' first to establish a baseline." >&2
        exit 1
    fi

    echo "Reading committed baseline from $BASELINE_FILE..." >&2
    echo "Running $NUM_RUNS measurement passes..." >&2

    runs_json="$(run_measurements)"

    python3 -c "
import json, sys, statistics

baseline_file = sys.argv[1]
runs = json.loads(sys.argv[2])

with open(baseline_file) as f:
    baseline = json.load(f)

baseline_metrics = baseline['metrics']
metrics_keys = ['cold_startup_ms', 'open_small_ms', 'open_10k_ms', 'keystroke_ms', 'save_ms', 'memory_mb']

current = {}
for key in metrics_keys:
    values = [r[key] for r in runs]
    current[key] = round(statistics.median(values), 4)

threshold = 1.10
failed = False

print()
print('Regression check (threshold: 110% of baseline):')
print(f'{\"Metric\":<22s}  {\"Baseline\":>10s}  {\"Current\":>10s}  {\"Ratio\":>8s}  Status')
print('-' * 70)

for m in metrics_keys:
    base_val = baseline_metrics[m]
    curr_val = current[m]
    if base_val == 0:
        ratio_str = 'N/A'
        status = 'SKIP'
    else:
        ratio = curr_val / base_val
        ratio_str = f'{ratio:.2f}x'
        if ratio > threshold:
            status = 'FAIL'
            failed = True
        else:
            status = 'PASS'
    print(f'  {m:<20s}  {base_val:>10.4f}  {curr_val:>10.4f}  {ratio_str:>8s}  [{status}]')

print()
if failed:
    print('REGRESSION DETECTED: one or more metrics exceed 110% of baseline.')
    sys.exit(1)
else:
    print('All metrics within 10% regression threshold. PASS.')
    sys.exit(0)
" "$BASELINE_FILE" "$runs_json"

    exit $?
fi
