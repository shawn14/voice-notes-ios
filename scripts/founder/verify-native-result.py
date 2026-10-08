#!/usr/bin/env python3
"""Compare actual QA SQLite after result tests to its real pre-save snapshot."""
import json,sqlite3,sys,uuid
from pathlib import Path
if len(sys.argv)!=4:
    raise SystemExit('Usage: verify-native-result.py <QA-device-UUID> <before.json> <actual-agent-report.md>')
device,before_path,report_path=sys.argv[1:]
uuid.UUID(device)
before=json.loads(Path(before_path).read_text())
store=Path(before['store']).resolve()
assert device in str(store), 'Store must belong to disposable QA device'
c=sqlite3.connect(store.as_uri()+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
try:
    notes=c.execute('SELECT ZID,ZTITLE,ZCONTENT,ZTRANSCRIPT,ZENHANCEDNOTETEXT,ZPROJECTID,ZINFERREDPROJECTNAME,ZANNOTATION FROM ZNOTE').fetchall()
    actions=c.execute('SELECT * FROM ZEXTRACTEDACTION').fetchall()
finally:c.close()
def rows(xs):return [{k:(v.hex() if isinstance(v,bytes) else v) for k,v in dict(x).items()} for x in xs]
after_notes=rows(notes);after_actions=rows(actions)
by_id={x['ZID']:x for x in after_notes}
for note in before['notes']:
    assert by_id[note['ZID']]==note, 'Pre-existing note changed or disappeared'
def ordered(xs):return sorted(xs,key=lambda x:json.dumps(x,sort_keys=True))
assert ordered(after_actions)==ordered(before['actions']), 'Task rows/status changed'
new=[x for x in after_notes if x['ZID'] not in {n['ZID'] for n in before['notes']}]
assert len(new)==1, 'Exactly one successful result; failed write must persist none'
result=new[0]
annotation=result['ZANNOTATION']
assert annotation.startswith('Agent-reported result\nSource note ID: ')
source_id=uuid.UUID(annotation.split('Source note ID: ')[1])
source=by_id[source_id.bytes.hex()]
assert source['ZTITLE']=='Standup with Lena'
assert result['ZPROJECTID']==source['ZPROJECTID']
assert result['ZINFERREDPROJECTNAME']==source['ZINFERREDPROJECTNAME']=='EEON'
report=Path(report_path).read_text()
a=report.index('## Reported Completion From Notes');b=report.index('## Actually Verified',a)
excerpt=report[a:b].strip()
assert result['ZCONTENT'].endswith(excerpt), 'Returned real report excerpt changed'
assert result['ZCONTENT'].startswith('Agent-reported result. Saving this report does not independently verify its claims or complete tasks.')
print(json.dumps({'passed':True,'method':'actual QA SQLite versus real pre-save snapshot','sourceID':str(source_id),'resultID':str(uuid.UUID(hex=result['ZID'])),'originalNotesUnchanged':len(before['notes']),'taskRowsUnchanged':len(before['actions']),'resultCount':1,'projectName':'EEON','explicitProjectIDExercised':source['ZPROJECTID'] is not None,'exactActualReportExcerpt':True,'scope':'seeded simulator excerpt; no full-report UI, physical recording, CloudKit sync, connector writes or production release'},indent=2))
