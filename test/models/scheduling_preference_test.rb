require "test_helper"

class SchedulingPreferenceTest < ActiveSupport::TestCase
  test ".current creates a default row when none exists" do
    assert_equal 0, SchedulingPreference.count

    preference = SchedulingPreference.current

    assert_equal "10:00", preference.window_start
    assert_equal "22:00", preference.window_end
    assert_equal [ { "start" => "12:00", "end" => "13:00" }, { "start" => "18:00", "end" => "19:00" } ], preference.excluded_ranges
  end

  test ".current returns the existing row instead of creating another one" do
    existing = SchedulingPreference.current
    existing.update!(window_start: "09:00")

    assert_equal existing.id, SchedulingPreference.current.id
    assert_equal "09:00", SchedulingPreference.current.window_start
    assert_equal 1, SchedulingPreference.count
  end

  test "is invalid when window_start/window_end aren't HH:MM" do
    preference = SchedulingPreference.current
    preference.window_start = "10am"

    assert_not preference.valid?
    assert_includes preference.errors[:window_start].join, "HH:MM"
  end

  test "is invalid when excluded_ranges isn't an array of { start, end }" do
    preference = SchedulingPreference.current
    preference.excluded_ranges = [ { "start" => "12:00" } ]

    assert_not preference.valid?
    assert_includes preference.errors[:excluded_ranges].join, "格式"
  end

  test "an empty excluded_ranges array is valid (no breaks configured)" do
    preference = SchedulingPreference.current
    preference.excluded_ranges = []

    assert preference.valid?
  end
end
