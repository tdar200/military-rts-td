import random, math
R=random.Random(11)
P='file:///home/tahseen-dar/Projects/military-rts-td/godot3d/assets/terrain/painterly/'
A='file:///home/tahseen-dar/Projects/military-rts-td/assets/'
def img(href,x,y,w,h=None,flip=False,extra=''):
    h=h or w
    t=f' transform="translate({x+w} {y}) scale(-1 1)"' if flip else f' x="{x}" y="{y}"'
    return f'<image href="{href}" width="{w}" height="{h}"{t} {extra}/>'
out=[]
o=out.append
def bank(t):
    # sample the bezier chain approx via straight polyline of control pts
    pts=[(520,-120),(640,100),(880,240),(1010,380),(1140,520),(1290,800),(1410,1100)]
    i=min(int(t*6),5); u=t*6-i
    x=pts[i][0]*(1-u)+pts[i+1][0]*u; y=pts[i][1]*(1-u)+pts[i+1][1]*u
    return x,y
o('''<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#0c2a40}svg{display:block}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3600" height="2400" viewBox="0 0 3600 2400">
<defs>
<pattern id="pV4" width="620" height="620" patternUnits="userSpaceOnUse"><image href="%scontinuous_ground_detail_v4.png" width="620" height="620"/></pattern>
<pattern id="pV4b" width="900" height="900" patternUnits="userSpaceOnUse" patternTransform="rotate(37)"><image href="%scontinuous_ground_detail_v4.png" width="900" height="900"/></pattern>
<pattern id="pRock" width="520" height="520" patternUnits="userSpaceOnUse"><image href="%shighland_v3.png" width="520" height="520"/></pattern>
<filter id="soft60" x="-30%%" y="-30%%" width="160%%" height="160%%"><feGaussianBlur stdDeviation="60"/></filter>
<filter id="soft30" x="-30%%" y="-30%%" width="160%%" height="160%%"><feGaussianBlur stdDeviation="30"/></filter>
<filter id="soft12" x="-30%%" y="-30%%" width="160%%" height="160%%"><feGaussianBlur stdDeviation="12"/></filter>
<filter id="soft6" x="-30%%" y="-30%%" width="160%%" height="160%%"><feGaussianBlur stdDeviation="6"/></filter>
<filter id="soft3" x="-30%%" y="-30%%" width="160%%" height="160%%"><feGaussianBlur stdDeviation="3"/></filter>
<filter id="wob"><feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="3" seed="7" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="38"/></filter>
<filter id="wobS"><feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="2" seed="3" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="14"/></filter>
<filter id="rockDesat"><feColorMatrix type="saturate" values="0.35"/><feComponentTransfer><feFuncR type="linear" slope=".82"/><feFuncG type="linear" slope=".82"/><feFuncB type="linear" slope=".86"/></feComponentTransfer></filter>
<filter id="purp"><feColorMatrix type="hueRotate" values="95"/></filter>
<filter id="noiseBig" x="0" y="0" width="100%%" height="100%%"><feTurbulence type="fractalNoise" baseFrequency="0.0019 0.0026" numOctaves="4" seed="21"/><feColorMatrix type="matrix" values="0 0 0 0 .5  0 0 0 0 .5  0 0 0 0 .5  1.6 0 0 0 -.3"/></filter>
<filter id="noiseMid" x="0" y="0" width="100%%" height="100%%"><feTurbulence type="fractalNoise" baseFrequency="0.0075" numOctaves="3" seed="5"/><feColorMatrix type="matrix" values="0 0 0 0 .5  0 0 0 0 .5  0 0 0 0 .5  1.4 0 0 0 -.2"/></filter>
<filter id="shadowSpr" x="-20%%" y="-20%%" width="140%%" height="150%%"><feDropShadow dx="6" dy="9" stdDeviation="5" flood-color="#0a0f06" flood-opacity=".5"/></filter>
<path id="landShape" d="M-200 -200 L3800 -200 L3800 560 C3500 560 3300 640 3000 640 C2700 640 2500 760 2250 860 C2000 960 1800 1010 1620 1080 C1500 1130 1420 1160 1330 1230 C1150 1380 1000 1500 760 1640 C520 1790 280 1900 -200 2150 Z"/>
<mask id="mLand"><rect width="3600" height="2400" fill="#000"/><use href="#landShape" fill="#fff" filter="url(#wobS)"/></mask>
<mask id="mMeadow"><rect width="3600" height="2400" fill="#000"/><g filter="url(#soft60)" fill="#fff"><ellipse cx="620" cy="520" rx="520" ry="330"/><ellipse cx="1500" cy="260" rx="380" ry="200"/><ellipse cx="520" cy="1250" rx="440" ry="260"/><ellipse cx="2000" cy="620" rx="260" ry="150"/></g></mask>
<mask id="mPlains"><rect width="3600" height="2400" fill="#000"/><g filter="url(#soft60)" fill="#fff"><ellipse cx="1950" cy="560" rx="560" ry="260"/><ellipse cx="2800" cy="520" rx="500" ry="170"/><ellipse cx="1600" cy="860" rx="260" ry="120"/><ellipse cx="1000" cy="1500" rx="210" ry="110"/></g></mask>
<mask id="mRock"><rect width="3600" height="2400" fill="#000"/><g filter="url(#soft30)" fill="#fff"><path d="M1700 -100 C2100 -60 2500 40 3000 0 L3400 -100 L3400 200 C3050 330 2550 350 2250 300 C1950 250 1750 220 1650 120 Z"/><path d="M260 1500 C380 1440 480 1480 520 1560 C440 1620 320 1620 260 1500 Z"/></g></mask>
<mask id="mRockCore"><rect width="3600" height="2400" fill="#000"/><g filter="url(#soft30)" fill="#fff"><path d="M2000 -100 C2300 -60 2700 20 3050 -20 L3300 -60 L3300 100 C3000 220 2650 230 2400 190 C2200 150 2050 120 1980 40 Z"/></g></mask>
<linearGradient id="gSea" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#15506f"/><stop offset=".5" stop-color="#0d3a58"/><stop offset="1" stop-color="#082a42"/></linearGradient>
<radialGradient id="gSun" cx=".30" cy=".20" r=".95"><stop offset="0" stop-color="#fff2c8" stop-opacity=".14"/><stop offset="1" stop-color="#000" stop-opacity=".22"/></radialGradient>
</defs>
''' % (P,P,P))

