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

  test "update raises a conflict error and doesn't touch Google Calendar when the new time overlaps another schedule" do
    Schedule.create!(title: "健身", start_time: Time.zone.now.change(hour: 17), end_time: Time.zone.now.change(hour: 18), google_event_id: "gym-id")
    Schedule.create!(title: "看中醫", start_time: Time.zone.now.change(hour: 19), end_time: Time.zone.now.change(hour: 19, min: 30), google_event_id: "doctor-id")
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(action: "UPDATE", title: "健身", start_time: Time.zone.now.change(hour: 19), end_time: Time.zone.now.change(hour: 20))

    error = assert_raises(Schedules::ConflictChecker::ConflictError) do
      Schedules::UpdateService.new(calendar: calendar).update(intent)
    end

    assert_includes error.message, "看中醫"
    assert_empty calendar.calls
  end

  test "update does not treat the schedule's own current slot as a conflict" do
    today_schedule = Schedule.create!(title: "健身", start_time: Time.zone.now.change(hour: 17), end_time: Time.zone.now.change(hour: 18), google_event_id: "gym-id")
    calendar = FakeGoogleCalendarService.new
    intent = ParsedIntent.new(action: "UPDATE", title: "健身", start_time: Time.zone.now.change(hour: 17, min: 30), end_time: Time.zone.now.change(hour: 18, min: 30))

    schedule = Schedules::UpdateService.new(calendar: calendar).update(intent)

    assert_equal today_schedule.id, schedule.id
  end
end
