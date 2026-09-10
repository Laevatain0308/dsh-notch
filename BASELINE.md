# 2026-09-10 baseline

Snapshot of the existing native Notch and Host plugin, before robot idle experiments.

Verification on macOS:
- Host tests: 8 passed (tsx 4.22.4).
- Native motion probe: FAILURES=0.
- Native geometry probe: FAILURES=0; compact one/two/three lamp heights 44/72/100 pt.
- No live Host restart or model calls during this snapshot.

Existing manual acceptance covered first-click response, keyboard editing, long content, retry, multi-question navigation and queued questions. Automated tests do not replace live DSH acceptance after future installation.

The idle robot is a separate experiment and is not part of this baseline.
