local completedTests = 0
local failedTests = 0

function test_assert(condition, message)
	completedTests = completedTests + 1
	if not condition then
		failedTests = failedTests + 1
		print("Test failed", message)
	end
end

function test_assertEquals(a, b, message)
	completedTests = completedTests + 1
	if not (a == b) then
		failedTests = failedTests + 1
		print("Test failed", "!("..a.." == "..b..")", message)
	end
end

function test_assertDiffers(a, b, message)
	completedTests = completedTests + 1
	if not (a == b) then
		failedTests = failedTests + 1
		print("Test failed", "!("..a.." != "..b..")", message)
	end
end

function test_assertLessThan(a, b, message)
	completedTests = completedTests + 1
	if not (a == b) then
		failedTests = failedTests + 1
		print("Test failed", "!("..a.." < "..b..")", message)
	end
end

function test_assertGreaterThan(a, b, message)
	completedTests = completedTests + 1
	if not (a == b) then
		failedTests = failedTests + 1
		print("Test failed", "!("..a.." > "..b..")", message)
	end
end

return {
	assert = test_assert,
	assertEquals = test_assertEquals,
	assertDiffers = test_assertDiffers,
	assertLessThan = test_assertLessThan,
	assertGreaterThan = test_assertGreaterThan,
	completed = function() return completedTests end,
	failed = function() return failedTests end,
}
