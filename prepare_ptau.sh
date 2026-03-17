#!/bin/bash
# ============================================================================
# prepare_ptau.sh — Download Hermez Powers of Tau & prepare phase 2 files
# ============================================================================
#
# Downloads raw ceremony files from the Hermez/iden3 trusted setup and runs
# snarkjs "prepare phase2" (inverse FFT to Lagrange basis) so the output
# files are ready for Groth16 / PLONK / fflonk circuit-specific key generation.
#
# Output structure:
#   <output_dir>/
#   ├── phase1/   raw Hermez downloads (monomial basis, safe to delete after)
#   └── phase2/   prepared ptau files  (Lagrange basis, used by snarkjs setup)
#
# Usage:
#   ./prepare_ptau.sh [OPTIONS] <power|range> [<power|range> ...]
#
# Arguments (powers 8-28):
#   12          single power
#   8-26        inclusive range
#   8-20 23 26  mix of ranges and singles
#
# Options:
#   -o DIR      output directory (default: ./ptau)
#   -j N        parallel downloads, max 4 (default: 3)
#   -k          keep raw phase1 files after preparing (default: delete)
#   -h          show this help
#
# Examples:
#   ./prepare_ptau.sh 8-26                        # full range, output to ./ptau
#   ./prepare_ptau.sh -o /data/ptau 8 12 16 21 23 # specific powers, custom dir
#   ./prepare_ptau.sh -k -o /data/ptau 8-25        # keep raw files
# ============================================================================
set -e

# --- Defaults ---
OUTPUT_DIR="./ptau"
MAX_PARALLEL=3
KEEP_RAW=false

# --- Parse options ---
usage() {
  head -n 32 "$0" | tail -n 28 | sed 's/^# *//'
  exit "${1:-0}"
}

while getopts "o:j:kh" opt; do
  case "$opt" in
    o) OUTPUT_DIR="$OPTARG" ;;
    j) MAX_PARALLEL="$OPTARG"
       if [ "$MAX_PARALLEL" -gt 4 ]; then MAX_PARALLEL=4; fi
       if [ "$MAX_PARALLEL" -lt 1 ]; then MAX_PARALLEL=1; fi
       ;;
    k) KEEP_RAW=true ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))

