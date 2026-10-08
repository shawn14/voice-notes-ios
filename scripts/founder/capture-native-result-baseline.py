#!/usr/bin/env python3
"""Capture the real seeded QA database before its first agent result is saved."""
import json,sqlite3,sys,time,uuid
from pathlib import Path
if len(sys.argv)!=3:
    raise SystemExit('Usage: capture-native-result-baseline.py <fresh-QA-device-UUID> <output.json>')
device,output=sys.argv[1:];uuid.UUID(device)
root=Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Containers/Shared/AppGroup'
end=time.monotonic()+300
while time.monotonic()<end:
    for store in root.glob('*/Library/Application Support/default.store'):
        c=None
        try:
            c=sqlite3.connect(store.as_uri()+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
            notes=c.execute('SELECT ZID,ZTITLE,ZCONTENT,ZTRANSCRIPT,ZENHANCEDNOTETEXT,ZPROJECTID,ZINFERREDPROJECTNAME,ZANNOTATION FROM ZNOTE').fetchall()
            if len(notes)>=11 and any(x['ZTITLE']=='Standup with Lena' for x in notes) and not any((x['ZANNOTATION'] or '').startswith('Agent-reported result\n') for x in notes):
                actions=c.execute('SELECT * FROM ZEXTRACTEDACTION').fetchall()
                def rows(xs):return [{k:(v.hex() if isinstance(v,bytes) else v) for k,v in dict(x).items()} for x in xs]
                Path(output).write_text(json.dumps({'store':str(store),'notes':rows(notes),'actions':rows(actions)},indent=2))
                print(f'Captured pre-save baseline: {len(notes)} notes, {len(actions)} actions')
                raise SystemExit(0)
        except sqlite3.Error:pass
        finally:
            if c:c.close()
    time.sleep(2)
raise SystemExit('No pre-save baseline captured; do not substitute a post-save snapshot')
