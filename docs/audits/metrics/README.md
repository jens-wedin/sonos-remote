# Audit metrics

`scripts/audit-metrics.py` collects the numbers below from the sources (static greps) and from two probe tests in `MetricsProbeTests` (dynamic). Run it with `--label <name>` to write `<name>.json` here and append a row to `history.md`; `--compare before after` prints a delta table. Directions: "lower" or "higher" is better; "info" is context only.

The metric ids and what they measure are defined in the script's `STATIC` and `DYNAMIC` tables; keep this file and the script in step when adding one. The baseline is `before.json` (main at the v0.2.0 docs commit); each fix task appends `task-N`; the closing run is `after.json`.