# SEA
o('<rect width="3600" height="2400" fill="url(#gSea)"/>')
o('<rect width="3600" height="2400" fill="#8fd0e8" filter="url(#noiseMid)" style="mix-blend-mode:soft-light" opacity=".55"/>')
o('<g opacity=".32" filter="url(#soft3)" stroke="#a8e6f4" fill="none" stroke-width="1.6" stroke-linecap="round">')
for k in range(46):
    x0=R.randint(1300,3500); y0=int(1050+ (x0-1300)*-.12 + R.randint(150,1250)*(1 if True else 1))
    y0=min(2380,max(1150,y0)); L=R.randint(30,110)
    o(f'<path d="M{x0} {y0} q{L/2} -6 {L} 0"/>')
o('</g>')
o('<use href="#landShape" fill="none" stroke="#3a9ab8" stroke-width="170" opacity=".5" filter="url(#soft30)"/>')
o('<use href="#landShape" fill="none" stroke="#86d6e2" stroke-width="70" opacity=".5" filter="url(#soft12)"/>')

# LAND
o('<g mask="url(#mLand)">')
o('<rect width="3600" height="2400" fill="url(#pV4)"/>')
o('<rect width="3600" height="2400" fill="url(#pV4b)" opacity=".5" style="mix-blend-mode:soft-light"/>')
# grass tint (everything), then region tints
o('<rect width="3600" height="2400" fill="#6b8a3a" style="mix-blend-mode:overlay" opacity=".5"/>')
o('<rect width="3600" height="2400" fill="#7d8a52" style="mix-blend-mode:multiply" opacity=".5"/>')
o('<rect width="3600" height="2400" fill="#a6a95a" mask="url(#mMeadow)" style="mix-blend-mode:overlay" opacity=".5"/>')
o('<g mask="url(#mPlains)"><rect width="3600" height="2400" fill="#b9955a" style="mix-blend-mode:overlay" opacity=".8"/><rect width="3600" height="2400" fill="#a88a55" style="mix-blend-mode:multiply" opacity=".4"/></g>')
o('<g mask="url(#mRock)"><rect width="3600" height="2400" fill="url(#pRock)" filter="url(#rockDesat)"/></g>')
o('<g mask="url(#mRockCore)"><rect width="3600" height="2400" fill="#fff" opacity=".10"/></g>')
o('<path d="M1980 120 C2200 190 2500 240 2800 210 C3000 190 3200 130 3300 60" fill="none" stroke="#10161b" stroke-width="30" opacity=".4" filter="url(#soft12)"/>')
o('<path d="M2000 20 C2300 60 2600 100 2900 70 C3100 50 3250 10 3300 -10" fill="none" stroke="#e9eef0" stroke-width="12" opacity=".22" filter="url(#soft6)"/>')
# large-scale colour breakup
o('<rect width="3600" height="2400" fill="#fff" filter="url(#noiseBig)" style="mix-blend-mode:overlay" opacity=".55"/>')
o('<rect width="3600" height="2400" fill="#fff" filter="url(#noiseMid)" style="mix-blend-mode:soft-light" opacity=".55"/>')
o('<rect width="3600" height="2400" fill="url(#gSun)"/>')
# dirt tracks with worn edges
for pth,wd in [("M740 470 C900 500 1060 540 1180 560",18),("M1240 560 C1500 580 1750 600 2050 640 C2250 660 2400 640 2550 600",18),("M520 700 C640 820 700 900 800 980",14)]:
    o(f'<path d="{pth}" fill="none" stroke="#3b2f1c" stroke-width="{wd+10}" stroke-linecap="round" opacity=".28" filter="url(#soft6)"/>')
    o(f'<path d="{pth}" fill="none" stroke="#9b8559" stroke-width="{wd}" stroke-linecap="round" opacity=".6" filter="url(#soft3)"/>')
    o(f'<path d="{pth}" fill="none" stroke="#6f5d3a" stroke-width="3" stroke-dasharray="5 9" opacity=".5" transform="translate(-4 -2)"/><path d="{pth}" fill="none" stroke="#6f5d3a" stroke-width="3" stroke-dasharray="5 9" opacity=".5" transform="translate(5 3)"/>')
