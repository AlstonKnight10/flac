#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="${ROOT_DIR}/bench"
RESULTS_DIR="${BENCH_DIR}/results"
BUILD_ROOT="${BENCH_DIR}/build"
CORPUS_DIR="${BENCH_DIR}/corpus"

RUNS=10
WARMUPS=1
PRESETS="8"
THREADS_LIST="1 2 4 8 16 32"
TASKSET_CPU=""
OUT_DIR="${BENCH_DIR}/tmp_out"
USE_PERF=0
PERF_EVENTS="cycles,instructions,branches,branch-misses,cache-misses"
PYTHON_CMD=""
TIME_BIN=""
RUN_ANALYSIS=1

usage() {
  cat <<'EOF'
Usage: bench/run_bench.sh [options]

Options:
  --corpus-dir PATH      Input WAV directory (default: bench/corpus)
  --results-dir PATH     Output results directory (default: bench/results)
  --build-root PATH      Build root for variant builds (default: bench/build)
  --runs N               Measured repetitions per case (default: 10)
  --warmups N            Warmup runs per case (default: 1)
  --presets "LIST"       Space-separated FLAC presets, e.g. "5 8"
  --threads "LIST"       Space-separated thread counts for flac -j (default: "1 2 4 8 16 32")
  --taskset-cpu N        Pin benchmark process to CPU core N
  --use-perf             Collect perf stat counters if available
  --out-dir PATH         Output FLAC temp directory (default: bench/tmp_out)
  --python-cmd CMD       Python interpreter for analysis (default: auto-detect)
  --skip-analysis        Skip post-run CSV analysis/report generation
  -h, --help             Show this help

Environment variables:
  CC, CXX                C/C++ compiler overrides for cmake
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --corpus-dir)
        CORPUS_DIR="$2"
        shift 2
        ;;
      --results-dir)
        RESULTS_DIR="$2"
        shift 2
        ;;
      --build-root)
        BUILD_ROOT="$2"
        shift 2
        ;;
      --runs)
        RUNS="$2"
        shift 2
        ;;
      --warmups)
        WARMUPS="$2"
        shift 2
        ;;
      --presets)
        PRESETS="$2"
        shift 2
        ;;
      --threads)
        THREADS_LIST="$2"
        shift 2
        ;;
      --taskset-cpu)
        TASKSET_CPU="$2"
        shift 2
        ;;
      --use-perf)
        USE_PERF=1
        shift
        ;;
      --out-dir)
        OUT_DIR="$2"
        shift 2
        ;;
      --python-cmd)
        PYTHON_CMD="$2"
        shift 2
        ;;
      --skip-analysis)
        RUN_ANALYSIS=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

