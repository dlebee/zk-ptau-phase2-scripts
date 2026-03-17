# zk-phase2-ptau-scripts

Standalone script to download [Hermez Powers of Tau](https://blog.hermez.io/hermez-cryptographic-setup/) ceremony files and prepare them for phase 2 use with [snarkjs](https://github.com/iden3/snarkjs).

The prepared files work with **Groth16**, **PLONK**, and **fflonk** proving systems.

## Why?

The snarkjs `powersoftau prepare phase2` step converts the raw ceremony output (monomial basis) into Lagrange basis via a large inverse FFT. For high powers (21+), this takes **hours** in JavaScript. By running it once on a server and keeping the output, you never wait again.

## Prerequisites

- **Node.js** >= 16
- **snarkjs** (installed automatically via npx, or `npm install -g snarkjs`)
- **curl**
- Enough disk space and RAM (see tables below)

## Usage

```bash
chmod +x prepare_ptau.sh

# Full range — every Hermez power from 8 to 26
./prepare_ptau.sh 8-26

# Just the common range (covers most circuits)
./prepare_ptau.sh 14-23

# Specific powers only
./prepare_ptau.sh 8 12 16 21 23

# Custom output directory
./prepare_ptau.sh -o /data/ptau 8-25

# Keep raw Hermez files (default: deleted after preparation)
./prepare_ptau.sh -k 8-26

# Limit parallel downloads (default: 3, max: 4)
./prepare_ptau.sh -j 2 8-26
```

## Output Structure

```
ptau/                        (or custom -o path)
├── phase1/                  raw Hermez ceremony files (deleted by default)
│   ├── powersOfTau28_hez_final_14.ptau
│   └── ...
└── phase2/                  prepared files (keep these!)
    ├── pot14_final.ptau
    ├── pot15_final.ptau
    └── ...
```

## Using the Prepared Files

The `phase2/*.ptau` files are drop-in replacements wherever snarkjs expects a ptau file:

```bash
# Groth16
npx snarkjs groth16 setup circuit.r1cs ptau/phase2/pot21_final.ptau circuit_0000.zkey

# PLONK (no phase 2 ceremony needed — just this one command)
npx snarkjs plonk setup circuit.r1cs ptau/phase2/pot23_final.ptau circuit_final.zkey

# fflonk
npx snarkjs fflonk setup circuit.r1cs ptau/phase2/pot24_final.ptau circuit_final.zkey
```

To integrate with an existing project, either:
1. **Symlink**: `ln -s /data/ptau/phase2/pot21_final.ptau ./circuit/build/pot21_final.ptau`
2. **Copy**: `cp /data/ptau/phase2/pot21_final.ptau ./circuit/build/`
3. **Point your build script** at the phase2 directory directly

## File Sizes

| Power | Raw download | Prepared file | Node.js heap | Typical use case |
|-------|-------------|---------------|-------------|-----------------|
| 8     | ~1 KB       | ~2 KB         | 0.5 GB      | 128 constraints     |
| 9     | ~2 KB       | ~4 KB         | 0.5 GB      | 256 constraints     |
| 10    | ~4 KB       | ~8 KB         | 0.5 GB      | 512 constraints     |
| 11    | ~8 KB       | ~16 KB        | 0.5 GB      | 1k constraints      |
| 12    | ~64 KB      | ~128 KB       | 0.5 GB      | 2k constraints      |
| 13    | ~256 KB     | ~512 KB       | 1 GB        | 4k constraints      |
| 14    | ~16 MB      | ~32 MB        | 1 GB        | 8k constraints      |
| 15    | ~32 MB      | ~64 MB        | 1 GB        | 16k constraints     |
| 16    | ~60 MB      | ~128 MB       | 4 GB        | small circuits      |
| 17    | ~128 MB     | ~256 MB       | 4 GB        |                     |
| 18    | ~250 MB     | ~512 MB       | 4 GB        |                     |
| 19    | ~512 MB     | ~1 GB         | 8 GB        |                     |
| 20    | ~1 GB       | ~2 GB         | 8 GB        |                     |
| 21    | ~2 GB       | ~4 GB         | 16 GB       | Groth16 large       |
| 22    | ~4 GB       | ~8 GB         | 16 GB       |                     |
| 23    | ~8 GB       | ~16 GB        | 28 GB       | PLONK large         |
| 24    | ~16 GB      | ~32 GB        | 56 GB       | fflonk              |
| 25    | ~32 GB      | ~64 GB        | 112 GB      |                     |
| 26    | ~64 GB      | ~128 GB       | 224 GB      | very large circuits |

### Totals for common ranges

| Range  | Total download | Total prepared (what you keep) | Peak disk during prep | Min system RAM |
|--------|---------------|-------------------------------|----------------------|---------------|
| 8-13   | < 1 MB        | < 1 MB                        | < 1 MB               | 1 GB          |
| 8-23   | ~16 GB        | ~31 GB                        | ~55 GB               | 32 GB         |
| 8-25   | ~64 GB        | ~128 GB                       | ~200 GB              | 128 GB        |
| 8-26   | ~128 GB       | ~256 GB                       | ~400 GB              | 256 GB        |

## Estimated Timing

Times are for snarkjs (JavaScript) on a modern server. Lower powers complete in seconds to minutes; the bulk of the time is spent on the largest power.

| Power | Prepare time (approx) |
|-------|----------------------|
| 8-13  | instant              |
| 14-18 | seconds each         |
| 19-20 | 1-5 min each         |
| 21    | ~15-30 min           |
| 22    | ~30-60 min           |
| 23    | ~1-3 hours           |
| 24    | ~3-8 hours           |
| 25    | ~8-20 hours          |
| 26    | ~20-40 hours         |

**Total for 8-25**: roughly 12-30 hours, dominated by powers 24 and 25.
**Total for 8-26**: roughly 30-70 hours, dominated by power 26.

## Server Recommendations

### For powers 8-23 (Groth16 + PLONK)

| Resource | Minimum  | Recommended |
|----------|----------|-------------|
| RAM      | 32 GB    | 32 GB       |
| Disk     | 60 GB    | 80 GB       |
| CPU      | 4 cores  | 8 cores     |

### For powers 8-25 (including fflonk at large N)

| Resource | Minimum  | Recommended |
|----------|----------|-------------|
| RAM      | 128 GB   | 150 GB      |
| Disk     | 200 GB   | 250 GB SSD  |
| CPU      | 8 cores  | 16 cores    |

### For powers 8-26 (near-maximum)

| Resource | Minimum  | Recommended |
|----------|----------|-------------|
| RAM      | 256 GB   | 300 GB      |
| Disk     | 400 GB   | 500 GB SSD  |
| CPU      | 8 cores  | 16 cores    |

**Tip:** Linode High Memory instances offer the best price-to-RAM ratio for this workload (e.g., High Memory 300 GB at $1.44/hr). CPU core count matters less than RAM — snarkjs is single-threaded.

CPU core count matters less than single-core clock speed — snarkjs runs the FFT in a single JavaScript thread. Pick the instance type with the fastest per-core performance.

## Security

These files contain **no secrets**. The preparation step is a deterministic computation (inverse FFT) over the publicly available Hermez ceremony output. The trust assumption rests entirely on the original [Hermez ceremony](https://blog.hermez.io/hermez-cryptographic-setup/) — as long as at least one of its participants destroyed their toxic waste, the ptau is secure.

You can verify any prepared file:

```bash
npx snarkjs powersoftau verify ptau/phase2/pot21_final.ptau
```
