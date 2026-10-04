# End-to-end QA matrix

Prepared before main execution; updated with observed results. Passes apply only to exercised cases. Missing features and open defects are explicit. See REPORT.md for reproducibility and limits.

| System | Main journey | Adversarial / boundaries | Result |
|---|---|---|---|
| Opening and campaign | fresh deploy → economy → research → mixed assault → Core victory | restart; simultaneous HQ loss; terminal commands | Running final fresh UI campaign |
| Economy and finite ore | truck → refinery buffer → material → production | empty deposit; full buffer; two trucks; destroyed receiver; exact costs | Passed exercised boundaries and ledger |
| Power and batteries | priority allocation; surplus charge; deficit discharge | zero/equilibrium; generator loss; battery destruction; brownout rounding | Passed exercised service/rounding cases |
| Construction and repair | all 11 human structures; valid previews; completion | overlap; borders; occupied tile; spam; sell twice; sell then repair | Partial; refund/repair defects fixed, not every placement permutation |
| Unit production | five human roles; cost/time/crew/rally | full queue; insufficient funds; blocked exit; factory destruction; multiple queues | Passed exercised cost/queue/crew/blocked-exit cases |
| Selection and groups | click/drag/shift/groups; mixed army | dead/recycled entity; double click; modal input; command spam | Passed clean UI control assertions; recycled identity limited evidence |
| Movement and formations | open terrain; walls; narrow corridor; retreat | large armies; unreachable destination; clipping; rapid retarget | Failed spacing: 100 units share one final position |
| Combat and targeting | controlled DPS/TTK/range/counters | exact range; out of range; simultaneous lethal fire; air restrictions; empty ammo | Passed six independent counter/TTK cases plus inherited regressions |
| Defences | walls/turrets/AA and layered defence | power loss; ammo depletion; wall maze; unreachable enemy | Partial; real defenses, wall supply and AA tests; no maze tournament |
| Enemy waves and relays | timing; locked doctrine; actual spawn count | relay loss/power cut; spawn blocked; late-wave cap; impossible routes | Partial; timing/relay/composition tests; no exhaustive spawn traps |
| AI and strategies | infantry/armour/air/boom/defence/mixed strategies | kiting; economy raids; retreat; stalled economy; troop replacement | Partial; live raids observed, strategy/exploit sweep incomplete |
| Logistics | ammo manufacture → route → unit → shot | sever/recover; empty depot; exhausted unit; material conservation | Passed ammo/buffer/cut-path cases; fuel unavailable |
| Research and eras | all 12 live technologies; theory/prototype; era 0→1 | no power/lab/factory; duplicate request; lost facilities; parallel labs | Core integration passes; all-project UI progression in progress |
| Technology graph/science | live graph plus 200 design examples validated separately | cycles; bad refs; impossible unlocks; speculative labels | Passed 12 runtime graph and 200 separate design records |
| Persistence and replay | discover actual save UI and serialized formats | research/combat/queues during persistence; repeated load; replay equivalence | Campaign save/load unavailable; deterministic replay only |
| Pause/speed and transport | actual Godot controls and native parity | commands during modal; partial write; duplicate delivery; restart stale commands | Transport fixed; Godot pause/speed unavailable |
| UI and camera | all tabs/alerts/minimap; 1080p/1440p/4K/ultrawide | clipping; overlap; bounds; zoom; input through panels | Partial; four resolutions, GPU, picking and modal; scrolling defect open |
| Performance and scale | 100/1000/5000/10000 entities where feasible | tick percentiles; memory; dense combat; command/path cost; render frame times | Failed 5000/10000 real-time budget; 1000 sustained passed |
| Long-run and chaos | 30min/2h/8h accelerated active simulation | drift; bounded inventory; determinism; command storms; entity lifecycle | Passed two economy soaks and command storm; not continuous combat soak |
| Later eras and strategic layers | availability audit | not mark design-only content as runtime pass | Unavailable in primary runtime; design-only content audited |
| Network lockstep | existing peer/input/hash tests | malformed peer; duplicate frames; authority; transport availability | Inherited deterministic tests pass; malformed authority not proven |