# --- Parse powers ---
POWERS=()
for ARG in "$@"; do
  if [[ "$ARG" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    for P in $(seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"); do
      POWERS+=("$P")
    done
  elif [[ "$ARG" =~ ^[0-9]+$ ]]; then
    POWERS+=("$ARG")
  else
    echo "Error: invalid argument '$ARG'"
    usage 1
  fi
done

if [ ${#POWERS[@]} -eq 0 ]; then
  echo "Error: no powers specified"
  usage 1
fi

for P in "${POWERS[@]}"; do
  if [ "$P" -lt 8 ] || [ "$P" -gt 28 ]; then
    echo "Error: power $P out of range (must be 8-28)"
    exit 1
  fi
done

UNIQUE_POWERS=($(printf '%s\n' "${POWERS[@]}" | sort -n | uniq))

# --- Setup dirs ---
PHASE1_DIR="$OUTPUT_DIR/phase1"
PHASE2_DIR="$OUTPUT_DIR/phase2"
mkdir -p "$PHASE1_DIR" "$PHASE2_DIR"

echo "============================================"
echo "  Hermez Powers of Tau — phase 2 preparation"
echo "============================================"
echo "Powers:      ${UNIQUE_POWERS[*]}"
echo "Output:      $OUTPUT_DIR"
echo "Parallel DL: $MAX_PARALLEL"
echo "Keep raw:    $KEEP_RAW"
echo ""

# --- Heap size per power (MB) ---
# The prepare phase2 step does a large inverse FFT over 2^P elliptic curve
# points. Memory scales exponentially. These values give ~2x headroom.
heap_size_for_power() {
  local P=$1
  if   [ "$P" -le 12 ]; then echo 512      # 0.5 GB — powers 8-12
  elif [ "$P" -le 15 ]; then echo 1024     #   1 GB — powers 13-15
  elif [ "$P" -le 18 ]; then echo 4096     #   4 GB — powers 16-18
  elif [ "$P" -le 20 ]; then echo 8192     #   8 GB — powers 19-20
  elif [ "$P" -le 22 ]; then echo 16384    #  16 GB — powers 21-22
  elif [ "$P" -eq 23 ]; then echo 28672    #  28 GB — power 23
  elif [ "$P" -eq 24 ]; then echo 57344    #  56 GB — power 24
  elif [ "$P" -eq 25 ]; then echo 114688   # 112 GB — power 25
  elif [ "$P" -eq 26 ]; then echo 229376   # 224 GB — power 26
  elif [ "$P" -eq 27 ]; then echo 458752   # 448 GB — power 27
  elif [ "$P" -eq 28 ]; then echo 917504   # 896 GB — power 28
  fi
}

# --- Check requirements ---
MAX_POWER="${UNIQUE_POWERS[-1]}"
MAX_HEAP=$(heap_size_for_power "$MAX_POWER")
MAX_HEAP_GB=$(( MAX_HEAP / 1024 ))
SYSTEM_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1024}' || echo 0)
SYSTEM_RAM_GB=$(( SYSTEM_RAM_KB / 1024 / 1024 ))

echo "Largest power:     $MAX_POWER"
echo "Heap needed:       ${MAX_HEAP_GB} GB"
if [ "$SYSTEM_RAM_GB" -gt 0 ]; then
  echo "System RAM:        ${SYSTEM_RAM_GB} GB"
  if [ "$SYSTEM_RAM_GB" -lt "$MAX_HEAP_GB" ]; then
    echo ""
    echo "WARNING: System RAM (${SYSTEM_RAM_GB} GB) is less than the heap"
    echo "         needed for power $MAX_POWER (${MAX_HEAP_GB} GB)."
    echo "         The process will swap heavily and may fail or take days."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
  fi
fi
echo ""

if ! command -v npx &>/dev/null; then
  echo "Error: npx not found. Install Node.js >= 16."
  exit 1
fi

# --- Step 1: Download raw Hermez files ---
echo "=== Step 1/2: Downloading Hermez ceremony files ==="
DOWNLOAD_PIDS=()
DOWNLOAD_POWERS=()

for P in "${UNIQUE_POWERS[@]}"; do
  PAD=$(printf "%02d" "$P")
  PHASE2_FILE="$PHASE2_DIR/pot${P}_final.ptau"
  RAW_FILE="$PHASE1_DIR/powersOfTau28_hez_final_${PAD}.ptau"

  if [ -f "$PHASE2_FILE" ]; then
    echo "  power $P: phase2 already exists ✓"
    continue
  fi
  if [ -f "$RAW_FILE" ]; then
    echo "  power $P: raw file exists, will prepare"
    continue
  fi

  if [ "$P" -eq 28 ]; then
    URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final.ptau"
  else
    URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_${PAD}.ptau"
  fi

  echo "  power $P: downloading from $URL"
  curl -L --progress-bar -o "$RAW_FILE" "$URL" &
  DOWNLOAD_PIDS+=($!)
  DOWNLOAD_POWERS+=("$P")

  if [ ${#DOWNLOAD_PIDS[@]} -ge "$MAX_PARALLEL" ]; then
    wait "${DOWNLOAD_PIDS[0]}" || { echo "Error: download failed for power ${DOWNLOAD_POWERS[0]}"; exit 1; }
    DOWNLOAD_PIDS=("${DOWNLOAD_PIDS[@]:1}")
    DOWNLOAD_POWERS=("${DOWNLOAD_POWERS[@]:1}")
  fi
done

for i in "${!DOWNLOAD_PIDS[@]}"; do
  wait "${DOWNLOAD_PIDS[$i]}" || { echo "Error: download failed for power ${DOWNLOAD_POWERS[$i]}"; exit 1; }
done
echo ""

# --- Step 2: Prepare phase 2 (sequential — CPU & memory heavy) ---
echo "=== Step 2/2: Preparing phase 2 (inverse FFT → Lagrange basis) ==="
for P in "${UNIQUE_POWERS[@]}"; do
  PAD=$(printf "%02d" "$P")
  PHASE2_FILE="$PHASE2_DIR/pot${P}_final.ptau"
  RAW_FILE="$PHASE1_DIR/powersOfTau28_hez_final_${PAD}.ptau"

  if [ -f "$PHASE2_FILE" ]; then
    continue
  fi
  if [ ! -f "$RAW_FILE" ]; then
    echo "  power $P: raw file missing, skipping"
    continue
  fi

  HEAP=$(heap_size_for_power "$P")
  HEAP_GB=$(( HEAP / 1024 ))
  echo "  power $P: preparing phase 2 (heap: ${HEAP_GB} GB)..."
  START_TIME=$(date +%s)
  NODE_OPTIONS="--max-old-space-size=$HEAP" npx snarkjs powersoftau prepare phase2 "$RAW_FILE" "$PHASE2_FILE" -v
  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "  power $P: done in ${ELAPSED}s"

  if [ "$KEEP_RAW" = false ]; then
    rm -f "$RAW_FILE"
    echo "  power $P: removed raw file"
  fi
  echo ""
done

# --- Summary ---
echo "============================================"
echo "  Summary"
echo "============================================"
echo ""
echo "Phase 1 (raw Hermez):"
if ls "$PHASE1_DIR"/*.ptau &>/dev/null; then
  ls -lh "$PHASE1_DIR"/*.ptau
else
  echo "  (empty — raw files cleaned up)"
fi
echo ""
echo "Phase 2 (ready for snarkjs setup):"
if ls "$PHASE2_DIR"/*.ptau &>/dev/null; then
  ls -lh "$PHASE2_DIR"/*.ptau
else
  echo "  (none)"
fi
echo ""
echo "To use with snarkjs:"
echo "  npx snarkjs groth16 setup circuit.r1cs $PHASE2_DIR/pot<N>_final.ptau key.zkey"
echo "  npx snarkjs plonk setup  circuit.r1cs $PHASE2_DIR/pot<N>_final.ptau key.zkey"
