"""Process-level restart protocol regression, isolated from player campaigns."""
import json,pathlib,subprocess,tempfile,time
root=pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='earthfront-restart-') as name:
 q=pathlib.Path(name);p=subprocess.Popen([str(root/'target/release/godot-bridge'),str(q/'snapshot.json')],stdout=subprocess.DEVNULL)
 def state():
  try:return json.loads((q/'snapshot.json').read_text())
  except (OSError,ValueError):return None
 def until(test):
  end=time.monotonic()+10
  while time.monotonic()<end:
   s=state()
   if s and test(s):return s
   time.sleep(.03)
  raise AssertionError('bridge condition timed out')
 try:
  until(lambda s:s['tick']==0)
  (q/'start.flag').write_text('deploy');until(lambda s:s['tick']>=10)
  (q/'start.flag').write_text('duplicate deploy')
  (q/'restart.flag').write_text('restart')
  until(lambda s:s['tick']==0);time.sleep(.5)
  s=state();assert s['tick']==0 and s['surveying'] and s['winner']==-1 and s['research_count']==0
  (q/'start.flag').write_text('deploy');until(lambda s:s['tick']>=5)
  print('PASS: restart clears duplicate deploy, waits at briefing, and accepts fresh deploy')
 finally:p.terminate();p.wait(timeout=5)
