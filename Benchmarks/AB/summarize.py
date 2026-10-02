from __future__ import annotations

import argparse
import json
import pathlib
import statistics
from collections import defaultdict


def median(values):
    values = [float(v) for v in values if v is not None]
    return round(statistics.median(values), 2) if values else None


def mean(values):
    values = [float(v) for v in values if v is not None]
    return round(statistics.mean(values), 2) if values else None


def metric(row, path):
    current = row
    for key in path.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("--json-out", default="ab-summary.json")
    parser.add_argument("--md-out", default="ab-summary.md")
    args = parser.parse_args()

    rows = []
    for line in pathlib.Path(args.report).read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))

    groups = defaultdict(list)
    for row in rows:
        groups[(row.get("mode"), row.get("scenario"))].append(row)

    fields = [
        "launchToRequestMs",
        "timings.buildMs",
        "timings.firstFrameAfterLoadMs",
        "timings.totalMs",
        "timings.pruneMs",
        "preScroll.avgMs",
        "preScroll.p95Ms",
        "preScroll.maxMs",
        "postScroll.avgMs",
        "postScroll.p95Ms",
        "postScroll.maxMs",
        "timer.p95Ms",
        "timer.maxMs",
        "longGaps",
        "baseline.nodes",
        "afterPrune.nodes",
        "baseline.mcp",
        "afterPrune.mcp",
    ]

    summary = {}

    for (mode, scenario), items in sorted(groups.items()):
        key = f"{mode}:{scenario}"
        summary[key] = {
            "runs": len(items),
            "median": {
                field: median(metric(row, field) for row in items)
                for field in fields
            },
            "mean": {
                field: mean(metric(row, field) for row in items)
                for field in fields
            },
        }

    comparisons = {}
    for scenario in ("raw", "pruned"):
        safari = summary.get(f"safari:{scenario}", {}).get("median", {})
        wk = summary.get(f"wk:{scenario}", {}).get("median", {})

        if not safari or not wk:
            continue

        comparisons[scenario] = {}
        for field in fields:
            s = safari.get(field)
            w = wk.get(field)
            if s in (None, 0) or w is None:
                continue
            comparisons[scenario][field] = {
                "safari": s,
                "wk": w,
                "wkVsSafariPct": round((w - s) / s * 100, 1),
            }

    payload = {
        "rows": len(rows),
        "groups": summary,
        "comparisons": comparisons,
    }

    pathlib.Path(args.json_out).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    md = [
        "# Safari vs WKWebView A/B",
        "",
        f"Reports: {len(rows)}",
        "",
        "| Scenario | Metric | Safari median | WK median | WK vs Safari |",
        "|---|---|---:|---:|---:|",
    ]

    focus = [
        "launchToRequestMs",
        "timings.totalMs",
        "preScroll.p95Ms",
        "preScroll.maxMs",
        "postScroll.p95Ms",
        "postScroll.maxMs",
        "timer.p95Ms",
        "timer.maxMs",
        "longGaps",
    ]

    for scenario, values in comparisons.items():
        for field in focus:
            row = values.get(field)
            if not row:
                continue
            md.append(
                f"| {scenario} | {field} | {row['safari']} | {row['wk']} | {row['wkVsSafariPct']}% |"
            )

    pathlib.Path(args.md_out).write_text(
        "\n".join(md) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
