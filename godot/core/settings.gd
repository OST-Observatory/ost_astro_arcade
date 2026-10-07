## Kiosk configuration (autoload `Settings`).
## Defaults live here; overrides are written by the admin menu to <data_dir>/settings.cfg.
## The data directory comes from `-- --data-dir=<path>`, then $OST_DATA_DIR, then user://.
extends Node

signal changed(key: String)

const DEFAULTS := {
	"general/default_locale": "de",
	"general/locales": ["de", "en", "es"],
	"general/show_upcoming": true,
	"kiosk/idle_warning_sec": 120.0,
	"kiosk/idle_countdown_sec": 10.0,
	"kiosk/hub_attract_sec": 60.0,
	"kiosk/hub_reset_sec": 120.0,
	"kiosk/external_max_sec": 1200.0,
	"kiosk/admin_pin_sha256": "",  # empty -> DEFAULT_PIN
	"audio/muted": true,
	"audio/master_db": -6.0,
	"display/show_fps": false,
	"display/quality_3d": "high",   # high | medium | low (FSR upscaling, MSAA, effects)
	"games/disabled": [],
	"external/nbody_path": "/opt/ost/external/nbody/nbody_dynamics",
	"site/name": "OST, Universität Potsdam (Golm)",
	"site/lat_deg": 52.4092,
	"site/lon_deg": 12.9733,
	"site/elevation_m": 80.0,
}
const DEFAULT_PIN := "1234"

var data_dir := "user://"
var _cfg := ConfigFile.new()


func _enter_tree() -> void:
	data_dir = _resolve_data_dir()
	DirAccess.make_dir_recursive_absolute(data_dir)
	_cfg.load(_cfg_path())


func _resolve_data_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data-dir="):
			return arg.trim_prefix("--data-dir=")
	var env := OS.get_environment("OST_DATA_DIR")
	return env if env != "" else "user://"


func _cfg_path() -> String:
	return data_dir.path_join("settings.cfg")


func data_path(file_name: String) -> String:
	return data_dir.path_join(file_name)


func get_value(key: String) -> Variant:
	var parts := key.split("/", true, 1)
	return _cfg.get_value(parts[0], parts[1], DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	var parts := key.split("/", true, 1)
	_cfg.set_value(parts[0], parts[1], value)
	_cfg.save(_cfg_path())
	changed.emit(key)


func is_game_enabled(game_id: String) -> bool:
	return not (get_value("games/disabled") as Array).has(game_id)


func check_pin(pin: String) -> bool:
	var stored: String = get_value("kiosk/admin_pin_sha256")
	if stored == "":
		return pin == DEFAULT_PIN
	return pin.sha256_text() == stored


func uses_default_pin() -> bool:
	return get_value("kiosk/admin_pin_sha256") == ""


func set_pin(pin: String) -> void:
	set_value("kiosk/admin_pin_sha256", pin.sha256_text())


## 3D quality preset: [render scale (FSR below 1), MSAA, galaxy stars, SSAO].
const QUALITY_3D := {
	"high": [1.0, Viewport.MSAA_4X, 200000, true],
	"medium": [0.77, Viewport.MSAA_2X, 150000, true],
	"low": [0.59, Viewport.MSAA_DISABLED, 100000, false],
}


func quality_3d() -> Array:
	return QUALITY_3D.get(str(get_value("display/quality_3d")), QUALITY_3D.high)


## Applies the 3D quality preset to a viewport that renders a 3D scene.
func apply_3d(vp: Viewport) -> void:
	var q := quality_3d()
	vp.msaa_3d = q[1]
	vp.scaling_3d_scale = q[0]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q[0] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR

