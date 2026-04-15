#!/usr/bin/env python3

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path


def median(values):
    values = sorted(values)
    n = len(values)
    if n == 0:
        return float("nan")
    mid = n // 2
    if n % 2 == 1:
        return values[mid]
    return (values[mid - 1] + values[mid]) / 2.0


def stdev_sample(values):
    n = len(values)
    if n < 2:
        return 0.0
    mean = sum(values) / n
    var = sum((x - mean) ** 2 for x in values) / (n - 1)
    return math.sqrt(var)


def load_rows(path):
    with path.open("r", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def summarize(rows):
    measured = [r for r in rows if r.get("phase") == "measure"]
    groups = defaultdict(list)
    for r in measured:
        key = (
            r["variant"],
            r["with_asm"],
            r["with_avx"],
            r["mask"],
            r["mask_label"],
            r["preset"],
            r["threads"],
            r["input_file"],
        )
        try:
            wall = float(r["wall_sec"])
        except ValueError:
            continue
        groups[key].append(wall)

    summary = []
    for key, walls in sorted(groups.items()):
        med = median(walls)
        sd = stdev_sample(walls)
        summary.append(
            {
                "variant": key[0],
                "with_asm": key[1],
                "with_avx": key[2],
                "mask": key[3],
                "mask_label": key[4],
                "preset": key[5],
                "threads": key[6],
                "input_file": key[7],
                "n": len(walls),
                "median_wall_sec": med,
                "stdev_wall_sec": sd,
            }
        )

    return summary


def add_speedups(summary):
    baseline = {}
    for row in summary:
        if row["mask"] == "127":
            baseline[(row["variant"], row["preset"], row["input_file"])] = row["median_wall_sec"]

    for row in summary:
        base = baseline.get((row["variant"], row["preset"], row["input_file"]))
        if base is None or row["median_wall_sec"] == 0:
            row["speedup_vs_mask127"] = float("nan")
        else:
            row["speedup_vs_mask127"] = base / row["median_wall_sec"]


def write_summary_csv(summary, path):
    fields = [
        "variant",
        "with_asm",
        "with_avx",
        "mask",
        "mask_label",
        "preset",
        "threads",
        "input_file",
        "n",
        "median_wall_sec",
        "stdev_wall_sec",
        "speedup_vs_mask127",
    ]
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in summary:
            out = dict(row)
            for key in ("median_wall_sec", "stdev_wall_sec", "speedup_vs_mask127"):
                val = out[key]
                out[key] = "" if math.isnan(val) else f"{val:.6f}"
            writer.writerow(out)


def write_report(summary, path):
    agg = defaultdict(list)
    for row in summary:
        agg[(row["variant"], row["preset"], row["mask"], row["mask_label"])].append(row)

    rows = []
    for (variant, preset, mask, mask_label), items in agg.items():
        med_time = median([i["median_wall_sec"] for i in items])
        med_speedup = median([i["speedup_vs_mask127"] for i in items if not math.isnan(i["speedup_vs_mask127"])])
        rows.append((variant, preset, mask, mask_label, med_time, med_speedup, len(items)))

    rows.sort(key=lambda x: (x[0], int(x[1]), int(x[2])))

    lines = []
    lines.append("# FLAC SIMD Benchmark Report")
    lines.append("")
    lines.append("This report uses measured runs only (`phase=measure`) and summarizes per-file medians.")
    lines.append("")
    lines.append("## Aggregate by variant, preset, and mask")
    lines.append("")
    lines.append("| Variant | Preset | Mask | Label | Median wall sec (across files) | Median speedup vs mask=127 | Cases |")
    lines.append("|---|---:|---:|---|---:|---:|---:|")
    for variant, preset, mask, mask_label, med_time, med_speedup, cases in rows:
        speed = "" if math.isnan(med_speedup) else f"{med_speedup:.3f}x"
        lines.append(f"| {variant} | {preset} | {mask} | {mask_label} | {med_time:.6f} | {speed} | {cases} |")

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- `mask=127` is baseline (all x86 instruction-set paths disabled via runtime mask).")
    lines.append("- Speedup is computed as `median(mask=127) / median(current mask)` per `(preset, input_file)`.")
    lines.append("- Build variants are still available in `summary.csv` for deeper slicing.")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Summarize FLAC SIMD benchmark CSV output")
    parser.add_argument("--input", required=True, help="Path to raw.csv")
    parser.add_argument("--output-dir", required=True, help="Directory for summary.csv and report.md")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_rows(input_path)
    summary = summarize(rows)
    add_speedups(summary)

    write_summary_csv(summary, output_dir / "summary.csv")
    write_report(summary, output_dir / "report.md")


if __name__ == "__main__":
    main()
