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

  test "find_free_busy calls the gem's real query_freebusy method and returns the busy periods" do
    busy = Google::Apis::CalendarV3::TimePeriod.new(start: Time.zone.parse("2026-08-04T19:00"), end: Time.zone.parse("2026-08-04T20:00"))
    response = Google::Apis::CalendarV3::FreeBusyResponse.new(
      calendars: { "primary" => Google::Apis::CalendarV3::FreeBusyCalendar.new(busy: [ busy ]) }
    )
    fake_client = Object.new
    fake_client.define_singleton_method(:authorization=) { |*| }
    fake_client.define_singleton_method(:query_freebusy) { |*| response }

    result = GoogleCalendarService.new(client: fake_client).find_free_busy(
      Time.zone.parse("2026-08-04T00:00"), Time.zone.parse("2026-08-04T23:59")
    )

    assert_equal [ busy ], result
  end
end
