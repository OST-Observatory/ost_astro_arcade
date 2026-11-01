## Language handling (autoload `I18n`). Strings live in res://locale/ui.csv (keys,de,en,es).
## Controls translate themselves; code uses tr("KEY").
extends Node

signal locale_changed(locale: String)

const NAMES := {"de": "Deutsch", "en": "English", "es": "Español"}

var locale := "de"


func _ready() -> void:
	set_locale(default_locale())


## The configured language; without one (tablet app) the system language, else English.
func default_locale() -> String:
	var code: String = Settings.get_value("general/default_locale")
	if code == "":
		code = OS.get_locale_language()
	return code if available().has(code) else "en"


func available() -> Array:
	return Settings.get_value("general/locales")


func set_locale(code: String) -> void:
	if not available().has(code):
		code = "en"
	locale = code
	TranslationServer.set_locale(code)
	locale_changed.emit(code)


func reset() -> void:
	if locale != default_locale():
		set_locale(default_locale())
