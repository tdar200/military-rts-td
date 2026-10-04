"""UI-only campaign player. Reads public snapshots; sends viewport input only."""
import sys,time,json,collections
from ui_client import UI
u=UI(sys.argv[1]); log=open(u.path/'journey.jsonl','a',buffering=1)
def record(action):
 s=u.snapshot();log.write(json.dumps({'action':action,'tick':s['tick'],'money':s['money_bits']/65536,'era':s['era'],'research':s['research_count'],'winner':s['winner'],'counts':dict(collections.Counter(e['kind'] for e in s['entities'] if e['owner']==0))})+'\n')
def build(kind,x,y):
 u.key('Escape');u.button('BUILD');u.button(kind)
 ts=sorted(u.observe()['tiles'],key=lambda t:(t['tx']-x)**2+(t['ty']-y)**2)
 ts=[t for t in ts if t['free']]
 if ts:u.click(ts[0]['x'],ts[0]['y']);record('build '+kind)
 u.key('Escape')
def research():
 s=u.snapshot()
 if s['active_research_id']>=0:return
 order=[0,1,3,4,5,6,7,8,9,10,11,2]
 opts={r['id']:r for r in s['research_options']}
 for i in order:
  if opts[i]['available']:
   u.key('Y')
   try:u.button(opts[i]['name']);record('research '+opts[i]['name'])
   finally:u.key('Escape')
   break
def assault():
 u.key('Escape')
 # Wheel zoom and edge scrolling are ordinary viewport controls.
 vw,vh=u.observe()['viewport']
 for _ in range(13):u.click(vw/2,vh/2,button=5)
 time.sleep(.5)
 obs=u.observe();types=['Tank','AntiArmor','Infantry','Helicopter'];selected=False
 for kind in types:
  units=[e for e in obs['entities'] if e['owner']==0 and e['kind']==kind and e['free']]
  if units:
   e=units[0];u.click(e['x'],e['y'],double=True,shift=selected);selected=True
 if not selected:return
 u.key('1',ctrl=True);record('army selected '+str(len(u.observe()['selection'])))
 for _ in range(12):
  obs=u.observe();core=next((e for e in obs['entities'] if e['owner']==1 and e['kind']=='CommandCenter'),None)
  if not core:break
  if core['free']:
   u.key('A');u.click(core['x'],core['y'],button=2);record('attack core');u.capture('core-assault-'+str(u.snapshot()['tick']));break
  vw,vh=obs['viewport']
  x=vw-2 if core['x']>vw*.75 else (2 if core['x']<vw*.2 else vw/2)
  y=2 if core['y']<vh*.2 else (vh-2 if core['y']>vh*.75 else vh/2)
  u.send({'type':'motion','x':x,'y':y});time.sleep(.5);u.send({'type':'motion','x':vw/2,'y':vh/2});time.sleep(.25)
 u.key('Home');time.sleep(.4)

if any('DEPLOY FORCES' in b['text'].upper() for b in u.observe()['buttons']):
 u.button('DEPLOY FORCES');time.sleep(.5);u.capture('fresh-base')
 obs=u.observe();inf=[e for e in obs['entities'] if e['owner']==0 and e['kind']=='Infantry']
 u.click(inf[0]['x'],inf[0]['y']);u.click(inf[1]['x'],inf[1]['y'],shift=True)
 assert len(u.observe()['selection'])==2
 u.key('1',ctrl=True);u.key('Escape');u.key('1');assert len(u.observe()['selection'])==2
 u.click(inf[0]['x'],inf[0]['y'],double=True);assert len(u.observe()['selection'])==4
 u.key('Escape');before=u.observe()['build_mode'];u.key('Y');u.key('P');assert u.observe()['build_mode']==before;u.key('Escape')
 obs=u.observe();assert all((t['tx'],t['ty'])==(t['picked_x'],t['picked_y']) for t in obs['tiles'])
 record('controls passed: shift, double-click, group, modal, terrain picking')
 for kind,x,y in [('REACTOR',2,16),('REFINERY',3,15),('BARRACKS',3,12),('RESEARCH LAB',1,16),('GUN TURRET',6,11),('GUN TURRET',6,14),('REACTOR',1,18),('SUPPLY DEPOT',4,14),('FIELD WALL',7,11)]:build(kind,x,y)
end=time.monotonic()+1400
last_capture=0
last_attack=0
while time.monotonic()<end:
 try:
  s=u.snapshot()
  if s['winner']!=-1:u.capture('campaign-terminal');record('terminal');break
  es=[e for e in s['entities'] if e['owner']==0];counts=collections.Counter(e['kind'] for e in es);money=s['money_bits']/65536
  if money>180:
   if counts['ResearchLab']==0 and money>300:build('RESEARCH LAB',1,16)
   elif counts['Barracks']==0 and money>250:build('BARRACKS',3,12)
   elif s['power_generation']<s['power_demand']+40:build('REACTOR',1,17)
   elif counts['Refinery']<3:build('REFINERY',3,17)
   elif counts['GunTurret']<6:build('GUN TURRET',6,9+counts['GunTurret']*2)
   elif counts['SupplyDepot']<2:build('SUPPLY DEPOT',5,14)
   elif 'VehicleFactory' in s['unlocked_buildings'] and counts['VehicleFactory']<2 and money>320:build('VEHICLE FACTORY',4,18)
   elif 'Battery' in s['unlocked_buildings'] and counts['Battery']<1:build('BATTERY',4,17)
   elif 'Airfield' in s['unlocked_buildings'] and counts['Airfield']<1:build('AIRFIELD',5,18)
   elif s['research_count']>=7 and counts['SupplyDepot']<3:build('SUPPLY DEPOT',10+3*(counts['SupplyDepot']-2),14)
   elif 'AaTurret' in s['unlocked_buildings'] and counts['AaTurret']<2:build('AA BATTERY',3,13)
  research()
  s=u.snapshot();es=[e for e in s['entities'] if e['owner']==0];counts=collections.Counter(e['kind'] for e in es)
  if s['money_bits']/65536>300:
   if counts['Harvester']<3 and not any(e['kind']=='Refinery' and e['production_queued'] for e in es):
    u.button('UNITS');u.button('HARVESTER',soft=True);record('replacement harvester ordered')
   if counts['Infantry']<8:u.key('T')
   if 'AntiArmor' in s['unlocked_units'] and counts['AntiArmor']<5:u.key('V')
   if 'Tank' in s['unlocked_units'] and counts['Tank']<22:u.key('K')
   if 'Helicopter' in s['unlocked_units'] and counts['Helicopter']<4:u.key('H')
  if s['research_count']>=12 and counts['Helicopter']>=1 and s['tick']-last_attack>1800:
   last_attack=s['tick'];assault()
  if s['tick']-last_capture>1800:
   last_capture=s['tick'];record('checkpoint');u.capture('campaign-'+str(s['tick']))
  time.sleep(1)
 except Exception as e:log.write(json.dumps({'error':str(e)})+'\n');time.sleep(1)
