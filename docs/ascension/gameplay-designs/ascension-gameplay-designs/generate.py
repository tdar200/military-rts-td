"""Generate original, editable gameplay boards. No production game changes."""
from pathlib import Path
import html, json, math, textwrap, zipfile

ROOT = Path(__file__).parent
C = dict(bg='#090e12', panel='#121e25', raised='#1d2d35', line='#354951', text='#eaf0e7', muted='#a4b8bb', cyan='#76d5c5', amber='#eab56b', red='#f17d74', violet='#aba5e9')

SCENES = [
 dict(id='01-construction', title='Every building is a commitment.', chapter='01 / CONSTRUCTION & ECONOMIC EXPANSION', era='ERA 01', mode='placement',
      subtitle='Place a vehicle factory without blocking the ore route or silently starving your defences.',
      hud=['MATERIAL 840 / planned 280','POWER 130 / 160 kW','CREW 22 / 60','WAVE 01  01:12'],
      decision='Build now, or add generation first?',
      inspector=[('VEHICLE FACTORY / PREVIEW','280 materials • 40 kW • 30 s build','cyan'),('PROJECTED GRID','170 / 160 kW after commissioning. Defences keep priority; industry shares the deficit.','amber'),('PLACEMENT CONTRACT','Green footprint: valid terrain and territory. Dashed cyan: delivery access. Orange: consequence, not a placement error.','text'),('PLAYER OPTIONS','Enter confirms this footprint. R rotates 90°. Esc cancels the preview. Shift repeats placement while resources allow.','text')],
      maplabels=[('A','Delivery lane must stay open',340,515),('B','Projected power warning',825,225),('C','Finite ore: 8,250 remaining',270,235)],
      states=[('VALID / AFFORDABLE','Enter at a valid site','Reserve 280 once; queue the foundation. Available materials fall from 840 to 560. Ghost becomes a visible build site.','cyan'),('BLOCKED / NO ROUTE','Footprint closes the only lane','Red hatch and “Blocks refinery access”. Confirmation is rejected without debit; show the nearest valid footprint.','red'),('CANCEL / PARTLY BUILT','Cancel at 30% material consumption','84 consumed, 196 unconsumed returned. Available balance becomes 756. Repeated cancel cannot issue a second refund.','amber')],
      rules=['Placement validity is authoritative and rechecked at command execution; preview validity is advisory.', 'Reject overlap with solid buildings, out-of-map cells and hostile footprints. Friendly units receive an eviction order; construction waits for a clear site.', 'Construction progresses only with staff, work capacity and delivered materials. Power shortage appears as an explicit pause or throttle reason.', 'Maintain separate available, reserved and consumed ledgers. Reservation must be atomic across rapid repeated placements.', 'Territory follows completed anchors; losing an anchor pauses new placements, not demolition of surviving facilities.', 'Illustrative proposed costs and incremental consumption are design changes, not a description of the current runtime.'],
      acceptance=['Exactly 280 is reserved once per accepted build.', 'An invalid preview never changes money or occupancy.', 'A destroyed foundation releases only recoverable, unconsumed stock.', 'Reload restores footprint, consumed stock, reservation and completion work.']),
 dict(id='02-combined-arms', title='Win with roles, not a bigger number.', chapter='02 / SELECTION, ORDERS & COMBINED ARMS', era='ERA 01', mode='combat',
      subtitle='Armour pins the front. Anti-armour teams use cover. Mobile air defence protects the resupply route.',
      hud=['SELECTED 18 units','TANKS 4 / AT 3 / INF 8','AA 2 / AIR 1','SUPPLY 72%'], decision='Hold the ridge or push through the valley?',
      inspector=[('VANGUARD / 18 UNITS','Wedge formation • face north-east • return fire','cyan'),('TACTICAL COUNTERS','Tanks: open terrain. Infantry: cover and capture. AT: armour ambush. AA: air denial. Aircraft: exposed artillery.','text'),('ENGAGEMENT PREVIEW','Target: alien heavy armour. AT shot: 90 × (1 − 0.10) = 81 HP. 3 s cycle → 27 sustained DPS.','amber'),('COMMAND FEEDBACK','Solid arrows: immediate order. Dotted arrows: queued order. Threat rings show range; striped ring shows a blocked firing line.','text')],
      maplabels=[('A','AT team in ridge cover',725,250),('B','Tanks hold the open lane',720,480),('C','Aircraft skirts the AA envelope',1090,205)],
      states=[('SELECT / COMPOSE','Drag, then Shift-click to adjust','Unit strip groups by role. Ctrl+1 stores this exact group. Double-click selects visible units of the same type; UI clicks never select through.','cyan'),('ADVANCE / MAINTAIN SPACING','A then choose a destination','Units approach in assigned slots; local avoidance yields at choke points. Slow support units receive a trailing slot, not a teleport.','amber'),('RETREAT / RESUPPLY','R chooses the nearest safe depot','Low-ammo units disengage by cohort. Healthy screens cover withdrawal. A severed route produces “No safe supply path”, not idle silence.','red')],
      rules=['Proposed damage model: effective armour = clamp(armour − penetration, 0, 0.8); damage = max(1, base_damage × (1 − effective_armour)).', 'Controlled AT example: 900 HP target, 81 HP per hit, 3 s cycle, first shot at t=0. Twelve hits kill at t=33 s. Travel time and movement add separately.', 'No random accuracy in the baseline test model. Cover modifies exposed hit area through a documented multiplier; aircraft eligibility is a target-class rule.', 'Range test uses squared distance, inclusive boundary. LOS, target class and ammunition are checked again when a shot is emitted.', 'Hold means never pursue beyond assigned position radius. Attack-move can engage along the route; explicit target orders expire on target death.', 'Formation slots are a soft objective. Narrow corridors temporarily use a column; regroup beyond the obstruction. Never force units through walls.', 'Older units keep useful roles through low cost, low energy demand and specialized counter technology, not universal era damage scaling.'],
      acceptance=['AT controlled experiment deals 81 HP per hit and kills at 33 s.', 'Friendly units cannot occupy the same solid footprint.', 'A destroyed selected unit disappears from group counts.', 'Ground-only weapons reject aircraft without wasting ammunition.']),
 dict(id='03-logistics', title='The front line ends where supply ends.', chapter='03 / SUPPLY, DEPLETION & RECOVERY', era='ERA 02', mode='logistics',
      subtitle='A raid cuts the depot corridor. Recover the link, reroute a convoy or give ground before magazines empty.',
      hud=['DEPOT 240 rounds','ARMY 72 / 90 rounds','ROUTE 02 severed','BUFFER 00:24'], decision='Repair the route or retreat while covered?',
      inspector=[('SUPPLY NETWORK / L','Cyan = connected. Amber = delayed. Red = cut. No traditional fog of war.','cyan'),('FAILURE CASCADE','Bridge blocked → deliveries stop → depot drains → units exhaust carried rounds → firing stops. Movement remains possible.','red'),('CONSERVATION EXAMPLE','Three tanks start at 72 rounds each. Transfer 18 each: depot 240 → 186; each tank 72 → 90. Total stays 456.','amber'),('RECOVERY TOOLS','Assign repair crew, set a safe alternate route or place a forward depot. New logistics capacity costs materials and power.','text')],
      maplabels=[('A','Depot: 186 rounds after transfer',380,545),('B','Route blocked by alien raiders',740,395),('C','Three tanks: 90 rounds each',1030,420)],
      states=[('CONNECTED / STOCKED','Depot and valid path in range','Transfer only the minimum of unit deficit, depot stock and route throughput. Reserve stock per recipient to prevent double withdrawal.','cyan'),('SEVERED / BUFFERED','Depot or route is destroyed','Carried ammo remains. Route indicator turns red and estimates combat endurance from recent firing demand. Supply cannot teleport.','red'),('RESTORED / RECOVERING','Repair or alternate route completes','Delivery resumes at throughput limits. Empty units refill first within player priority; no instant full-army refill or free rounds.','amber')],
      rules=['Supply route overlays show actual traversable connectivity, not straight-line distance alone.', 'Early slice uses material-funded local ammunition distribution. Fuel, spare parts and routed convoys in this board are future design extensions where shown.', 'No ammunition permits movement and retreat but no weapon discharge. Aircraft retain a separately visible reserve-return rule in the full design.', 'Each shipment owns a unique reservation. Destruction moves contents to a wreck ledger or documented loss, never to both destination and source.', 'Automatic routing minimizes travel time plus exposed-threat cost; player waypoints override with a visible risk notice.', 'Economy buffer warning predicts remaining supply under current consumption, and labels the forecast as an estimate.', 'Repair work consumes a separate parts/material budget and cannot create ammo. Depots cannot distribute more than they hold.'],
      acceptance=['Ammo transfers conserve depot + units + in-transit inventory.', 'Destroying a depot cannot refill any unit.', 'A sealed wall blocks supply even if the depot is geographically close.', 'Save/load preserves shipment ownership and pending reservations.']),
 dict(id='04-wave-defence', title='Read the attack. Redesign the defence.', chapter='04 / ADAPTIVE WAVES & DEFENSIVE GEOMETRY', era='ERA 02', mode='waves',
      subtitle='The enemy commits to a siege wave after observing heavy walls. Create a mobile reserve instead of adding another wall.',
      hud=['WAVE 04 / SIEGE','ARRIVAL 00:45','RELAYS 2 active','RESERVE 6 units'], decision='Counter-battery strike or defence in depth?',
      inspector=[('DOCTRINE LOCKED / T−45','Siege: 2 artillery, 4 heavy escorts, 8 raiders. Composition estimate is marked as an estimate until confirmed.','red'),('DEFENCE PLAN','Outer obstacles delay. AT protects the breach. Turrets cover crossfire. Aircraft or mobile armour hunt the artillery.','text'),('AI OBSERVATION','Walls raise siege weight. Tanks raise anti-armour weight. Aircraft raise air-denial weight. Committed waves do not change after launch.','amber'),('STRATEGIC TRADEOFF','Each surviving relay contributes reinforcements. Raid a relay to lower future pressure, accepting a temporarily weaker home defence.','cyan')],
      maplabels=[('A','Crossfire, not one turret clump',655,445),('B','Siege battery outside turret range',1090,235),('C','Reserve counterattack route',790,600)],
      states=[('PREPARE / T−90 TO T−45','Inter-wave economy window','Show repairs, low ammunition and stalled construction first. Wave timer never hides while build or research panels are open.','cyan'),('COMMIT / T−45 TO T=0','Alien doctrine is committed','Announce approach and estimated threats. Preserve composition through save/load. Avoid instant counters to actions after commitment.','amber'),('ASSAULT / CLEANUP','Attackers reach the defence','Attack obstacles if no route exists. Detect path stalls, recalculate or engage the blocking structure. No unreachable enemy may stall the campaign.','red')],
      rules=['Current early-wave baseline: first arrival at 90 s; later arrivals at 180 s intervals; doctrine announced 45 s before arrival.', 'Composition shown here is illustrative. Spawn counts must be funded by the invasion budget plus operational relay contributions.', 'AI planner scores infrastructure value, exposure, route cost and expected losses. Tactical controller chooses legal targets with hysteresis to avoid target thrashing.', 'Doctrine observes a rolling history; it does not read queued human orders. Apply capped adaptation so all unit families remain viable.', 'Spawn positions are validated outside occupied solid cells. A blocked edge selects another legal entry, never deletes the wave silently.', 'Give each assault a progress watchdog. If no damage or advance occurs, change route, breach, or regroup; record the decision for QA.', 'The player can see the map; uncertainty concerns future intent, production capacity and unstudied weapons.'],
      acceptance=['Arrival and warning occur at exact configured ticks.', 'Reload cannot reroll doctrine or duplicate a wave.', 'Enemy artillery has a counter and a minimum deployment vulnerability.', 'Blocking all spawn cells cannot suppress future pressure for free.']),
 dict(id='05-research-deployment', title='Knowledge is not industrial capacity.', chapter='05 / RESEARCH, PROTOTYPES & ERA ADVANCEMENT', era='ERA 01 → 02', mode='research',
      subtitle='A robotic-workcell prototype reserves one factory. Decide whether the long-term productivity gain justifies fewer tanks now.',
      hud=['SCIENCE 62% theory','PROTOTYPE 0 / 1','FACTORY 01 reserved','POWER 30 kW needed'], decision='Commit the factory, or postpone the era transition?',
      inspector=[('ROBOTIC WORKCELLS','Advanced computing + precision manufacturing → theory → powered prototype → commissioning.','cyan'),('EXPLICIT OPPORTUNITY COST','Factory 01 is reserved for the prototype. Factory 02 keeps its tank queue. No hidden suspension of all military production.','amber'),('ERA ADVANCEMENT','Validate the prototype and commission the first workcell. Unlock Era 02 infrastructure; existing tanks keep their model and role.','text'),('SCIENCE LABEL','Engineering extrapolation. Robotics is established; flexible reliable automation at this scale depends on engineering and energy.','violet')],
      maplabels=[],
      states=[('THEORY / LAB-BOUND','Fund the project with prerequisites met','Computing and staffed laboratories advance theory. Show effective rate and the current bottleneck; more power alone cannot replace experiments.','cyan'),('PROTOTYPE / FACTORY-BOUND','Theory complete; reserve one factory','Pause only the chosen production bay. Factory destruction transfers to a valid replacement; otherwise preserve progress in a halted state.','amber'),('DEPLOY / ECONOMY-BOUND','Prototype validated and tooling built','Commission the first upgraded line, unlock Era 02 and offer optional retrofits. No automatic empire-wide transformation.','violet')],
      rules=['Research graph is a directed acyclic graph; every prerequisite, unit unlock and facility ID resolves before shipping.', 'Separate theory work, experimental evidence, prototype work and deployment eligibility; a single points bar cannot substitute for all four.', 'Proposed retrofit: 120 materials + 20 s downtime buys +25% compatible work rate and +30 kW demand. Pay per facility; this is a design value, not current balance.', 'Example factory: 12 work/s, 360 work per tank. Baseline 30 s; retrofitted 15 work/s gives 24 s with full supply. At 50% served capacity, 48 s.', 'Prototype reservation is exclusive and recorded in saves. Another laboratory cannot clone the same prototype progress or reserve the same bay.', 'Era UI previews new capabilities and continuing constraints before commit. No technology is completed by merely entering an era.', 'Destruction of infrastructure pauses requirements-dependent work; established knowledge remains unless a explicitly designed scenario says otherwise.'],
      acceptance=['A prototype cannot advance without its powered required facility.', 'Only one chosen factory is reserved for this prototype.', 'Era advancement fires exactly once at commissioning.', 'Legacy units and buildings remain valid after the transition.']),
 dict(id='06-core-assault', title='Break the invasion’s coordination.', chapter='06 / RELAY RAIDS, CORE ASSAULT & CAMPAIGN END', era='ERA 02', mode='core',
      subtitle='Take down optional relay support, secure a forward depot and commit a supplied combined-arms force to the Core district.',
      hud=['CORE 4,800 / 12,000 HP','RELAYS 1 / 2 active','HQ 72% integrity','AMMO 61%'], decision='Finish the Core, or divert to save headquarters?',
      inspector=[('OBJECTIVE / CORE NODE','Destroying the Core ends the Earth operation. Relay destruction reduces reinforcements but is not mandatory.','red'),('ASSAULT SEQUENCE','Suppress AA → clear the AT screen → move tanks up → protect the forward depot → focus the exposed Core.','text'),('TELEGRAPHED RETALIATION','Core charge: 8 s warning, marked impact zone, interruptible emitter. Disperse or destroy the emitter; no unavoidable screen-wide kill.','amber'),('AFTERMATH','Freeze hostile simulation, show casualties and economy history, reveal an off-world command signature and offer the Solar campaign.','cyan')],
      maplabels=[('A','Forward depot sustains the push',515,545),('B','Core retaliation: move out',1080,325),('C','HQ raid still needs a response',320,235)],
      states=[('BREACH / SUPPLIED','Outer AA and anti-armour cleared','Expose a safe approach. Units retain ammo limits; direct-rush strategy remains possible with enough preparation.','cyan'),('TERMINAL / SAME-TICK RESOLUTION','Core HP or HQ HP reaches zero','Resolve all damage for the tick first. Core dead and HQ alive = victory; HQ dead and Core alive = loss; both dead = mutual destruction.','red'),('DEBRIEF / NEXT HORIZON','A terminal outcome is committed','Emit one outcome event. Stop combat and economy mutation. Preserve final replay state; restart uses a fresh seed/state, not old orders.','violet')],
      rules=['Core health and terminal state are authoritative. Clients cannot award victory from a local animation.', 'The simultaneous-destruction outcome is a proposed explicit rule requiring implementation; do not infer it from the current ordering of damage events.', 'Every weapon class that can legally damage structures can finish the Core. A projectile already emitted may finish it after its attacker dies.', 'Defeat debrief shows what failed, the last supply interruption and the timing of production pauses; avoid a bare “You lose” screen.', 'A resource deadlock prompts recovery options before declaring defeat. Losing all combat units alone is not defeat while production remains possible.', 'Camera keeps the Core visible during the final assault but never steals control before terminal resolution.', 'Cosmic campaign reveal is narrative progression, not proof that later layers are currently playable.'],
      acceptance=['Victory event is emitted once regardless of multiple lethal hits.', 'No future wave, shot, refund or build order mutates terminal state.', 'Simultaneous HQ/Core loss produces the documented outcome.', 'Restart clears selection, build ghosts, commands and prior wave timers.']),
 dict(id='07-scale-transition', title='Zoom out without throwing your army away.', chapter='07 / PLANETARY & SOLAR STRATEGY TRANSITION', era='ERA 03 → 04', mode='solar',
      subtitle='Delegate stabilized regions, preserve their ledgers and retain direct command of strategically important operations.',
      hud=['POWER 4.8 / 6.2 TW','INDUSTRY 8.4 Mt/yr','FLEETS 6 task forces','TRANSIT 82%'], decision='How much authority should a planetary governor have?',
      inspector=[('REGION → PLANET → SYSTEM','A region becomes a persistent production and defence contract, not a freshly minted resource bonus.','cyan'),('CONSERVATION EXAMPLE','Earth 1,200 + Mars 800 + in transit 100 = 2,100 kt before and after aggregation. Transit stock belongs to one shipment.','amber'),('GOVERNOR CONTRACT','Civilian minimum 55%; defence reserve 20%; expansion up to 25%. Cannot overspend, disassemble inhabited assets or change species policy.','text'),('PLAYER AGENCY','Set objectives, budgets and fallback doctrine. Exceptions open an operation card with the exact shortage, route risk and available intervention.','violet')],
      maplabels=[],
      states=[('DELEGATE / PREVIEW','Choose a stable region','Show inventories, work rates, garrisons and standing orders that will be retained. No conversion until the player confirms the contract.','cyan'),('AGGREGATE / PRESERVE','Transfer authority at a tick boundary','Store one ownership ledger. Disable duplicate low-level simulation of the same inventory; preserve queues and transit in the aggregate model.','amber'),('RE-ENTER / INSPECT','Open a threatened operation','Restore or deterministically instantiate the tactical state from the saved contract. Never spawn a new full army in addition to the abstract one.','violet')],
      rules=['Full future design: tactical entities aggregate into cohorts with count, equipment, HP distribution, ammunition and orders.', 'Use a single owner for each simulation domain. Change ownership transactionally; do not run tactical and aggregate production on the same assets.', 'Zoom is presentation only. Time speed is explicit, bounded by active engagements, and applied consistently to travel, research and resource flows.', 'Planetary logistics respects launch mass, transfer windows, travel time and receiving capacity. A space elevator raises throughput, not free material.', 'Interstellar orders execute on delivery under the chosen physical model. Standing local orders prevent the entire civilization waiting for the player.', 'No FTL logistics before the explicitly speculative branch. Antimatter is manufactured energy storage, not net energy creation.', 'Army groups retain composition vulnerabilities: a system with many transports and no escorts is not equivalent to an equally expensive combat fleet.'],
      acceptance=['Resource totals and military cohorts match before/after every scale change.', 'Repeated zoom in/out cannot duplicate units or reset damage.', 'A destroyed destination reroutes or holds cargo under policy.', 'Governor exceptions surface before an irreversible policy violation.']),
 dict(id='08-cosmic-governance', title='At cosmic scale, survival is the objective.', chapter='08 / GALACTIC WARFARE & COSMIC STEWARDSHIP', era='ERA 08 → 10', mode='galaxy',
      subtitle='Control routes, energy, computation and resilience while respecting the limits of the chosen physics model.',
      hud=['POWER 2.4 × 10³³ W','COMPUTE 61% allocated','GATEWAYS 42 / 45','REFUGES 7 / 12'], decision='Expand the network or preserve a survivable reserve?',
      inspector=[('WORMHOLE NETWORK / SPECULATIVE','Inspired by general relativity; requires unproven traversability and stabilizing negative energy. Gameplay permission is an explicit scenario assumption.','violet'),('COUNTERPLAY / ROUTE DENIAL','Gateway attack cuts throughput. Distributed depots, redundant routes, local production and conventional fallback fleets prevent a single unstoppable strike.','text'),('VICTORY / RESILIENCE CONTRACT','Maintain 12 independent refuges, survive 3 disruption cycles and preserve 90% of civilization information under the scenario’s finite horizon.','cyan'),('PHYSICAL BOUNDARY','Observable-universe control is not guaranteed: expansion and causal horizons limit reach. Artificial universes remain unknown-physics research, not established capability.','amber')],
      maplabels=[],
      states=[('SECTOR / AUTONOMOUS','Set fleet and production policy','Governors operate inside energy, matter and compute budgets. A local emergency spends only its reserved contingency allocation.','cyan'),('DISRUPTION / ISOLATED','A gateway or star-power hub is lost','Sever the route, expose the affected civilian reserve and execute fallback policy. Redundant sectors retain useful agency.','red'),('COSMIC / SURVIVAL','Complete the resilience contract','Victory evaluates retained minds, information, redundancy and sustainable power—not only destroyed enemy headquarters.','violet')],
      rules=['Era 05 interstellar: propulsion and autonomous probes; Era 06 stellar: swarms, lifting and stellar industry; Era 07 post-biological: optional digital and hybrid societies.', 'Era 08 spacetime: explicitly speculative gateways and gravity research; Era 09 galactic: sector policies and distributed warfare; Era 10 cosmic: survival under causal and thermodynamic limits.', 'Dyson swarms are orbiting collectors; no unsupported rigid sphere. Stellar engines use momentum transfer. Black-hole energy extraction has an explicit source of mass or spin.', 'Relativistic strike: large preparation cost, visible launch infrastructure and long lead time; counter with dispersal, interception and relocation. No instant uncounterable kill button.', 'Gateways impose mass/energy throughput and stabilization costs. Capturing a gateway does not grant unlimited instantaneous movement.', 'Digital minds require compute, power and backup consistency. Biological populations require habitats, ecology and care; neither path is mandatory or a pure stat upgrade.', 'Scenario physics choices are disclosed before campaign start and stored in the save. Never silently introduce faster-than-light solutions in a hard-science campaign.'],
      acceptance=['Each exotic weapon has a cost, warning, counter and aftermath.', 'Sector automation cannot spend the same reserve twice.', 'No energy-positive antimatter production loop exists.', 'Victory checks resilience across disruption cycles, not a momentary stockpile spike.']),
]

