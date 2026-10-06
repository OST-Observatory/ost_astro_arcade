## Base class for unit tests. Every method starting with `test_` is run by run_tests.gd.
class_name TestCase
extends RefCounted

var failures: PackedStringArray = []
var _current := ""


func _set_current(test_name: String) -> void:
	_current = test_name


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		_fail(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		_fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if actual != expected:
		_fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_almost(actual: float, expected: float, tol: float, msg := "") -> void:
	if absf(actual - expected) > tol:
		_fail("%s expected %f ± %g, got %f" % [msg, expected, tol, actual])