o('</g>')

# SHORE
o('<g mask="url(#mLand)"><use href="#landShape" fill="none" stroke="#b9a373" stroke-width="40" opacity=".8" filter="url(#soft6)"/><use href="#landShape" fill="none" stroke="#6d5d3c" stroke-width="12" opacity=".35" transform="translate(-8 -6)" filter="url(#soft3)"/></g>')
o('<use href="#landShape" fill="none" stroke="#f4fbff" stroke-width="5" opacity=".55" filter="url(#wobS)"/><use href="#landShape" fill="none" stroke="#f4fbff" stroke-width="12" opacity=".18" filter="url(#soft6)"/>')

# RIVER
RP="M520 -120 C640 100 880 240 1010 380 C1140 520 1210 640 1290 800 C1340 900 1380 1000 1410 1100"
o(f'<g filter="url(#soft3)"><path d="{RP}" fill="none" stroke="#5c4c30" stroke-width="196" stroke-linecap="round" opacity=".35" filter="url(#wob)"/>')
o(f'<path d="{RP}" fill="none" stroke="#bda878" stroke-width="176" stroke-linecap="round" opacity=".9" filter="url(#wob)"/>')
o(f'<path d="{RP}" fill="none" stroke="#7d6c46" stroke-width="152" stroke-linecap="round" opacity=".55" filter="url(#wob)"/>')
o(f'<path d="{RP}" fill="none" stroke="#2b7a98" stroke-width="144" stroke-linecap="round" filter="url(#wob)"/>')
o(f'<path d="{RP}" fill="none" stroke="#1b5a7c" stroke-width="104" stroke-linecap="round" filter="url(#wob)"/>')
o(f'<path d="{RP}" fill="none" stroke="#0f3f5f" stroke-width="56" stroke-linecap="round" filter="url(#wob)" opacity=".9"/>')
# ripples
o('<g stroke="#cdf1f7" fill="none" stroke-linecap="round" opacity=".55">')
for k in range(120):
    t=R.random(); x,y=bank(t); x+=R.randint(-42,42); y+=R.randint(-42,42)
    if 1060<x<1250 and 460<y<640: continue
    L=R.randint(10,34); o(f'<path d="M{x:.0f} {y:.0f} q{L/2:.0f} {R.choice([-3,3])} {L} {R.randint(-3,3)}" stroke-width="{R.choice([1.2,1.8,2.4])}" opacity="{R.uniform(.25,.8):.2f}"/>')
o('</g>')
# ford
o('<ellipse cx="1150" cy="548" rx="72" ry="108" transform="rotate(-38 1150 548)" fill="#94d6dc" opacity=".28" filter="url(#soft6)"/>')
o('<g fill="#9aa5a8" opacity=".9">')
for k in range(16):
    a=R.random()*6.28; r=R.random()*60
    o(f'<ellipse cx="{1150+math.cos(a)*r*.7:.0f}" cy="{548+math.sin(a)*r:.0f}" rx="{R.randint(5,11)}" ry="{R.randint(3,6)}" fill="{R.choice(["#9aa5a8","#7d878b","#b5bec0"])}"/>')