class SVG:
    def __init__(self,w=1920,h=1440):
        self.parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs><style>@font-face{{font-family:Rajdhani;src:url(../fonts/Rajdhani-SemiBold.ttf)}}text{{font-family:DejaVu Sans,sans-serif}}.head{{font-family:Rajdhani,DejaVu Sans,sans-serif;font-weight:600}}</style><pattern id="hatch" width="12" height="12" patternUnits="userSpaceOnUse"><path d="M0 12L12 0" stroke="#f17d74" opacity=".5"/></pattern></defs>']
    def add(self,s): self.parts.append(s)
    def rect(self,x,y,w,h,fill='panel',stroke=None,r=0):
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{C.get(fill,fill)}"'+(f' stroke="{C.get(stroke,stroke)}"' if stroke else '')+'/>')
    def text(self,x,y,s,size=18,color='text',head=False):
        self.add(f'<text x="{x}" y="{y}" font-size="{size}" fill="{C.get(color,color)}"'+(' class="head"' if head else '')+f'>{html.escape(str(s))}</text>')
    def wrap(self,x,y,s,width,size=18,color='muted',leading=None):
        leading=leading or size*1.55
        lines=[]
        for p in s.split('\n'): lines+=textwrap.wrap(p,max(8,int(width/(size*.57)))) or ['']
        for line in lines: self.text(x,y,line,size,color);y+=leading
        return y
    def path(self,d,stroke='cyan',width=2,fill='none',dash=None,opacity=1):
        self.add(f'<path d="{d}" fill="{C.get(fill,fill)}" stroke="{C.get(stroke,stroke)}" stroke-width="{width}" opacity="{opacity}"'+(f' stroke-dasharray="{dash}"' if dash else '')+'/>')
    def circle(self,x,y,r,fill='cyan',stroke=None,opacity=1):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{C.get(fill,fill)}" opacity="{opacity}"'+(f' stroke="{C.get(stroke,stroke)}"' if stroke else '')+'/>')
    def end(self): return ''.join(self.parts)+'</svg>'

