## Sound (autoload `Audio`). Buses: Master > Music, SFX, UI.
## Cues play res://assets/audio/<cue>.ogg if it exists, otherwise a small synthesized
## placeholder sound, so every interaction has feedback before real assets arrive.
## Muted by default until speakers are installed (admin menu: audio/muted).
extends Node

const BUSES := ["Music", "SFX", "UI"]
const MIX_RATE := 44100

var _players: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	apply_settings()
	Settings.changed.connect(func(key): if key.begins_with("audio/"): apply_settings())


func apply_settings() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, Settings.get_value("audio/muted"))
	AudioServer.set_bus_volume_db(master, Settings.get_value("audio/master_db"))


## cue: "tap", "back", "success", "fail", "whoosh", "tick", or a file name in res://assets/audio/.
func play(cue: String, bus := "UI", pitch := 1.0, volume_db := 0.0) -> void:
	var stream := _stream_for(cue)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.bus = bus
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			return


func _stream_for(cue: String) -> AudioStream:
	if _cache.has(cue):
		return _cache[cue]
	var path := "res://assets/audio/%s.ogg" % cue
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else _synth(cue)
	_cache[cue] = s
	return s


func _synth(cue: String) -> AudioStream:
	match cue:
		"tap": return _tone([[880.0, 0.05]], 0.25)
		"back": return _tone([[660.0, 0.05], [440.0, 0.06]], 0.22)
		"tick": return _tone([[1200.0, 0.025]], 0.15)
		"success": return _tone([[523.3, 0.09], [659.3, 0.09], [784.0, 0.09], [1046.5, 0.22]], 0.25)
		"fail": return _tone([[300.0, 0.12], [220.0, 0.2]], 0.25)
		"whoosh": return _noise_sweep(0.35)
	return null


## Sequence of [frequency_hz, seconds] notes, soft sine with short attack/decay.
static func _tone(notes: Array, amp: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var count := int(MIX_RATE * float(n[1]))
		for i in count:
			var t := float(i) / MIX_RATE
			var env := minf(1.0, i / (MIX_RATE * 0.004)) * exp(-3.0 * float(i) / count)
			var v := sin(TAU * freq * t) * 0.8 + sin(TAU * freq * 2.0 * t) * 0.2
			data.append_array(_s16(v * env * amp))
	return _wav(data)


static func _noise_sweep(seconds: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var count := int(MIX_RATE * seconds)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var x := float(i) / count
		var cutoff := lerpf(0.02, 0.35, sin(PI * x))
		lp += (rng.randf_range(-1, 1) - lp) * cutoff
		data.append_array(_s16(lp * sin(PI * x) * 0.5))
	return _wav(data)


static func _s16(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_s16(0, int(clampf(v, -1.0, 1.0) * 32767.0))
	return b


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