o('</g></g>')
# river pebbles & reeds along the banks
o('<g>')
for k in range(150):
    t=R.random(); x,y=bank(t); side=R.choice([-1,1]); d=R.randint(74,98)
    nx=0.7*side; ny=-0.7*side
    px=x+nx*d+R.randint(-8,8); py=y+ny*d+R.randint(-8,8)
    if 1060<px<1250 and 460<py<640: continue
    c=R.choice(['#8b8478','#a39c8c','#6e695f','#b4ab97'])
    o(f'<ellipse cx="{px:.0f}" cy="{py:.0f}" rx="{R.randint(3,8)}" ry="{R.randint(2,5)}" fill="{c}" opacity=".85"/>')
for k in range(70):
    t=R.random(); x,y=bank(t); side=R.choice([-1,1]); d=R.randint(84,106)
    px=x+0.7*side*d; py=y-0.7*side*d
    if 1060<px<1250 and 460<py<640: continue
    for j in range(5):
        o(f'<path d="M{px+j*3:.0f} {py:.0f} q{R.randint(-4,4)} -{R.randint(10,20)} {R.randint(-6,6)} -{R.randint(18,30)}" stroke="{R.choice(["#4a6a2a","#5d7d32","#6f8d3a"])}" stroke-width="2.2" fill="none" stroke-linecap="round"/>')
o('</g>')

# island/spit
o('<ellipse cx="2300" cy="1250" rx="150" ry="52" fill="#b9a373" opacity=".9" filter="url(#wobS)"/><ellipse cx="2300" cy="1244" rx="118" ry="36" fill="#58803a" filter="url(#wobS)"/><ellipse cx="2300" cy="1244" rx="118" ry="36" fill="url(#pV4)" opacity=".5" style="mix-blend-mode:overlay"/>')

# ---------- baked contact shadows + pads under buildings (world coords from the boards) ----------
b=[('pp',150,310,170),('pp',110,450,160),('cc',360,300,250),('fnd',330,100,170),('fl',570,360,80),('ref',560,470,200),('bar',400,570,200),('lab',610,230,150),('gt',735,330,115),('gt',880,560,115),('aa',780,430,85),
   ('acap',2620,270,330),('apw',2950,250,150),('agt',2445,325,130),('agt',2425,535,130),('aaa',2810,560,120),('aat',2505,430,110),('awall',2360,430,110),('awall',2355,590,110),('awall',2360,300,110),
   ('gt',900,440,110),('gt',915,600,110),('wall',960,520,100),('wall',990,570,100)]
o('<g>')
for n,x,y,w in b:
    cx=x+w/2; cy=y+w*0.70; rx=w*0.52; ry=w*0.22
    big = w>=150
    if big:
        o(f'<ellipse cx="{cx:.0f}" cy="{cy+4:.0f}" rx="{rx*1.18:.0f}" ry="{ry*1.25:.0f}" fill="#8d7e5b" opacity=".32" filter="url(#soft12)"/>')
        o(f'<ellipse cx="{cx:.0f}" cy="{cy+4:.0f}" rx="{rx*1.0:.0f}" ry="{ry*1.0:.0f}" fill="#9a8b66" opacity=".28" filter="url(#soft6)"/>')
        o(f'<ellipse cx="{cx:.0f}" cy="{cy+4:.0f}" rx="{rx*1.1:.0f}" ry="{ry*1.1:.0f}" fill="url(#pV4)" opacity=".25" style="mix-blend-mode:multiply"/>')
o('</g>')

# ---------- forests: real game tree clusters ----------
TREE=P+'forest_cluster_v5.png'
trees=[]
def cluster(x,y,w,flip=None,filt=''):
    trees.append((y,x,w,R.random()<.5 if flip is None else flip,filt))
for (x0,y0,x1,y1,n,w0,w1) in [(300,780,740,1050,26,160,230),(60,150,300,300,7,120,160),(190,1240,470,1400,9,140,200)]:
    for k in range(n):
        cluster(R.randint(x0,x1),R.randint(y0,y1),R.randint(w0,w1))