def building(s,x,y,name,w=94,h=62,color='cyan'):
    s.rect(x+8,y+10,w,h,'#121c1b')
    s.path(f'M{x} {y}l18 -14h{w}l-18 14Z', '#6c7970',1,'#5b685e')
    s.path(f'M{x+w} {y}l18 -14v{h}l-18 14Z','#33423a',1,'#2c3d33')
    s.rect(x,y,w,h,'#424f46','#758779')
    for i in range(4):s.rect(x+10+i*20,y+8,2,h-19,'#66766a')
    s.rect(x+5,y+h-6,w-10,3,color)
    s.text(x,y+h+23,name,12,'muted')

def unit(s,x,y,kind='tank',enemy=False,selected=True):
    color='red' if enemy else 'cyan'
    if selected:s.circle(x,y,20,'none',color)
    if kind=='tank':
        s.add(f'<g transform="translate({x-12} {y-16}) rotate(30 12 16)"><path d="M0 4h5v29H0ZM19 4h5v29h-5Z" fill="#25312d" stroke="#8a9b87"/><path d="M5 7h14v24H5Z" fill="{C[color]}"/><path d="M8 11h8v13H8ZM11 -6h3v20h-3Z" fill="#d4dbc4"/></g>')
    elif kind=='air':s.path(f'M{x} {y-24}l5 20 22 12 -23 -5 -4 18 -4 -18 -23 5 22 -12Z',color,1,'#c4cfbd')
    elif kind=='at':s.path(f'M{x} {y-12}l11 23h-22Z',color,2,'#293d37');s.path(f'M{x+3} {y-6}l17 -12',color,4)
    else:s.circle(x,y,6,color);s.path(f'M{x} {y+6}v9m-7 -8h14',color,3)
    s.rect(x-15,y+27,30,3,'line');s.rect(x-15,y+27,24,3,color)

