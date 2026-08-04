require "test_helper"

class Schedules::CreationServiceTest < ActiveSupport::TestCase
  test "create persists a Schedule with the google_event_id returned by the calendar" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "CREATE",
      title: "健身",
      start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"),
      end_time: Time.zone.parse("2026-08-05T18:00:00+08:00")
    )

    schedule = service.create(intent)

    assert schedule.persisted?
    assert_equal "健身", schedule.title
    assert_equal "fake-event-1", schedule.google_event_id
    assert_equal [ [ :create_event, { summary: "健身", start_time: intent.start_time, end_time: intent.end_time, location: nil } ] ],
                 calendar.calls
  end
end
