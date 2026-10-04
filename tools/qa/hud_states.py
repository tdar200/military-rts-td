"""Captures every live HUD state over the real 3D scene into <qa dir>/states/*.png (run after launch_ui.py).
Presentation only: it picks a deck tab, forces the assault layout and opens the debrief; it never sends a command."""
import sys,time,pathlib
from ui_client import UI
u=UI(sys.argv[1]);out=pathlib.Path(sys.argv[1])
if any('DEPLOY FORCES' in b['text'].upper() for b in u.observe()['buttons']):
 u.capture('state-title');u.button('DEPLOY FORCES');time.sleep(2.5)
u.capture('state-build')
obs=u.observe();inf=[e for e in obs['entities'] if e['owner']==0 and e['kind']=='Infantry' and e['free']]
u.click(inf[0]['x'],inf[0]['y'],double=True);time.sleep(.6);u.capture('state-orders-selection')
u.key('Y');time.sleep(.8);assert u.observe()['research_open'];u.capture('state-research')
u.key('Escape');assert not u.observe()['research_open']
u.ui_state(tab='orders',engage=True);time.sleep(.6);u.capture('state-assault')
u.ui_state(debrief=True);time.sleep(.6);u.capture('state-debrief')
print('captured',sorted(p.name for p in out.glob('state-*.png')))
