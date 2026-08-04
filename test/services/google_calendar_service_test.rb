require "test_helper"

class GoogleCalendarServiceTest < ActiveSupport::TestCase
  test "build_event serializes start/end as RFC3339 (Google rejects the default TimeWithZone#to_s format)" do
    start_time = Time.zone.parse("2026-08-05T17:00:00+08:00")
    end_time = Time.zone.parse("2026-08-05T18:00:00+08:00")

    event = GoogleCalendarService.new.send(
      :build_event, summary: "看書", start_time: start_time, end_time: end_time, location: nil
    )

    payload = JSON.parse(event.to_json)

    assert_equal "2026-08-05T17:00:00.000+08:00", payload.dig("start", "dateTime")
    assert_equal "2026-08-05T18:00:00.000+08:00", payload.dig("end", "dateTime")
  end
end
