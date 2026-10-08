## The same three actions at the end of every game, always in the same order and look:
## play again (accent), change difficulty (back to the start screen), back to the hub.
## Stacked for narrow side panels, in a row for full-screen results.
class_name ResultActions
extends BoxContainer


static func make(again_key: String, again_icon: String, on_again: Callable, width: float, stacked := true) -> ResultActions:
	var r := ResultActions.new()
	r.vertical = stacked
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 18 if stacked else 28)
	var w := width if stacked else (width - 56.0) / 3.0
	var again := BigButton.make(again_key, again_icon, true, int(w))
	again.pressed.connect(on_again)
	r.add_child(again)
	r.add_child(Router.restart_button(int(w)))
	var home := BigButton.make("BACK_TO_HUB", "home", false, int(w))
	home.pressed.connect(func(): Router.go_home("home"))
	r.add_child(home)
	return r
