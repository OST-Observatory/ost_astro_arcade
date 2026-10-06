## Blocks offensive free-text names (de/en/es) on the unattended kiosk.
## Text is normalised (lower case, leetspeak, accents, repeated letters) and checked
## against stems in res://core/data/blocked_words.txt (substring match) and
## whole-word codes (e.g. neo-Nazi number codes). False positives are acceptable:
## the player simply picks another name, and admins can delete entries anyway.
class_name WordFilter
extends RefCounted

const LIST_PATH := "res://core/data/blocked_words.txt"
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s", "!": "i", "€": "e"}
const ACCENTS := {"ä": "a", "ö": "o", "ü": "u", "ß": "ss", "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ñ": "n", "à": "a", "è": "e"}

static var _stems: PackedStringArray = []
static var _words: PackedStringArray = []


static func _ensure_loaded() -> void:
	if not _stems.is_empty():
		return
	var f := FileAccess.open(LIST_PATH, FileAccess.READ)
	if f == null:
		push_error("WordFilter: missing " + LIST_PATH)
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges().to_lower()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("="):
			_words.append(line.substr(1))
		else:
			_stems.append(_squash(line))


## Lower case, accents removed, leetspeak mapped, only letters kept, repeats collapsed.
static func normalize(text: String) -> String:
	var s := text.to_lower()
	var out := ""
	for ch in s:
		ch = ACCENTS.get(ch, ch)
		ch = LEET.get(ch, ch)
		out += ch
	return _squash(out)


static func _squash(s: String) -> String:
	var out := ""
	var last := ""
	for ch in s:
		if ch < "a" or ch > "z":
			continue
		if ch != last:
			out += ch
		last = ch
	return out


static func is_allowed(text: String) -> bool:
	_ensure_loaded()
	var norm := normalize(text)
	for stem in _stems:
		if stem != "" and norm.contains(stem):
			return false
	var tokens := text.to_lower().replace("-", " ").replace("_", " ").replace(".", " ").split(" ", false)
	for t in tokens:
		if _words.has(t):
			return false
	return true
