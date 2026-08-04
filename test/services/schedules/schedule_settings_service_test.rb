require "test_helper"

class Schedules::ScheduleSettingsServiceTest < ActiveSupport::TestCase
  test "update overwrites window_start/window_end/excluded_ranges from the parsed intent" do
    intent = ParsedIntent.new(
      action: "UPDATE_SCHEDULE_SETTINGS",
      window_start: "09:00",
      window_end: "21:00",
      excluded_ranges: [ { "start" => "12:30", "end" => "13:30" } ]
    )

    preference = Schedules::ScheduleSettingsService.new.update(intent)

    assert_equal "09:00", preference.window_start
    assert_equal "21:00", preference.window_end
    assert_equal [ { "start" => "12:30", "end" => "13:30" } ], preference.excluded_ranges
    assert_equal preference.attributes, SchedulingPreference.current.attributes
  end

  test "update keeps the existing value for any field the intent leaves blank" do
    SchedulingPreference.current.update!(window_start: "08:00", window_end: "23:00")
    intent = ParsedIntent.new(action: "UPDATE_SCHEDULE_SETTINGS", window_start: "", window_end: nil, excluded_ranges: nil)

    preference = Schedules::ScheduleSettingsService.new.update(intent)

    assert_equal "08:00", preference.window_start
    assert_equal "23:00", preference.window_end
  end

  test "update raises InvalidSettingsError when the new value fails validation" do
    intent = ParsedIntent.new(action: "UPDATE_SCHEDULE_SETTINGS", window_start: "not-a-time")

    assert_raises(Schedules::ScheduleSettingsService::InvalidSettingsError) do
      Schedules::ScheduleSettingsService.new.update(intent)
    end
  end
end
