#!/usr/bin/env python3
"""Capture the real seeded QA database before its first agent result is saved."""
import json,sqlite3,sys,time,uuid
from pathlib import Path
if len(sys.argv) not in (3,4) or (len(sys.argv)==4 and sys.argv[3]!='--require-explicit-project'):
    raise SystemExit('Usage: capture-native-result-baseline.py <fresh-QA-device-UUID> <output.json> [--require-explicit-project]')
device,output=sys.argv[1:3];uuid.UUID(device)
require_explicit=len(sys.argv)==4
root=Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Containers/Shared/AppGroup'
end=time.monotonic()+300
while time.monotonic()<end:
    for store in root.glob('*/Library/Application Support/default.store'):
        c=None
        try:
            c=sqlite3.connect(store.as_uri()+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
            notes=c.execute('SELECT ZID,ZTITLE,ZCONTENT,ZTRANSCRIPT,ZENHANCEDNOTETEXT,ZPROJECTID,ZINFERREDPROJECTNAME,ZANNOTATION FROM ZNOTE').fetchall()
            source=next((x for x in notes if x['ZTITLE']=='Standup with Lena'),None)
            explicit_ready=not require_explicit or (source is not None and source['ZPROJECTID'] is not None and any(x['ZTITLE']=='Different EEON project' for x in notes))
            if explicit_ready and len(notes)>=11 and source is not None and not any((x['ZANNOTATION'] or '').startswith('Agent-reported result\n') for x in notes):
                actions=c.execute('SELECT * FROM ZEXTRACTEDACTION').fetchall()
                def rows(xs):return [{k:(v.hex() if isinstance(v,bytes) else v) for k,v in dict(x).items()} for x in xs]
                projects=c.execute('SELECT ZID,ZNAME FROM ZPROJECT').fetchall()
                Path(output).write_text(json.dumps({'store':str(store),'notes':rows(notes),'actions':rows(actions),'projects':rows(projects)},indent=2))
                print(f'Captured pre-save baseline: {len(notes)} notes, {len(actions)} actions')
                raise SystemExit(0)
        except sqlite3.Error:pass
        finally:
            if c:c.close()
    time.sleep(2)
raise SystemExit('No pre-save baseline captured; do not substitute a post-save snapshot')
