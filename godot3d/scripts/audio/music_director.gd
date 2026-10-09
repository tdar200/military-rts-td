extends RefCounted
## Kestrel music (kestrel-depth Task 30): which kind of music fits the moment, as plain calls with no engine in them. The
## game feeds update() every Kestrel frame with where the player is (on the title or deployed), the snapshot's winner and
## the seconds since the last shot the player could see; the answer is one of STATES. Combat starts on a shot within
## COMBAT_ENTER_S and ends only after COMBAT_HOLD_S of quiet, so a lull between volleys never flips the music back and
## forth. Victory and defeat are terminal: the scene reloads before another match.
##
## No music track exists yet. track_for answers "" for every state, and play is a no-op on "", so no player is ever
## created and nothing sounds. A track added later is a path in TRACKS; play then starts it on the Music bus, which the
## SFX director already ducks and the player's Music volume (Settings) already scales.

const STATES := ["menu", "calm", "combat", "victory", "defeat"]
const COMBAT_ENTER_S := 3.0  # a shot at most this many seconds ago starts combat
const COMBAT_HOLD_S := 8.0  # combat ends only after this many seconds without a shot
## state -> a res:// audio path. Empty: no music yet (owed to the user, see NEXT_STEPS.md).
const TRACKS := {}
const PLAYER_NAME := "Music"
const BUS := "Music"
const PLAYER := 0  # the snapshot's winner when the player wins

var state := "menu"
var _last_shot := -INF  # the time of the latest shot update() has heard of


## The state for this moment. ctx: on_title (bool, the title or picker is up), winner (int, the snapshot's winner: -1
## undecided, PLAYER the player, any other side the enemy) and recent_combat_s (float, seconds since the last shot the
## player could see; INF for none). `now` is the caller's clock in seconds.
func update(ctx: Dictionary, now: float) -> String:
	if state == "victory" or state == "defeat":
		return state
	var winner := int(ctx.get("winner", -1))
	if winner >= 0:
		state = "victory" if winner == PLAYER else "defeat"
		return state
	var recent := float(ctx.get("recent_combat_s", INF))
	if recent <= COMBAT_ENTER_S:
		_last_shot = maxf(_last_shot, now - recent)
	if bool(ctx.get("on_title", false)):
		state = "menu"
	elif recent <= COMBAT_ENTER_S:
		state = "combat"
	elif state == "combat" and now - _last_shot < COMBAT_HOLD_S:
		state = "combat"
	else:
		state = "calm"
	return state


## The track for a state: "" for every state until music exists.
func track_for(for_state: String) -> String:
	return String(TRACKS.get(for_state, ""))


## Starts `track` on the Music bus under `host` and returns the player; a no-op returning null on "" (every state today),
## so nothing is created and nothing sounds.
func play(track: String, host: Node) -> AudioStreamPlayer:
	if track == "" or host == null:
		return null
	var player := AudioStreamPlayer.new()
	player.name = PLAYER_NAME
	player.bus = BUS
	if ResourceLoader.exists(track):
		player.stream = load(track) as AudioStream
	host.add_child(player)
	if player.is_inside_tree() and player.stream != null:
		player.play()
	return player
