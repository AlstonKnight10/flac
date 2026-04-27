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
            key = (
                row["variant"],
                row["preset"],
                row["threads"],
                row["input_file"],
            )
            baseline[key] = row["median_wall_sec"]

    for row in summary:
        key = (
            row["variant"],
            row["preset"],
            row["threads"],
            row["input_file"],
        )

        base = baseline.get(key)

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


def pretty_input_name(filename):
    name = filename.lower()

    if "special_dj_mix" in name:
        return "Song"

    if "white_noise" in name:
        return "White Noise"

    if "silence" in name:
        return "Silence"

    stem = Path(filename).stem
    return stem.replace("_", " ").title()


def graph_mask_sort_key(label):
    graph_order = [
        "all_disabled",
        "sse2_only",
        "ssse3_only",
        "sse4_only",
        "sse42_only",
        "plus_sse41",
        "plus_sse42",
        "plus_avx2",
        "plus_fma",
        "avx2_only",
        "fma_only",
    ]

    if label in graph_order:
        return graph_order.index(label)

    return 999


def graph_input_sort_key(input_file):
    pretty = pretty_input_name(input_file)

    order = {
        "Song": 0,
        "White Noise": 1,
        "Silence": 2,
    }

    return order.get(pretty, 999)


def write_graph_equivalent_tables(summary, lines):
    variants = sorted(set(row["variant"] for row in summary))
    presets = sorted(set(row["preset"] for row in summary), key=lambda x: int(x))
    threads_list = sorted(set(row["threads"] for row in summary), key=lambda x: int(x))

    for variant in variants:
        for preset in presets:
            for threads in threads_list:
                rows_here = [
                    row
                    for row in summary
                    if row["variant"] == variant
                    and row["preset"] == preset
                    and row["threads"] == threads
                ]

                if not rows_here:
                    continue

                input_files = sorted(
                    set(row["input_file"] for row in rows_here),
                    key=graph_input_sort_key,
                )

                mask_labels = sorted(
                    set(row["mask_label"] for row in rows_here),
                    key=graph_mask_sort_key,
                )

                lookup = {
                    (row["mask_label"], row["input_file"]): row for row in rows_here
                }

                lines.append("")
                lines.append(
                    f"## Performance comparison: `{variant}`, preset `{preset}`, threads `{threads}`"
                )
                lines.append("")
                lines.append(
                    "This table represents the same information as the bar graph."
                )
                lines.append("Lower wall time is better.")
                lines.append("")

                headers = ["Mask Label"]
                headers += [
                    f"{pretty_input_name(input_file)} (s)" for input_file in input_files
                ]

                align = ["---"]
                align += ["---:"] * len(input_files)

                lines.append("| " + " | ".join(headers) + " |")
                lines.append("|" + "|".join(align) + "|")

                for mask_label in mask_labels:
                    row_values = [mask_label]

                    for input_file in input_files:
                        row = lookup.get((mask_label, input_file))

                        if row is None:
                            row_values.append("")
                        else:
                            row_values.append(f"{row['median_wall_sec']:.3f}")

                    lines.append("| " + " | ".join(row_values) + " |")

                lines.append("")
                lines.append("### Quick read")
                lines.append("")

                for input_file in input_files:
                    input_name = pretty_input_name(input_file)

                    input_rows = [
                        row for row in rows_here if row["input_file"] == input_file
                    ]

                    if not input_rows:
                        continue

                    fastest = min(input_rows, key=lambda row: row["median_wall_sec"])
                    slowest = max(input_rows, key=lambda row: row["median_wall_sec"])

                    lines.append(
                        f"- Fastest `{input_name}` result: `{fastest['mask_label']}` "
                        f"at `{fastest['median_wall_sec']:.3f}` seconds."
                    )
                    lines.append(
                        f"- Slowest `{input_name}` result: `{slowest['mask_label']}` "
                        f"at `{slowest['median_wall_sec']:.3f}` seconds."
                    )


def write_report(summary, path):
    agg = defaultdict(list)

    for row in summary:
        key = (
            row["variant"],
            row["preset"],
            row["threads"],
            row["mask"],
            row["mask_label"],
        )
        agg[key].append(row)

    rows = []

    for (variant, preset, threads, mask, mask_label), items in agg.items():
        med_time = median([i["median_wall_sec"] for i in items])

        speedups = [
            i["speedup_vs_mask127"]
            for i in items
            if not math.isnan(i["speedup_vs_mask127"])
        ]

        med_speedup = median(speedups)

        rows.append(
            (
                variant,
                preset,
                threads,
                mask,
                mask_label,
                med_time,
                med_speedup,
                len(items),
            )
        )

    rows.sort(key=lambda x: (x[0], int(x[1]), int(x[2]), int(x[3])))

    lines = []

    lines.append("# FLAC SIMD Benchmark Report")
    lines.append("")
    lines.append(
        "This report uses measured runs only (`phase=measure`) and summarizes per-file medians."
    )
    lines.append("")

    lines.append("## Aggregate by variant, preset, threads, and mask")
    lines.append("")
    lines.append(
        "| Variant | Preset | Threads | Mask | Label | Median wall sec across files | Median speedup vs mask=127 | Cases |"
    )
    lines.append("|---|---:|---:|---:|---|---:|---:|---:|")

    for (
        variant,
        preset,
        threads,
        mask,
        mask_label,
        med_time,
        med_speedup,
        cases,
    ) in rows:
        speed = "" if math.isnan(med_speedup) else f"{med_speedup:.3f}x"

        lines.append(
            f"| {variant} | {preset} | {threads} | {mask} | {mask_label} | "
            f"{med_time:.6f} | {speed} | {cases} |"
        )

    lines.append("")
    lines.append("# Graph-equivalent performance tables")
    lines.append("")
    lines.append(
        "These tables show the same information as the performance graphs, but in text form."
    )

    write_graph_equivalent_tables(summary, lines)

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append(
        "- `mask=127` is the baseline for each matching `(variant, preset, threads, input_file)` group."
    )
    lines.append("- Speedup is computed as `median(mask=127) / median(current mask)`.")
    lines.append(
        "- `summary.csv` contains the detailed per-file data for deeper analysis."
    )
    lines.append("- Lower wall time means better performance.")
    lines.append(
        "- The graph-equivalent tables use the same layout as the graphs: mask labels as rows and input files as columns."
    )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="Summarize FLAC SIMD benchmark CSV output"
    )

    parser.add_argument("--input", required=True, help="Path to raw.csv")
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory for summary.csv and report.md",
    )

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
