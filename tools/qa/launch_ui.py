"""Start an isolated rendered client and authoritative bridge; print owned PIDs."""
import subprocess,pathlib,json,os,sys,time,shutil
root=pathlib.Path(__file__).resolve().parents[2]
q=pathlib.Path(sys.argv[1]);q.mkdir(parents=True,exist_ok=True)
for name in ['action.json','observation.json']:
 (q/name).unlink(missing_ok=True)
env=os.environ.copy();children=[]
if '--software' not in sys.argv and shutil.which('nvidia-smi') and subprocess.run(['nvidia-smi','-L'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
 env.update(__NV_PRIME_RENDER_OFFLOAD='1',__GLX_VENDOR_LIBRARY_NAME='nvidia')
if '--software' in sys.argv:
 display=':93'
 x=subprocess.Popen(['Xvfb',display,'-screen','0','3840x2160x24','-nolisten','tcp'],stdout=(q/'xvfb.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
 children.append(x.pid);env.update(DISPLAY=display,LIBGL_ALWAYS_SOFTWARE='1');time.sleep(.5)
a=subprocess.Popen([str(root/'target/release/godot-bridge'),str(q/'snapshot.json')],stdout=(q/'bridge.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
b=subprocess.Popen([str(root/'tools/godot/Godot_v4.7.2-stable_linux.x86_64'),'--path',str(root/'godot3d'),'--max-fps','60','--script',str(root/'tools/qa/ui_driver.gd'),'--','--runtime-dir='+str(q),'--qa-dir='+str(q)],env=env,stdout=(q/'godot.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
children += [a.pid,b.pid];(q/'pids.json').write_text(json.dumps(children));print(children)
