## Generates friendly, grammatically correct player names such as
## "Mutiger Komet 42", "Brave Comet 42", "Cometa Valiente 42".
class_name NameGenerator
extends RefCounted

# German: adjective stems take the strong ending for the noun gender (m -er, f -e, n -es).
const DE_ADJ := ["Mutig", "Funkelnd", "Flink", "Neugierig", "Kühn", "Leuchtend", "Schlau",
	"Wild", "Stolz", "Strahlend", "Kosmisch", "Fröhlich", "Schnell", "Tapfer", "Glänzend"]
const DE_NOUN := [["Komet", "m"], ["Nova", "f"], ["Quasar", "m"], ["Pulsar", "m"],
	["Meteor", "m"], ["Galaxie", "f"], ["Supernova", "f"], ["Nebel", "m"], ["Mond", "m"],
	["Sonne", "f"], ["Rakete", "f"], ["Teleskop", "n"], ["Polarlicht", "n"], ["Sternchen", "n"],
	["Planet", "m"], ["Asteroid", "m"]]
const DE_END := {"m": "er", "f": "e", "n": "es"}

const EN_ADJ := ["Brave", "Sparkling", "Swift", "Curious", "Bold", "Shining", "Clever",
	"Wild", "Proud", "Radiant", "Cosmic", "Happy", "Speedy", "Daring", "Glowing"]
const EN_NOUN := ["Comet", "Nova", "Quasar", "Pulsar", "Meteor", "Galaxy", "Supernova",
	"Nebula", "Moon", "Sun", "Rocket", "Telescope", "Aurora", "Star", "Planet", "Asteroid"]

# Spanish: noun first, adjective agrees in gender ([masc, fem]).
const ES_ADJ := [["Valiente", "Valiente"], ["Brillante", "Brillante"], ["Veloz", "Veloz"],
	["Curioso", "Curiosa"], ["Audaz", "Audaz"], ["Radiante", "Radiante"], ["Listo", "Lista"],
	["Salvaje", "Salvaje"], ["Cósmico", "Cósmica"], ["Alegre", "Alegre"], ["Rápido", "Rápida"],
	["Atrevido", "Atrevida"], ["Luminoso", "Luminosa"]]
const ES_NOUN := [["Cometa", "m"], ["Nova", "f"], ["Quásar", "m"], ["Púlsar", "m"],
	["Meteoro", "m"], ["Galaxia", "f"], ["Supernova", "f"], ["Nebulosa", "f"], ["Luna", "f"],
	["Estrella", "f"], ["Cohete", "m"], ["Telescopio", "m"], ["Planeta", "m"], ["Asteroide", "m"]]


static func generate(locale: String, rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var num := rng.randi_range(1, 98)
	if num == 88:  # neo-Nazi code, never generate it
		num = 99
	match locale.substr(0, 2):
		"de":
			var noun: Array = DE_NOUN[rng.randi() % DE_NOUN.size()]
			var adj: String = DE_ADJ[rng.randi() % DE_ADJ.size()]
			return "%s%s %s %d" % [adj, DE_END[noun[1]], noun[0], num]
		"es":
			var noun: Array = ES_NOUN[rng.randi() % ES_NOUN.size()]
			var adj: Array = ES_ADJ[rng.randi() % ES_ADJ.size()]
			return "%s %s %d" % [noun[0], adj[0] if noun[1] == "m" else adj[1], num]
		_:
			return "%s %s %d" % [EN_ADJ[rng.randi() % EN_ADJ.size()], EN_NOUN[rng.randi() % EN_NOUN.size()], num]