for (x,y,w) in [(1720,320,150),(1790,350,130),(1900,860,150),(2320,420,140),(2390,450,120),(2100,760,150),(2640,780,150),(2700,760,130),(3050,500,150),(1380,1180,120),(260,1010,110),(1650,430,120),(1980,330,110)]:
    cluster(x,y,w,filt='dry')
# riverside willows
for k in range(18):
    t=R.random(); x,y=bank(t); side=R.choice([-1,1]); d=R.randint(112,150)
    px=x+.7*side*d; py=y-.7*side*d
    if 1000<px<1300 and 380<py<700: continue
    cluster(int(px),int(py),R.randint(90,130))
trees.sort()
o('<g>')
for y,x,w,fl,fi in trees:
    h=w*1167/1347
    # ground shadow
    o(f'<ellipse cx="{x+w*0.62:.0f}" cy="{y+h*0.95:.0f}" rx="{w*0.46:.0f}" ry="{w*0.12:.0f}" fill="#06110a" opacity=".42" filter="url(#soft6)" transform="rotate(8 {x+w*0.6:.0f} {y+h*0.95:.0f})"/>')
    st=' style="filter:saturate(.75) sepia(.25) brightness(.95)"' if fi=='dry' else ''
    o(img(TREE,x,y,w,h,fl,st))
o('</g>')

# ---------- scrub, rocks, craters, ore, alloy (real sprites) ----------
def sprite(name,x,y,w,flip=False,extra=''):
    h=w
    o(f'<ellipse cx="{x+w*0.56:.0f}" cy="{y+h*0.82:.0f}" rx="{w*0.40:.0f}" ry="{w*0.10:.0f}" fill="#0a0f08" opacity=".36" filter="url(#soft6)"/>')
    o(img(A+name,x,y,w,h,flip,extra))
S=[]
for k in range(46):
    x=R.randint(80,3300); y=R.randint(60,1700)
    # keep on land, off river corridor, off buildings
    if y> 1080+(1620-x)*0.2 and x>1500: continue
    if x>1500 and y>880+ (2250-x)*-0.0: pass
    S.append((x,y))
placed=[]
def ok(x,y):
    # river corridor
    for t in [i/60 for i in range(61)]:
        bx,by=bank(t)
        if abs(bx-x)<110 and abs(by-y)<110: return False
    # coast: land is above the coastline polyline roughly
    if x>1330:
        coast=640+(3000-x)*0.0 if x>3000 else (640+(3000-x)*0.43 if x>2250 else 860+(2250-x)*0.2 if x>1620 else 1080+(1620-x)*0.45)
        if y>coast-60: return False
    else:
        coast=1230+(1330-x)*0.6
        if y>coast-60: return False
    for n,bx,by,bw in b:
        if bx-40<x<bx+bw+40 and by-30<y<by+bw: return False
    if 300<x<760 and 770<y<1060: return False   # forest
    for (px,py) in placed:
        if abs(px-x)<70 and abs(py-y)<50: return False
    return True
items=[]
for k in range(260):
    x=R.randint(60,3400); y=R.randint(40,1800)
    kind=R.choices(['scrub','rock'],[3,2])[0]
    if y<330 and x>1700 and x<3300: kind='rock'
    if not ok(x,y): continue
    placed.append((x,y)); items.append((y,kind,x))
items.sort()
for y,kind,x in items[:62]:
    if kind=='scrub': sprite('scrub_cluster_v1.png',x,y,R.randint(64,92),R.random()<.5)
    else: sprite('rock_cluster_v1.png',x,y,R.randint(70,120),R.random()<.5)
for k in range(30):
    x=R.randint(1750,3300); y=R.randint(-20,250)
    if y>90+ (x-1750)*0.0 and (x<2000 or x>3200): continue
    sprite('rock_cluster_v1.png',x,y,R.randint(80,150),R.random()<.5)
# hero features
for x,y in [(790,330),(800,360)]: sprite('rock_cluster_v1.png',x-20,y-10,84)
for x,y,w in [(810,410,110),(770,455,100),(1400,780,110),(1450,820,100)]: sprite('ore_crystals_v1.png',x,y,w)
for x,y,w in [(2280,130,120),(2340,170,110)]: sprite('ore_crystals_v1.png',x,y,w,False,'style="filter:hue-rotate(95deg) saturate(1.1)"')
for x,y in [(2420,590),(1880,730)]: sprite('crater_v1.png',x,y,130)
o('<rect width="3600" height="2400" fill="url(#gSun)" opacity=".5"/>')
o('</svg></body></html>')
open('land.html','w').write('\n'.join(out))
print(len(out),'nodes')
