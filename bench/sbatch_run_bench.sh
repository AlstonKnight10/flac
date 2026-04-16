#!/usr/bin/env bash
#SBATCH --job-name=flac-bench
#SBATCH --time=06:00:00
#SBATCH --output=flac-bench-%j.out
#SBATCH --error=flac-bench-%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

set -euo pipefail

cd "$HOME/flac"

RESULT_DIR="bench/results/job-${SLURM_JOB_ID}"
BUILD_DIR="bench/build/job-${SLURM_JOB_ID}"
TMP_DIR="bench/tmp_out/job-${SLURM_JOB_ID}"

chmod +x bench/run_bench.sh

./bench/run_bench.sh \
  --corpus-dir bench/corpus \
  --results-dir "${RESULT_DIR}" \
  --build-root "${BUILD_DIR}" \
  --out-dir "${TMP_DIR}"
