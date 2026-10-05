"""Start an isolated rendered client and authoritative bridge; print owned PIDs.
Usage: launch_ui.py <dir> [--software] [--scenario kestrel|survival] [--display :NN] [--driver world]. Godot always runs with the Dummy audio driver: QA never makes sound.
--display needs --software (it names the private Xvfb display); without --display a free number from :93 up is chosen, and a
named display that is already in use is an error, never shared. pids.json is written as each process starts, so a failed
launch leaves the PIDs for the caller to kill."""
import subprocess,pathlib,json,os,sys,time,shutil
root=pathlib.Path(__file__).resolve().parents[2]
q=pathlib.Path(sys.argv[1]);q.mkdir(parents=True,exist_ok=True)
for name in ['action.json','observation.json','pids.json']:
 (q/name).unlink(missing_ok=True)
scenario=sys.argv[sys.argv.index('--scenario')+1] if '--scenario' in sys.argv else None
display=sys.argv[sys.argv.index('--display')+1] if '--display' in sys.argv else None
driver='world_driver.gd' if '--driver' in sys.argv and sys.argv[sys.argv.index('--driver')+1]=='world' else 'ui_driver.gd'
if display and '--software' not in sys.argv:
 sys.exit('launch_ui: --display needs --software (it names the private Xvfb display)')
env=os.environ.copy();children=[];extra=[]
def save():(q/'pids.json').write_text(json.dumps(children))
def in_use(n):
 lock=pathlib.Path(f'/tmp/.X{n}-lock')
 if not lock.exists():return False
 try:os.kill(int(lock.read_text().strip()),0);return True
 except (ValueError,ProcessLookupError):return False
 except PermissionError:return True
def die(msg):
 for pid in children:
  try:os.kill(pid,15)
  except ProcessLookupError:pass
 sys.exit('launch_ui: '+msg)
if '--software' not in sys.argv and shutil.which('nvidia-smi') and subprocess.run(['nvidia-smi','-L'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
 env.update(__NV_PRIME_RENDER_OFFLOAD='1',__GLX_VENDOR_LIBRARY_NAME='nvidia')
if '--software' in sys.argv:
 if display:
  if in_use(int(display.lstrip(':'))):sys.exit(f'launch_ui: display {display} is already in use')
 else:
  n=93
  while in_use(n):n+=1
  display=f':{n}'
 x=subprocess.Popen(['Xvfb',display,'-screen','0','3840x2160x24','-nolisten','tcp'],stdout=(q/'xvfb.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
 children.append(x.pid);save()
 end=time.monotonic()+10
 while not pathlib.Path(f'/tmp/.X11-unix/X{display.lstrip(":")}').exists():
  if x.poll() is not None or time.monotonic()>end:die(f'Xvfb {display} did not start, see {q/"xvfb.log"}')
  time.sleep(.1)
 env.update(DISPLAY=display,LIBGL_ALWAYS_SOFTWARE='1');extra=['--qa-xvfb']  # the world driver warps the pointer only on Xvfb
try:
 a=subprocess.Popen([str(root/'target/release/godot-bridge'),*(['--scenario',scenario] if scenario else []),str(q/'snapshot.json')],stdout=(q/'bridge.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
 children.append(a.pid);save()
 b=subprocess.Popen([str(root/'tools/godot/Godot_v4.7.2-stable_linux.x86_64'),'--audio-driver','Dummy','--path',str(root/'godot3d'),'--max-fps','60','--script',str(root/'tools/qa'/driver),'--','--runtime-dir='+str(q),'--qa-dir='+str(q),*extra],env=env,stdout=(q/'godot.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
 children.append(b.pid);save()
except Exception as e:
 die(str(e))
print(children)
