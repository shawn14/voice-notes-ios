#!/usr/bin/env python3
"""Drive the real simulator UI and verify deletion in its real persistent store.
Build the UITests scheme first. Only the DEBUG screenshot fixture is accepted.
"""
import argparse, json, plistlib, sqlite3, subprocess, time
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--device', required=True)
p.add_argument('--confirm-disposable-simulator', action='store_true', required=True, help='This simulator holds only disposable fixture data')
p.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
p.add_argument('--derived-data', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)

def run(*cmd):
    return subprocess.check_output(cmd, text=True).strip()

def sim(*cmd):
    return run('xcrun', 'simctl', *cmd)

available = json.loads(sim('list', 'devices', 'available', '--json'))
assert any(d['udid'] == a.device and d['state'] == 'Booted' for ds in available['devices'].values() for d in ds), 'A booted simulator is required'
bundle = 'voice.notes.voice-notes'
data = Path(sim('get_app_container', a.device, bundle, 'data'))
initial_preferences = data / 'Library/Preferences' / (bundle + '.plist')
if initial_preferences.exists():
    with initial_preferences.open('rb') as f:
        assert plistlib.load(f).get('appleUserID') in (None, '', 'debug-user'), 'Refusing to overwrite a real app identity'
def terminate_fixture():
    result = subprocess.run(['xcrun', 'simctl', 'terminate', a.device, bundle], text=True, capture_output=True)
    if result.returncode and 'found nothing to terminate' not in result.stderr:
        raise RuntimeError(result.stderr)

terminate_fixture()
sim('launch', a.device, bundle, '-UITestMode', '-SkipOnboarding', '-SeedScreenshotData')
time.sleep(5)

def prefs():
    data = Path(sim('get_app_container', a.device, bundle, 'data'))
    with (data / 'Library/Preferences' / (bundle + '.plist')).open('rb') as f:
        return plistlib.load(f)

def rows():
    group = Path(sim('get_app_container', a.device, bundle, 'group.com.eeon.voicenotes'))
    store = group / 'Library/Application Support/default.store'
    db = sqlite3.connect(store.as_uri() + '?mode=ro', uri=True)
    tables = [r[0] for r in db.execute("select name from sqlite_master where type='table' and name like 'Z%' and name not like 'Z\_%' escape '\\'")]
    result = {}
    for table in tables:
        columns = {r[1] for r in db.execute('pragma table_info("' + table + '")')}
        if {'Z_PK', 'Z_ENT'} <= columns:
            result[table] = [r[0] for r in db.execute('select Z_PK from "' + table + '"')]
    db.close()
    return result

deadline = time.monotonic() + 45
while prefs().get('appleUserID') != 'debug-user' and time.monotonic() < deadline:
    time.sleep(1)  # CFPreferences may flush asynchronously after debug sign-in.
assert prefs().get('appleUserID') == 'debug-user', 'Refusing to drive deletion for anything except DEBUG fixture identity'
before = rows()
assert len(before.get('ZNOTE', [])) >= 5 and len(before.get('ZKNOWLEDGEARTICLE', [])) >= 1, 'Fixture must contain notes AND associated data'
(a.output / 'before.json').write_text(json.dumps(before, indent=2))
cmd = ['xcodebuild', '-scheme', 'voice notes UITests', '-project', str(a.source / 'voice notes.xcodeproj'), '-destination', 'id=' + a.device, '-derivedDataPath', str(a.derived_data), '-parallel-testing-enabled', 'NO', '-only-testing:voice notes UITests/ScreenshotTests/testAccountDeletionConfirmation', '-resultBundlePath', str(a.output / 'test.xcresult'), 'test-without-building']
with (a.output / 'test.log').open('w') as log:
    subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
terminate_fixture()  # XCTest may already have closed the fixture app.
sim('launch', a.device, bundle, '-UITestMode')  # No seed and no forced onboarding completion.
time.sleep(5)
after = rows()
remaining = {t: sorted(set(ids) & set(after.get(t, []))) for t, ids in before.items()}
remaining = {t: ids for t, ids in remaining.items() if ids}
report = {'beforeCounts': {t: len(ids) for t, ids in before.items()}, 'afterCounts': {t: len(ids) for t, ids in after.items()}, 'remainingOriginalRows': remaining, 'signedOut': not prefs().get('appleUserID')}
(a.output / 'report.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
assert report['signedOut'] and not remaining, 'Deletion must remove EVERY original model row and persist sign-out across relaunch'
print('PASS: real iPad UI confirmation/cancel/delete and persistent associated-data deletion')
