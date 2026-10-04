extends SceneTree
var game: Node3D
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 root.size=Vector2i(1920,1080)
 game=load("res://main.tscn").instantiate()
 root.add_child(game)
 await create_timer(2).timeout
 for button in game.find_children("*","Button",true,false):
  if button.text.to_upper()=="DEPLOY FORCES":button.pressed.emit()
 await create_timer(2).timeout
 var light: DirectionalLight3D=game.find_children("*","DirectionalLight3D",true,false)[0]
 var report: Array=[]
 for mode in [2,1,0]:
  light.directional_shadow_mode=mode
  for i in range(30):await process_frame
  var samples: Array=[]
  var last=Time.get_ticks_usec()
  for i in range(120):
   await process_frame
   var now=Time.get_ticks_usec()
   samples.append(float(now-last)/1000.0);last=now
  samples.sort()
  report.append({"shadow_mode":mode,"p50_ms":samples[60],"p95_ms":samples[114],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
 print("QA_RENDER "+JSON.stringify(report))
 quit()