def terrain(s):
    s.rect(32,260,1220,638,'#222e28')
    s.add('<g clip-path="url(#terrainClip)">')
    for i in range(16):s.path(f'M0 {280+i*48}Q340 {120+i*46} 670 {340+i*37}T1300 {160+i*43}','#55684e',1,opacity=.25)
    s.path('M0 450Q230 375 420 452T820 470T1310 382','#405e54',54)
    s.path('M0 450Q230 375 420 452T820 470T1310 382','#7c9b89',2,opacity=.55)
    s.path('M150 950L625 606L910 628L1190 270','#444c43',55)
    s.path('M150 950L625 606L910 628L1190 270','#8a8d74',2,dash='18 14')
    for i in range(75):
        x=55+(i*113)%1150;y=290+(i*73)%570
        if x<270 or (x>890 and y>700) or y<355:s.path(f'M{x} {y}l-11 22h22Z','#3d5840',1,'#18281d')
    for x,y in [(265,530),(290,546),(311,524),(275,555),(327,550)]:s.path(f'M{x} {y}l-10 17 18 8 12 -13Z','#92a0a0',1,'#626d69')
    s.add('</g>')

def tactical(s,d):
    terrain(s)
    building(s,365,645,'COMMAND',106,70);building(s,505,735,'DEPOT',75,47);building(s,355,555,'REFINERY',88,53)
    for i in range(8):s.rect(550+i*33,555,28,13,'#879178')
    for x in [560,710,812]:s.circle(x,602,18,'#4f6654','cyan');s.path(f'M{x} 602l21 -15','cyan',4)
    s.path('M410 621L552 756L748 690L945 575','cyan',2,dash='7 7')
    for i in range(4):unit(s,805+(i%2)*52,640+(i//2)*58)
    for i in range(3):unit(s,689+i*39,513,'at')
    for i in range(8):unit(s,590+(i%4)*28,666+(i//4)*36,'infantry')
    for i in range(5):unit(s,1060+(i%3)*46,503+(i//3)*48,'tank',True,False)
    unit(s,997,380,'air')
    if d['mode']=='placement':
        s.rect(636,710,145,95,'#28493c','cyan');s.path('M636 710l22 -16h145l-22 16Z','cyan',1,'#36584b');s.rect(652,725,112,54,'none','cyan');s.text(638,838,'VEHICLE FACTORY / VALID',13,'cyan')
        s.path('M576 805L622 773','cyan',3);s.circle(710,754,112,'none','amber');s.text(707,686,'+40 kW',16,'amber')
    elif d['mode']=='combat':
        s.circle(1060,490,118,'none','red',.8);s.path('M985 424Q929 342 1120 316','cyan',3,dash='8 6');s.path('M837 650L979 575','cyan',3);s.text(946,666,'AA THREAT',12,'red');s.text(643,479,'RIDGE COVER / AT',12,'cyan')
    elif d['mode']=='logistics':
        s.path('M580 750L725 672','amber',4,dash='7 6');s.path('M726 655l30 30m0 -30l-30 30','red',5);s.text(714,716,'ROUTE CUT',13,'red');unit(s,748,631,'tank',True);s.path('M584 773Q651 859 959 695','amber',2,dash='9 7');s.text(770,839,'ALTERNATE ROUTE / +18 s',12,'amber')
    elif d['mode']=='waves':
        for i in range(2):building(s,1068+i*61,329+i*45,'SIEGE',45,33,'red')
        s.path('M1090 363Q990 461 729 590','red',2,dash='5 7');s.path('M788 735Q1017 814 1191 468','cyan',3,dash='10 7');s.text(974,790,'MOBILE RESERVE',12,'cyan')
    elif d['mode']=='core':
        s.path('M1060 329L1127 370L1103 466L1055 492L1008 456L997 373Z','red',2,'#36232b');s.path('M1058 347L1081 400L1056 461L1031 400Z','red',1,'#bf6a68');s.circle(948,618,80,'none','amber');s.text(897,609,'IMPACT / 8 s',14,'amber');s.text(1013,515,'CORE NODE',14,'red')
    anchors={'placement':[(578,773),(710,685),(294,546)],'combat':[(722,513),(828,655),(998,381)],'logistics':[(542,755),(742,669),(830,650)],'waves':[(710,602),(1090,358),(1004,754)],'core':[(542,755),(948,618),(417,677)]}
    for i,(key,caption,x,y) in enumerate(d['maplabels']):
        xx,yy=66,302+i*63;tx,ty=anchors[d['mode']][i]
        s.path(f'M{xx+276} {yy+20}L{tx} {ty}','muted',1,dash='3 5',opacity=.55)
        s.circle(tx,ty,4,'cyan');s.rect(xx,yy,282,48,'panel','line')
        s.circle(xx+19,yy+23,12,'none','cyan');s.text(xx+14,yy+28,key,12,'cyan');s.wrap(xx+40,yy+21,caption,232,12,'text',17)

def research(s):
    s.rect(32,260,1220,638,'#101920')
    cols=[70,455,840]
    for i,t in enumerate(['01 / DISCOVER','02 / VALIDATE','03 / COMMISSION']):s.text(cols[i],306,t,15,'cyan')
    for x in [381,766]:s.path(f'M{x} 409h65','cyan',3);s.path(f'M{x+54} 402l11 7 -11 7','cyan',2)
    cards=[(70,350,'Advanced computing','COMPLETE','8 lab teams • 100%'),(70,501,'Precision manufacturing','COMPLETE','Materials lab • 100%'),(455,350,'Robotic-workcell theory','ACTIVE / 62%','12 compute units • 60 kW'),(455,501,'Factory prototype','WAITING FOR THEORY','Factory 01 reserved • 30 kW'),(840,350,'Install first workcell','LOCKED / TOOLING','120 materials • 20 s downtime'),(840,501,'ERA 02 / INDUSTRIAL','COMMISSION TO ADVANCE','Unlocks automation + new grids')]
    for x,y,title,state,detail in cards:
        s.rect(x,y,330,121,'raised','cyan' if 'ACTIVE' in state else 'line');s.text(x+17,y+29,state,12,'amber' if 'WAITING' in state else 'cyan');s.text(x+17,y+63,title,24,'text',True);s.text(x+17,y+97,detail,13,'muted')
    s.path('M400 563H424V410H455','cyan',2);s.path('M620 471v30','cyan',2);s.path('M785 562h30V410h25','cyan',2)
    s.rect(70,671,1100,165,'panel','line');s.text(90,704,'THE OPPORTUNITY COST IS VISIBLE',13,'amber');s.text(90,743,'Factory 01: prototype reservation',24,'text',True);s.text(90,780,'Factory 02: tank queue continues',18,'cyan');s.text(685,744,'12 → 15 work/s',31,'text',True);s.text(685,782,'30 s → 24 s per tank at full supply',16,'muted')

def space(s,galaxy=False):
    s.rect(32,260,1220,638,'#0b121b')
    for i in range(145):s.circle(49+(i*173)%1180,281+(i*89)%590,1+(i%7==0),'#adbbd4',opacity=.2+(i%4)*.12)
    if galaxy:
        for a in range(3):
            points=[]
            for i in range(90):
                theta=i*.057+a*2.094;r=25+i*4.5;points.append((647+math.cos(theta)*r*1.2,565+math.sin(theta)*r*.62))
            s.path('M'+'L'.join(f'{x:.1f} {y:.1f}' for x,y in points),'#716f98',24,opacity=.12)
        nodes=[(385,650,'SOL LEGACY','cyan'),(550,715,'REFUGE / 04','cyan'),(739,523,'GATEWAY NEXUS','violet'),(918,457,'INTERDICTED','red'),(554,405,'ORION COMPUTE','cyan')]
        s.path('M385 650L550 715L739 523L554 405L385 650','cyan',2);s.path('M739 523L918 457','red',3,dash='7 7')
        s.text(884,525,'CAPACITY 0 / 12',13,'red')
    else:
        for rx,ry in [(180,91),(306,164),(475,248)]:s.add(f'<ellipse cx="630" cy="563" rx="{rx}" ry="{ry}" fill="none" stroke="#334a54"/>')
        s.circle(630,563,38,'amber');s.circle(630,563,58,'amber',opacity=.08)
        nodes=[(420,471,'EARTH / 1,200 kt','cyan'),(803,435,'MARS / 800 kt','amber'),(988,665,'CERES LOGISTICS','cyan')]
        s.path('M420 471Q531 324 803 435T988 665Q627 815 420 471','cyan',2,dash='8 8');s.text(645,758,'IN TRANSIT / 100 kt',14,'cyan')
    for x,y,t,c in nodes:s.circle(x,y,13,c);s.circle(x,y,23,'none',c);s.text(x+31,y-9,t,16,c,True)
    s.rect(64,796,1150,67,'panel','line');s.text(84,824,'POLICY: CIVILIAN 55%  /  DEFENCE 20%  /  EXPANSION 25%',15,'cyan');s.text(84,849,'No inhabited-world disassembly • Escalate civilian route loss • Preserve local reserves',13,'muted')

def board(d):
    s=SVG();s.rect(0,0,1920,1440,'bg');s.add('<defs><clipPath id="terrainClip"><rect x="32" y="260" width="1220" height="638"/></clipPath></defs>')
    s.text(32,40,'A / ASCENSION',23,'cyan',True);s.text(1315,39,'DETAILED GAMEPLAY DESIGN  /  PROPOSED',14,'muted');s.text(32,86,d['chapter'],14,'muted');s.text(32,144,d['title'],48,'text',True);s.text(34,181,d['subtitle'],17,'muted')
    s.rect(32,213,1220,47,'panel','line')
    for i,item in enumerate(d['hud']):s.text(49+i*306,243,item,13,'amber' if i==2 else 'text')
    if d['mode']=='research':research(s)
    elif d['mode'] in ['solar','galaxy']:space(s,d['mode']=='galaxy')
    else:tactical(s,d)
    s.rect(32,898,1220,77,'panel','line')
    commands={'placement':[('Enter','Confirm'),('R','Rotate'),('Shift','Repeat'),('P','Power'),('Esc','Cancel')], 'research':[('Enter','Fund theory'),('P','Pin path'),('F','Factory'),('Q','Queue'),('Esc','Close')], 'solar':[('Tab','Change scale'),('G','Governors'),('O','Orders'),('L','Logistics'),('Esc','Back')], 'galaxy':[('G','Governors'),('R','Reserves'),('L','Gateways'),('E','Exceptions'),('Esc','Back')]}.get(d['mode'],[('A','Attack-move'),('M','Move'),('H','Hold'),('R','Resupply'),('L','Logistics')])
    for i,(key,label) in enumerate(commands):
        x=53+i*231;s.rect(x,914,211,44,'raised','cyan' if i==0 else 'line');s.text(x+15,943,key+'   '+label,15,'text')
    s.rect(1280,213,608,762,'panel','line');s.text(1306,247,'PLAYER DECISION',13,'cyan');y=s.wrap(1306,284,d['decision'],550,27,'text',36)+13
    for title,body,c in d['inspector']:
        s.path(f'M1306 {y-8}H1860','line',1);s.text(1306,y+19,title,13,c);y=s.wrap(1306,y+48,body,550,17,'muted',25)+27
    s.text(32,1017,'INTERACTION STATES / INPUT → FEEDBACK → SIMULATION CONSEQUENCE',14,'cyan')
    for i,(state,trigger,effect,c) in enumerate(d['states']):
        x=32+i*625;s.rect(x,1040,604,292,'panel','line');s.rect(x,1040,604,3,c);s.text(x+22,1078,state,16,c);s.wrap(x+22,1116,trigger,557,22,'text',29);s.wrap(x+22,1188,effect,552,17,'muted',27)
    s.text(32,1373,'DESIGN CONTRACT',13,'cyan');s.text(227,1373,d['acceptance'][0],15,'text');s.text(32,1414,'Illustrative balance and future mechanics • Consult the companion interaction specification • No production game behaviour changed',12,'muted');s.text(1640,1414,d['era']+'  /  '+d['id'][:2],13,'muted')
    return s.end()

def main():
    for d in SCENES:(ROOT/'boards'/f"{d['id']}.svg").write_text(board(d))
    (ROOT/'gameplay-spec.json').write_text(json.dumps(SCENES,indent=2,ensure_ascii=False))
    css='''@font-face{font-family:Rajdhani;src:url(fonts/Rajdhani-SemiBold.ttf)}*{box-sizing:border-box}body{margin:0;background:#090e12;color:#eaf0e7;font:16px/1.65 system-ui,sans-serif}header{padding:36px 4vw 26px;border-bottom:1px solid #354951}h1,h2,h3{font-family:Rajdhani,sans-serif;line-height:1.15}h1{font-size:46px;margin:6px 0 10px}h2{font-size:32px}p{max-width:1000px;color:#a4b8bb}a{color:#76d5c5}nav{display:flex;gap:8px;flex-wrap:wrap;padding:20px 4vw;position:sticky;top:0;background:#090e1ff5;z-index:5}button{font:inherit;color:#a4b8bb;border:1px solid #354951;background:#121e25;padding:10px 15px;cursor:pointer}button[aria-selected=true],button:hover{color:#76d5c5;border-color:#76d5c5}button:focus-visible,a:focus-visible{outline:3px solid #eab56b;outline-offset:4px}main{padding:0 3vw 70px}.board{width:100%;height:auto;display:block;border:1px solid #354951}.details{display:grid;grid-template-columns:1.25fr 1fr;gap:32px;margin:30px 1vw}.card{background:#121e25;border:1px solid #354951;padding:26px;margin-bottom:20px}.kicker{font-size:12px;color:#76d5c5;letter-spacing:2px}li{margin:12px 0;color:#a4b8bb}.notice{font-size:14px;color:#eab56b}.state{display:none}.state.active{display:block}section[hidden]{display:none}.downloads{display:flex;gap:24px;flex-wrap:wrap}.sequence{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:28px}.sequence div{padding:16px;border:1px solid #354951;background:#121e25}.sequence b{color:#76d5c5;display:block}.sequence span{font-size:13px;color:#a4b8bb}footer{padding:20px 4vw;border-top:1px solid #354951;color:#a4b8bb}@media(max-width:850px){.details{grid-template-columns:1fr}.sequence{grid-template-columns:1fr 1fr}h1{font-size:34px}nav{position:static}}@media print{nav,button{display:none}section[hidden]{display:block}.details{break-after:page}}'''
    nav=''.join(f'<button role="tab" id="tab-{i}" aria-controls="panel-{i}" aria-selected="{str(i==0).lower()}" data-tab="{i}">{i+1:02} {html.escape(d["chapter"].split(" / ")[1].split(" & ")[0].title())}</button>' for i,d in enumerate(SCENES))
    sections=[]
    for i,d in enumerate(SCENES):
        states=''.join(f'<div class="state {"active" if j==0 else ""}" id="state-{i}-{j}"><h3>{html.escape(st[0])}</h3><p><strong>Input:</strong> {html.escape(st[1])}</p><p><strong>Result:</strong> {html.escape(st[2])}</p></div>' for j,st in enumerate(d['states']))
        buttons=''.join(f'<button data-state="{i}-{j}" aria-pressed="{str(j==0).lower()}">{j+1}. {html.escape(st[0].split(" / ")[0])}</button>' for j,st in enumerate(d['states']))
        sections.append(f'''<section role="tabpanel" id="panel-{i}" aria-labelledby="tab-{i}" {"hidden" if i else ""}><img class="board" src="boards/{d['id']}.svg" alt="{html.escape(d['title'])} Detailed gameplay map, decision inspector and three interaction states."><div class="details"><div class="card"><span class="kicker">IMPLEMENTATION CONTRACT</span><h2>{html.escape(d['decision'])}</h2><ol>{''.join('<li>'+html.escape(r)+'</li>' for r in d['rules'])}</ol></div><div><div class="card"><span class="kicker">EXPLORE STATES / DESIGN PREVIEW</span><div class="downloads">{buttons}</div>{states}</div><div class="card"><span class="kicker">ACCEPTANCE CHECKS</span><ul>{''.join('<li>'+html.escape(r)+'</li>' for r in d['acceptance'])}</ul><a href="boards/{d['id']}.svg" download>Download editable SVG board →</a></div></div></div></section>''')
    script='''const tabs=[...document.querySelectorAll('[data-tab]')];function show(i){tabs.forEach((b,j)=>{b.setAttribute('aria-selected',j===i);document.querySelector('#panel-'+j).hidden=j!==i});location.hash='board-'+(i+1)}tabs.forEach((b,i)=>b.addEventListener('click',()=>show(i)));document.querySelector('[role=tablist]').addEventListener('keydown',e=>{let i=tabs.indexOf(document.activeElement);if(i<0)return;if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();i=(i+(e.key==='ArrowRight'?1:-1)+tabs.length)%tabs.length;tabs[i].focus();show(i)}});document.querySelectorAll('[data-state]').forEach(b=>b.addEventListener('click',()=>{let[i,j]=b.dataset.state.split('-');document.querySelectorAll('#panel-'+i+' .state').forEach(s=>s.classList.remove('active'));document.querySelector('#state-'+i+'-'+j).classList.add('active');document.querySelectorAll('#panel-'+i+' [data-state]').forEach(x=>x.setAttribute('aria-pressed',x===b))}));let start=Number(location.hash.replace('#board-',''))-1;if(Number.isInteger(start)&&start>=0&&start<tabs.length)show(start);'''
    page=f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ascension / Detailed gameplay design</title><style>{css}</style><header><span class="kicker">ASCENSION / GAMEPLAY DESIGN PACK 02</span><h1>From a single foundation to a civilization.</h1><p>Eight detailed gameplay boards connect player decisions, readable battlefield feedback and exact simulation contracts. Use the tabs to inspect each system and the state buttons to compare normal, interrupted and recovery behaviour.</p><p class="notice">Proposed designs and illustrative balance—not implemented gameplay. Figma's Starter-plan API limit blocked publication; the SVG boards below are ready to import into the existing file.</p><div class="downloads"><a href="https://www.figma.com/design/jeYvt0dxHykkMDjuoYJaSm">Existing Figma designs ↗</a><a href="ascension-gameplay-designs.zip" download>Download complete pack ↓</a><a href="gameplay-spec.json" download>Machine-readable specification ↓</a></div><div class="sequence"><div><b>FOUND / 0–45 s</b><span>Read the base. Establish ore, power and delivery access.</span></div><div><b>PREPARE / 45–90 s</b><span>Read the first wave. Train mixed counters. Protect supply.</span></div><div><b>TRANSFORM / MID-MISSION</b><span>Reserve industry for prototypes. Expand and raid relays.</span></div><div><b>COMMIT / ENDGAME</b><span>Sustain the assault. Defeat the Core. Preserve civilization.</span></div></div></header><nav role="tablist" aria-label="Gameplay boards">{nav}</nav><main>{''.join(sections)}</main><footer>All artwork is original vector geometry. No desktop mouse automation. Future eras are design proposals. Generated from gameplay-spec.json and generate.py.</footer><script>{script}</script></html>'''
    (ROOT/'index.html').write_text(page)
    with zipfile.ZipFile(ROOT/'ascension-gameplay-designs.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(ROOT.rglob('*')):
            if p.is_file() and p.suffix in ['.svg','.ttf','.html','.json','.py','.txt'] and 'preview' not in p.parts:z.write(p,p.relative_to(ROOT))
    print(f'Generated {len(SCENES)} boards, {sum(len(d["rules"]) for d in SCENES)} implementation rules and {sum(len(d["acceptance"]) for d in SCENES)} acceptance checks.')

if __name__=='__main__':main()
