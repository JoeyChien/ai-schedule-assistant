require "test_helper"

class Schedules::UpdateServiceTest < ActiveSupport::TestCase
  test "update finds today's schedule by title and updates both calendar and DB" do
    today_schedule = Schedule.create!(
      title: "健身",
      start_time: Time.zone.now.change(hour: 17),
      end_time: Time.zone.now.change(hour: 18),
      source: "line",
      status: "confirmed",
      google_event_id: "existing-id"
    )
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(
      action: "UPDATE",
      title: "健身",
      start_time: Time.zone.now.change(hour: 19),
      end_time: Time.zone.now.change(hour: 20)
    )

    schedule = Schedules::UpdateService.new(calendar: calendar).update(intent)

    assert_equal today_schedule.id, schedule.id
    assert_equal 19, schedule.reload.start_time.hour
    assert_equal [ [ :update_event, "existing-id", { summary: "健身", start_time: intent.start_time, end_time: intent.end_time, location: nil } ] ],
                 calendar.calls
  end

  test "update raises NotFound when there is no matching schedule today" do
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(action: "UPDATE", title: "不存在", start_time: Time.zone.now)

    assert_raises(Schedules::Finder::NotFound) do
      Schedules::UpdateService.new(calendar: calendar).update(intent)
    end
  end
end
