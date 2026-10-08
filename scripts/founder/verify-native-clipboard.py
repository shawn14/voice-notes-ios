#!/usr/bin/env python3
"""Read-only E2E check after ScreenshotTests/testFounderAgentBrief on seeded QA device."""
import html, json, re, sqlite3, subprocess, sys, uuid
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("Usage: verify-native-clipboard.py <QA-device-UUID> <actual-default.store-path>")
device, store = sys.argv[1:]
uuid.UUID(device)
store = Path(store).resolve()
assert device in str(store), "Database must belong to this disposable QA device"
packet = subprocess.run(["xcrun", "simctl", "pbpaste", device], check=True, capture_output=True, text=True).stdout
assert "## My request\nBuild a landing page for this project" in packet
assert "Project: EEON" in packet
matches = list(re.finditer(r"Note ID: ([0-9A-F-]{36}).*?<source-note>\n(.*?)\n</source-note>", packet, re.S))
assert len(matches) == 4, "Seeded flow should include primary and three EEON notes"
connection = sqlite3.connect(store.as_uri() + "?mode=ro", uri=True)
connection.row_factory = sqlite3.Row
try:
    rows = connection.execute("SELECT ZID,ZTITLE,ZTRANSCRIPT,ZCONTENT,ZENHANCEDNOTETEXT,ZINFERREDPROJECTNAME FROM ZNOTE").fetchall()
finally:
    connection.close()
notes = {str(uuid.UUID(bytes=row["ZID"])).upper(): dict(row) for row in rows}
ids = [match[1] for match in matches]
assert len(set(ids)) == 4
for match in matches:
    note = notes[match[1]]
    assert note["ZINFERREDPROJECTNAME"] == "EEON", "Unrelated project leaked into brief"
    original = note["ZTRANSCRIPT"] or note["ZCONTENT"]
    assert html.unescape(match[2]) == original, "Original source changed in clipboard"
primary = notes[ids[0]]
assert primary["ZTITLE"] == "Standup with Lena"
rewrite = re.search(r"AI rewrite.*?<note-rewrite>\n(.*?)\n</note-rewrite>", packet, re.S)
assert rewrite and html.unescape(rewrite[1]) == primary["ZENHANCEDNOTETEXT"]
print(json.dumps({"passed": True, "method": "live clipboard versus read-only SwiftData SQLite", "sources": ids, "project": "EEON", "originalAndRewriteSeparate": True, "scope": "seeded simulator; not recording, physical device or native authentication"}, indent=2))
