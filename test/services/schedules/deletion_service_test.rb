require "test_helper"

class Schedules::DeletionServiceTest < ActiveSupport::TestCase
  test "delete removes today's matching schedule and the calendar event" do
    today_schedule = Schedule.create!(
      title: "健身",
      start_time: Time.zone.now.change(hour: 17),
      end_time: Time.zone.now.change(hour: 18),
      source: "line",
      status: "confirmed",
      google_event_id: "existing-id"
    )
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(action: "DELETE", title: "健身")

    Schedules::DeletionService.new(calendar: calendar).delete(intent)

    assert_not Schedule.exists?(today_schedule.id)
    assert_equal [ [ :delete_event, "existing-id" ] ], calendar.calls
  end

  test "delete raises NotFound when there is no matching schedule today" do
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(action: "DELETE", title: "不存在")

    assert_raises(Schedules::Finder::NotFound) do
      Schedules::DeletionService.new(calendar: calendar).delete(intent)
    end
  end
end
