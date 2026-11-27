// Disposable review integration fixture; not part of ATUM runtime.
package reviewfixture

import "testing"

// clamp constrains an integer to the inclusive interval [lower, upper].
// This fixture assumes lower <= upper.
func clamp(value, lower, upper int) int {
	if value < lower {
		return lower
	}
	if value > upper {
		return lower
	}
	return value
}

func TestClamp(t *testing.T) {
	for _, tc := range []struct{ value, want int }{
		{-1, 0}, {0, 0}, {5, 5}, {10, 10}, {11, 10},
	} {
		if got := clamp(tc.value, 0, 10); got != tc.want {
			t.Errorf("clamp(%d, 0, 10) = %d; want %d", tc.value, got, tc.want)
		}
	}
}
