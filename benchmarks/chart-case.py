"""Draw a case's median logical reads per variant as an SVG bar chart.

Usage: python benchmarks/chart-case.py CASE_NAME TITLE

Reads benchmarks/results/CASE_NAME.csv (written by run-case.sh) and writes
assets/screenshots/CASE_NAME-logical-reads.svg. Medians are computed the same
way as in the Markdown results. Python 3 standard library only.
"""
import csv
import statistics
import sys
from html import escape
from pathlib import Path

root = Path(__file__).resolve().parent.parent
case_name, title = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader((root / "benchmarks/results" / f"{case_name}.csv").open(encoding="utf-8")))

variants = list(dict.fromkeys(r["variant"] for r in rows))
medians = {v: statistics.median(int(r["logical_reads"]) for r in rows if r["variant"] == v) for v in variants}

width, left, right, top, bar_h, gap = 760, 150, 90, 74, 30, 18
height = top + len(variants) * (bar_h + gap) + 28
plot_w = width - left - right
peak = max(medians.values())

out = [
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
    f'role="img" aria-labelledby="t d" font-family="Segoe UI, Helvetica, Arial, sans-serif">',
    f'<title id="t">{escape(title)}</title>',
    '<desc id="d">' + escape("; ".join(f"{v}: {medians[v]:,.0f} logical reads" for v in variants)) + "</desc>",
    "<style>.bg{fill:#fcfcfb}.ink{fill:#0b0b0b}.ink2{fill:#52514e}.bar{fill:#2a78d6}.grid{stroke:#e1e0d9}"
    "@media (prefers-color-scheme: dark){.bg{fill:#1a1a19}.ink{fill:#f0efec}.ink2{fill:#c3c2b7}"
    ".bar{fill:#3987e5}.grid{stroke:#2c2c2a}}</style>",
    f'<rect class="bg" width="{width}" height="{height}" rx="8"/>',
    f'<text class="ink" x="24" y="34" font-size="18" font-weight="600">{escape(title)}</text>',
    '<text class="ink2" x="24" y="56" font-size="13">Logical reads per execution, median of the measured runs. Lower is better.</text>',
    f'<line class="grid" x1="{left}" y1="{top - 8}" x2="{left}" y2="{height - 20}" stroke-width="1"/>',
]
for i, v in enumerate(variants):
    y = top + i * (bar_h + gap)
    w = plot_w * medians[v] / peak
    out.append(f'<text class="ink2" x="{left - 12}" y="{y + bar_h / 2 + 5}" font-size="14" text-anchor="end">{escape(v)}</text>')
    if w >= 1:
        out.append(f'<rect class="bar" x="{left}" y="{y}" width="{w:.1f}" height="{bar_h}" rx="4"/>')
    out.append(f'<text class="ink" x="{left + w + 8:.1f}" y="{y + bar_h / 2 + 5}" font-size="14" font-weight="600">'
               f'{medians[v]:,.0f}</text>')
out.append("</svg>")

target = root / "assets/screenshots" / f"{case_name}-logical-reads.svg"
target.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
print(target.relative_to(root).as_posix())
