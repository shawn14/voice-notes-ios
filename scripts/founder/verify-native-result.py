#!/usr/bin/env python3
"""Compare actual QA SQLite after result tests to its real pre-save snapshot."""
import html,json,re,sqlite3,subprocess,sys,uuid
from pathlib import Path
if len(sys.argv) not in (4,5) or (len(sys.argv)==5 and sys.argv[4]!='--check-next-brief'):
    raise SystemExit('Usage: verify-native-result.py <QA-device-UUID> <before.json> <actual-agent-report.md> [--check-next-brief]')
device,before_path,report_path=sys.argv[1:4]
check_next=len(sys.argv)==5
uuid.UUID(device)
before=json.loads(Path(before_path).read_text())
store=Path(before['store']).resolve()
assert device in str(store), 'Store must belong to disposable QA device'
c=sqlite3.connect(store.as_uri()+'?mode=ro',uri=True);c.row_factory=sqlite3.Row
try:
    notes=c.execute('SELECT ZID,ZTITLE,ZCONTENT,ZTRANSCRIPT,ZENHANCEDNOTETEXT,ZPROJECTID,ZINFERREDPROJECTNAME,ZANNOTATION FROM ZNOTE').fetchall()
    actions=c.execute('SELECT * FROM ZEXTRACTEDACTION').fetchall()
    projects=c.execute('SELECT ZID,ZNAME FROM ZPROJECT').fetchall() if check_next else []
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
next_sources=[]
if check_next:
    assert source['ZPROJECTID'] is not None, 'Explicit project ID was not exercised'
    after_projects=rows(projects)
    assert ordered(after_projects)==ordered(before['projects']), 'Existing projects changed'
    same_name=[p for p in after_projects if p['ZNAME']=='EEON']
    assert len(same_name)==2 and len({p['ZID'] for p in same_name})==2, 'Need two real projects with same name/different IDs'
    assert source['ZPROJECTID'] in {p['ZID'] for p in same_name}
    packet=subprocess.run(['xcrun','simctl','pbpaste',device],check=True,capture_output=True,text=True).stdout
    matches=list(re.finditer(r'(?m)^Note ID: ([0-9A-F-]{36}).*?<source-note>\n(.*?)\n</source-note>',packet,re.S))
    next_sources=[uuid.UUID(m[1]).hex for m in matches]
    expected={n['ZID'] for n in after_notes if n['ZPROJECTID']==source['ZPROJECTID']}
    assert next_sources and next_sources[0]==source_id.hex, 'Next brief primary is not the source note'
    assert len(next_sources)==len(set(next_sources)) and set(next_sources)==expected, 'Explicit project context missing or crossed project boundary'
    assert result['ZID'] in next_sources, 'Returned result did not re-enter project context'
    for match in matches:
        n=by_id[uuid.UUID(match[1]).hex]
        assert html.unescape(match[2])==(n['ZTRANSCRIPT'] or n['ZCONTENT']), 'Next brief source text differs from actual database'
    wrong=next(n for n in after_notes if n['ZTITLE']=='Different EEON project')
    assert wrong['ZPROJECTID']!=source['ZPROJECTID'] and wrong['ZID'] not in next_sources
print(json.dumps({'passed':True,'method':'actual QA SQLite versus real pre-save snapshot','sourceID':str(source_id),'resultID':str(uuid.UUID(hex=result['ZID'])),'originalNotesUnchanged':len(before['notes']),'taskRowsUnchanged':len(before['actions']),'resultCount':1,'projectName':'EEON','explicitProjectIDExercised':source['ZPROJECTID'] is not None,'exactActualReportExcerpt':True,'nextBriefChecked':check_next,'nextBriefSourceIDs':next_sources,'scope':'seeded simulator excerpt; no full-report UI, physical recording, CloudKit sync, connector writes or production release'},indent=2))
