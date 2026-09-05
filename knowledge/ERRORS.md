# Errors

Log format: date, what happened, deterministic or infrastructure, conclusion (if any).

| Date | Error | Kind | Conclusion |
|---|---|---|---|
| 2026-09-03 | Raw SSDP multicast from a shell process: `OSError: [Errno 65] No route to host` | Deterministic | macOS Local Network privacy blocks multicast for non-entitled processes. Use Bonjour (`NWBrowser`) instead. |
