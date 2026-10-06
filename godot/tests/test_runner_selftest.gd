extends TestCase


func test_assertions_record_failures() -> void:
	var inner := TestCase.new()
	inner._set_current("inner")
	inner.assert_eq(1, 1)
	inner.assert_almost(1.0, 1.05, 0.1)
	assert_true(inner.failures.is_empty(), "passing assertions must not fail")
	inner.assert_eq(1, 2)
	inner.assert_true(false)
	assert_eq(inner.failures.size(), 2, "failing assertions")
