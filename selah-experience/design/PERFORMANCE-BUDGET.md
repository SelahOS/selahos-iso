# Performance budgets and release gates

These are targets, not measured shipping claims.

| Item | Budget |
| --- | --- |
| Added boot waiting | 0ms; no sleeps or minimum splash duration |
| Plymouth animation | ~3.2s, <=25 visual updates/s, then static |
| Decoded Plymouth PNG assets | <=2MiB |
| Installed package payload | <=5MiB (uncompressed) |
| SDDM idle CPU | <1% of one core after settling on reference machine |
| Network, video, continuous animation, added services | zero |

`tools/check.py` checks asset and source budgets. Package payload size is checked
during validation. Profile cold boot against the same baseline ISO, three runs
per variant; record boot-to-login time, CPU, peak RSS and power on hardware.
Any regression beyond run-to-run noise blocks default activation. Password,
question, error and slow-boot behavior outrank animation. No CPU/RSS claim is
made until native Plymouth and real SDDM measurements are recorded.
