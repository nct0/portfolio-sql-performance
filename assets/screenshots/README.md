# Screenshots

Sanitized screenshots used by the README and the portfolio drafts.

Before adding an image, check that it shows only synthetic data and no usernames, email addresses, avatars, machine names, file paths, browser tabs, bookmarks or taskbar. Strip metadata, then name the file `<topic>-<before|after>.png`.

Charts are generated, never drawn by hand: `python benchmarks/chart-case.py <case> "<title>"` reads `benchmarks/results/<case>.csv` and writes `<case>-logical-reads.svg` here (Python 3 standard library only).

| File | Shows |
|---|---|
| `case-01-filtering-lookup-logical-reads.svg` | Case 1 median logical reads for all four variants |
| `case-01-plan-before.png` | Case 1 baseline actual plan in SSMS, with the SELECT tooltip showing the conversion and memory-grant warnings |
| `case-01-plan-after.png` | Case 1 optimized actual plan in SSMS |
