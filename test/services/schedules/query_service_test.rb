require "test_helper"

class Schedules::QueryServiceTest < ActiveSupport::TestCase
  test "call returns schedules within the parsed intent's query range, ordered by start_time" do
    later = Schedule.create!(title: "英文", start_time: Time.zone.parse("2026-08-04T20:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T20:30:00+08:00"))
    earlier = Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T17:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T18:00:00+08:00"))
    Schedule.create!(title: "明天的行程", start_time: Time.zone.parse("2026-08-05T09:00:00+08:00"), end_time: Time.zone.parse("2026-08-05T10:00:00+08:00"))

    intent = ParsedIntent.new(action: "QUERY", start_time: Time.zone.parse("2026-08-04T00:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T23:59:59+08:00"))

    result = Schedules::QueryService.new.call(intent)

    assert_equal [ earlier, later ], result.to_a
  end

  test "call returns an empty relation when nothing is scheduled in range" do
    intent = ParsedIntent.new(action: "QUERY", start_time: Time.zone.parse("2026-08-04T00:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T23:59:59+08:00"))

    result = Schedules::QueryService.new.call(intent)

    assert_empty result
  end
end