list_inputs() {
  shopt -s nullglob
  local files=("${CORPUS_DIR}"/*.wav "${CORPUS_DIR}"/*.WAV)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    die "No WAV files found in ${CORPUS_DIR}"
  fi
  printf '%s\n' "${files[@]}"
}

build_variant() {
  local name="$1"
  local with_asm="$2"
  local with_avx="$3"
  local build_dir="${BUILD_ROOT}/${name}"

  mkdir -p "${build_dir}"

  local cmake_args=(
    -S "${ROOT_DIR}"
    -B "${build_dir}"
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_PROGRAMS=ON
    -DBUILD_EXAMPLES=OFF
    -DBUILD_TESTING=OFF
    -DINSTALL_MANPAGES=OFF
    -DWITH_OGG=OFF
    -DWITH_ASM="${with_asm}"
    -DWITH_AVX="${with_avx}"
  )

  echo "==> Configuring ${name}"
  cmake "${cmake_args[@]}"
  echo "==> Building ${name}"
  cmake --build "${build_dir}" --target flacapp --parallel
}

write_headers() {
  mkdir -p "${RESULTS_DIR}"
  cat >"${RESULTS_DIR}/raw.csv" <<'EOF'
timestamp,hostname,variant,with_asm,with_avx,mask,mask_label,preset,threads,input_file,run_index,phase,wall_sec,user_sec,sys_sec,encoded_bytes,perf_cycles,perf_instructions,perf_branches,perf_branch_misses,perf_cache_misses,command
EOF
}

mask_label() {
  case "$1" in
    127) echo "all_disabled" ;;
    125) echo "sse2_only" ;;
    121) echo "sse2_ssse3" ;;
    113) echo "plus_sse41" ;;
    49)  echo "plus_sse42" ;;
    33)  echo "plus_avx2" ;;
    1)   echo "plus_fma" ;;
    *)   echo "mask_$1" ;;
  esac
}

safe_csv() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

run_one() {
  local flac_bin="$1"
  local variant="$2"
  local with_asm="$3"
  local with_avx="$4"
  local mask="$5"
  local preset="$6"
  local input="$7"
  local run_index="$8"
  local phase="$9"

  local input_base
  input_base="$(basename "${input}")"
  local input_stem
  input_stem="${input_base%.*}"
  if [[ -z "${input_stem}" ]]; then
    input_stem="${input_base}"
  fi
  local output
  output="${OUT_DIR}/${variant}/p${preset}/t${THREADS}/m${mask}/${input_stem}.flac"
  mkdir -p "$(dirname "${output}")"
  rm -f "${output}"

  local time_file perf_file
  time_file="$(mktemp)"
  perf_file="$(mktemp)"

  local cmd=("${flac_bin}" -f -s -"${preset}" -j "${THREADS}" --benchmark-disable-instruction-set "${mask}" -o "${output}" "${input}")
  local run_cmd=()
  if [[ -n "${TASKSET_CPU}" ]]; then
    run_cmd+=(taskset -c "${TASKSET_CPU}")
  fi

  local perf_cycles=""
  local perf_instructions=""
  local perf_branches=""
  local perf_branch_misses=""
  local perf_cache_misses=""

  if [[ "${USE_PERF}" -eq 1 ]]; then
    if [[ ${#run_cmd[@]} -gt 0 ]]; then
      "${TIME_BIN}" -f '%e,%U,%S' -o "${time_file}" perf stat -x, -e "${PERF_EVENTS}" -o "${perf_file}" "${run_cmd[@]}" "${cmd[@]}"
    else
      "${TIME_BIN}" -f '%e,%U,%S' -o "${time_file}" perf stat -x, -e "${PERF_EVENTS}" -o "${perf_file}" "${cmd[@]}"
    fi

    while IFS=, read -r value unit event rest; do
      case "${event}" in
        cycles) perf_cycles="${value}" ;;
        instructions) perf_instructions="${value}" ;;
        branches) perf_branches="${value}" ;;
        branch-misses) perf_branch_misses="${value}" ;;
        cache-misses) perf_cache_misses="${value}" ;;
      esac
    done <"${perf_file}"
  else
    if [[ ${#run_cmd[@]} -gt 0 ]]; then
      "${TIME_BIN}" -f '%e,%U,%S' -o "${time_file}" "${run_cmd[@]}" "${cmd[@]}"
    else
      "${TIME_BIN}" -f '%e,%U,%S' -o "${time_file}" "${cmd[@]}"
    fi
  fi

  local wall user sys
  IFS=, read -r wall user sys <"${time_file}"

  local encoded_bytes=""
  if [[ -f "${output}" ]]; then
    encoded_bytes="$(stat -c '%s' "${output}")"
  fi

  local now host label cmd_str
  now="$(date -Iseconds)"
  host="$(hostname)"
  label="$(mask_label "${mask}")"
  printf -v cmd_str '%q ' "${cmd[@]}"

  {
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,' \
      "${now}" "${host}" "${variant}" "${with_asm}" "${with_avx}" "${mask}" "${label}" "${preset}" "${THREADS}" "${input_base}" "${run_index}" "${phase}" "${wall}" "${user}" "${sys}" "${encoded_bytes}" "${perf_cycles}" "${perf_instructions}" "${perf_branches}" "${perf_branch_misses}" "${perf_cache_misses}"
    safe_csv "${cmd_str}"
    printf '\n'
  } >>"${RESULTS_DIR}/raw.csv"

  rm -f "${time_file}" "${perf_file}"
}

run_variant_matrix() {
  local variant="$1"
  local with_asm="$2"
  local with_avx="$3"
  local flac_bin="${BUILD_ROOT}/${variant}/src/flac/flac"

  [[ -x "${flac_bin}" ]] || die "Missing flac binary for variant ${variant}: ${flac_bin}"

  local masks=(127 125 121 113 49 17 1)
  if [[ "${with_asm}" != "ON" ]]; then
    masks=(127)
  elif [[ "${with_avx}" != "ON" ]]; then
    masks=(127 125 121 113 49)
  fi

  local preset mask input run threads
  for preset in ${PRESETS}; do
    for threads in ${THREADS_LIST}; do
      THREADS="${threads}"
      for mask in "${masks[@]}"; do
        while IFS= read -r input; do
          for ((run = 1; run <= WARMUPS; run++)); do
            run_one "${flac_bin}" "${variant}" "${with_asm}" "${with_avx}" "${mask}" "${preset}" "${input}" "${run}" "warmup"
          done
          for ((run = 1; run <= RUNS; run++)); do
            run_one "${flac_bin}" "${variant}" "${with_asm}" "${with_avx}" "${mask}" "${preset}" "${input}" "${run}" "measure"
          done
        done < <(list_inputs)
      done
    done
  done
}

main() {
  parse_args "$@"

  have_cmd cmake || die "cmake not found"
  if TIME_BIN="$(type -P gtime)" && [[ -n "${TIME_BIN}" ]]; then
    :
  elif TIME_BIN="$(type -P time)" && [[ -n "${TIME_BIN}" ]]; then
    :
  else
    die "GNU time not found (checked gtime/time in PATH)"
  fi
  if [[ -n "${TASKSET_CPU}" ]]; then
    have_cmd taskset || die "taskset requested but not found"
  fi
  if [[ "${USE_PERF}" -eq 1 ]]; then
    have_cmd perf || die "--use-perf requested but perf not found"
  fi

  if [[ "${RUN_ANALYSIS}" -eq 1 ]]; then
    if [[ -n "${PYTHON_CMD}" ]]; then
      have_cmd "${PYTHON_CMD}" || die "Configured python command not found: ${PYTHON_CMD}"
    elif have_cmd python3; then
      PYTHON_CMD="python3"
    elif have_cmd python; then
      PYTHON_CMD="python"
    else
      echo "WARNING: Neither python3 nor python found; disabling analysis" >&2
      RUN_ANALYSIS=0
    fi
  fi

  mkdir -p "${RESULTS_DIR}" "${BUILD_ROOT}" "${OUT_DIR}"
  list_inputs >/dev/null

  write_headers

  build_variant "noasm" "OFF" "OFF"
  build_variant "asm_noavx" "ON" "OFF"
  build_variant "full" "ON" "ON"

  run_variant_matrix "noasm" "OFF" "OFF"
  run_variant_matrix "asm_noavx" "ON" "OFF"
  run_variant_matrix "full" "ON" "ON"

  if [[ "${RUN_ANALYSIS}" -eq 1 ]]; then
    "${PYTHON_CMD}" "${BENCH_DIR}/analyze.py" --input "${RESULTS_DIR}/raw.csv" --output-dir "${RESULTS_DIR}"
  else
    echo "Skipping analysis; raw data written to ${RESULTS_DIR}/raw.csv"
  fi

  echo "Benchmark complete. Results in ${RESULTS_DIR}"
}

main "$@"
