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

  test "create raises a conflict error and doesn't touch Google Calendar when the time overlaps an existing schedule" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))
    calendar = FakeGoogleCalendarService.new
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "CREATE",
      title: "做伸展",
      start_time: Time.zone.parse("2026-08-04T19:00"),
      end_time: Time.zone.parse("2026-08-04T19:30")
    )

    error = assert_raises(Schedules::ConflictChecker::ConflictError) { service.create(intent) }

    assert_includes error.message, "看中醫"
    assert_empty calendar.calls
  end

  test "create auto-schedules into a free slot when time_specified is false, avoiding an existing Google Calendar event and preferring the requested period" do
    # 模擬「看中醫」已經在 Google Calendar 佔用 19:00-20:00（就跟真實情境一樣，先前建立時已經寫進 Google Calendar）
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [ FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T19:00"), Time.zone.parse("2026-08-04T20:00")) ]
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "CREATE",
      title: "做伸展",
      time_specified: false,
      duration_minutes: 30,
      date: "2026-08-04",
      preferred_period: "evening"
    )

    schedule = service.create(intent)

    # 晚上時段扣掉晚餐(18-19)跟看中醫(19-20)後，第一個排得下的空檔是 20:00
    assert_equal Time.zone.parse("2026-08-04T20:00"), schedule.start_time
    assert_equal Time.zone.parse("2026-08-04T20:30"), schedule.end_time
    assert_includes calendar.calls, [ :create_event, { summary: "做伸展", start_time: schedule.start_time, end_time: schedule.end_time, location: nil } ]
  end

  test "create falls back to the full scheduling window when the preferred period has no room" do
    calendar = FakeGoogleCalendarService.new
    # 早上時段（交集後是 10:00-12:00）整段都被佔滿
    calendar.busy_periods = [ FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T12:00")) ]
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "CREATE", title: "閱讀", time_specified: false, duration_minutes: 30, date: "2026-08-04", preferred_period: "morning"
    )

    schedule = service.create(intent)

    assert_equal Time.zone.parse("2026-08-04T13:00"), schedule.start_time
  end

  test "create with no preferred_period picks the first available slot in the whole window" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(action: "CREATE", title: "散步", time_specified: false, duration_minutes: 30, date: "2026-08-04")

    schedule = service.create(intent)

    assert_equal Time.zone.parse("2026-08-04T10:00"), schedule.start_time
  end

  test "create raises NoFreeSlotError when the whole scheduling window is full" do
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [ FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T22:00")) ]
    service = Schedules::CreationService.new(calendar: calendar)
    intent = ParsedIntent.new(action: "CREATE", title: "冥想", time_specified: false, duration_minutes: 15, date: "2026-08-04")

    error = assert_raises(Schedules::CreationService::NoFreeSlotError) { service.create(intent) }

    assert_includes error.message, "冥想"
  end
end
