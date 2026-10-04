"""Drive viewport input through ui_driver.gd; never submit simulation commands."""
import json,time,pathlib
class UI:
    def __init__(self,path):
        self.path=pathlib.Path(path);self.seq=int(time.time()*1000)
    def observe(self):
        return json.loads((self.path/'observation.json').read_text())
    def snapshot(self):
        return json.loads((self.path/'snapshot.json').read_text())
    def send(self,*events,timeout=15):
        self.seq+=1
        p=self.path/'action.next';p.write_text(json.dumps({'id':self.seq,'events':events}));p.replace(self.path/'action.json')
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            try:
                obs=self.observe()
                if obs['ack']==self.seq:return obs
            except (OSError,ValueError):pass
            time.sleep(.08)
        raise TimeoutError((self.seq,events))
    def key(self,key,**kw):return self.send({'type':'key','key':key,**kw})
    def click(self,x,y,**kw):return self.send({'type':'click','x':x,'y':y,**kw})
    def button(self,text,soft=False):
        """Click the visible, enabled button whose text contains `text` (case-insensitive); the driver reports only the
        part of each button that is on screen, so the centre of the rectangle is always a point a player can click."""
        buttons=self.observe()['buttons']
        matches=[b for b in buttons if text.upper() in b['text'].upper() and not b['disabled']]
        if not matches:
            if soft or any(b['text'].upper()==text.upper() and b['disabled'] for b in buttons):return self.observe()
            raise ValueError('No enabled button '+text)
        matches.sort(key=lambda b: (b['text'].split('\n')[0].upper()!=text.upper(),len(b['text'])))
        b=matches[0]
        return self.click(b['x']+b['w']/2,b['y']+b['h']/2)
    def ui_state(self,**kw):return self.send({'type':'ui_state',**kw})
    def capture(self,name):return self.send({'type':'capture','name':name})
