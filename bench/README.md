# FLAC SIMD Benchmark Harness

This harness benchmarks how x86 instruction-set dispatch impacts end-to-end FLAC encoding performance in this fork.

It uses a hidden CLI hook added to `flac`:

- `--benchmark-disable-instruction-set=<mask>`

Mask bits map to `FLAC__stream_encoder_disable_instruction_set()`:

- `1` MMX
- `2` SSE2
- `4` SSSE3
- `8` SSE4.1
- `16` AVX2
- `32` FMA
- `64` SSE4.2

Value `127` disables all listed x86 paths.

## Directory layout

- `bench/corpus/` input `.wav` files (you provide these)
- `bench/build/` generated build dirs for benchmark variants
- `bench/results/raw.csv` per-run timing data
- `bench/results/summary.csv` per-case medians and speedups
- `bench/results/report.md` aggregate markdown report

## Build variants used

The runner builds three variants with CMake:

- `noasm`: `WITH_ASM=OFF`, `WITH_AVX=OFF`
- `asm_noavx`: `WITH_ASM=ON`, `WITH_AVX=OFF`
- `full`: `WITH_ASM=ON`, `WITH_AVX=ON`

## Runtime ISA mask matrix

For `full`:

- `127` all disabled
- `125` SSE2 only
- `121` SSE2 + SSSE3
- `113` + SSE4.1
- `49` + SSE4.2
- `33` + AVX2 (FMA disabled)
- `1` + FMA

For `asm_noavx`, AVX2/FMA masks are omitted.
For `noasm`, only `127` is used.

## Usage

1. Put test WAVs in `bench/corpus/`.
2. Run:

```bash
bash bench/run_bench.sh --taskset-cpu 2 --runs 10 --warmups 1 --presets "5 8"
```

Optional perf counters:

```bash
bash bench/run_bench.sh --taskset-cpu 2 --use-perf
```

If Python is in a non-standard command name or you only want raw CSV output:

```bash
bash bench/run_bench.sh --python-cmd python3.12
bash bench/run_bench.sh --skip-analysis
```

## Recommended measurement hygiene

- Use `-j 1` (default in script) to isolate SIMD effects.
- Pin to one core with `--taskset-cpu`.
- Set CPU governor to performance if possible.
- Avoid background load during runs.
- Keep corpus fixed across comparisons.

## Quick interpretation

- Use `summary.csv` for per-file per-preset comparisons.
- Use `report.md` for aggregate speedup trends by build variant and mask.
- Baseline speedup reference is `mask=127` within the same build variant.
