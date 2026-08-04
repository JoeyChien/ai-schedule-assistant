require "test_helper"

class Schedules::BulkScheduleServiceTest < ActiveSupport::TestCase
  # 固定在測試日期（2026-08-04）之前，這樣「今天不能排過去時間」的邏輯不會影響這些測試
  setup { travel_to(Time.zone.parse("2026-08-01T09:00:00+08:00")) }
  teardown { travel_back }

  test "schedules one occurrence per day, walking forward until it hits the requested count" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::BulkScheduleService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME", title: "閱讀", occurrences: 2, duration_minutes: 60,
      range_start: "2026-08-04", range_end: "2026-08-06"
    )

    result = service.call(intent)

    assert_equal 2, result.scheduled.size
    assert_equal 0, result.skipped
    assert_equal [ Date.new(2026, 8, 4), Date.new(2026, 8, 5) ], result.scheduled.map { |s| s.start_time.to_date }
    assert result.scheduled.all? { |s| s.title == "閱讀" && s.persisted? }
  end

  test "skips a day with no room and moves on to the next one" do
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [
      FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T22:00"))
    ]
    service = Schedules::BulkScheduleService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME", title: "閱讀", occurrences: 1, duration_minutes: 60,
      range_start: "2026-08-04", range_end: "2026-08-05"
    )

    result = service.call(intent)

    assert_equal 1, result.scheduled.size
    assert_equal Date.new(2026, 8, 5), result.scheduled.first.start_time.to_date
  end

  test "reports the remaining count as skipped when the range runs out before hitting the requested occurrences" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::BulkScheduleService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME", title: "閱讀", occurrences: 5, duration_minutes: 60,
      range_start: "2026-08-04", range_end: "2026-08-05"
    )

    result = service.call(intent)

    assert_equal 2, result.scheduled.size
    assert_equal 3, result.skipped
  end

  test "does not double-book a slot that's already taken by another schedule in the same batch" do
    Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T10:00"), end_time: Time.zone.parse("2026-08-05T22:00"))
    calendar = FakeGoogleCalendarService.new
    service = Schedules::BulkScheduleService.new(calendar: calendar)
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME", title: "閱讀", occurrences: 1, duration_minutes: 60,
      range_start: "2026-08-04", range_end: "2026-08-05"
    )

    result = service.call(intent)

    assert_equal 0, result.scheduled.size
    assert_equal 1, result.skipped
  end

  test "when the request comes in late in the day, skips today (no room left) and moves to the next day" do
    travel_to(Time.zone.parse("2026-08-04T22:00:00+08:00")) do
      calendar = FakeGoogleCalendarService.new
      service = Schedules::BulkScheduleService.new(calendar: calendar)
      intent = ParsedIntent.new(
        action: "FIND_FREE_TIME", title: "閱讀", occurrences: 2, duration_minutes: 60,
        range_start: "2026-08-04", range_end: "2026-08-09"
      )

      result = service.call(intent)

      assert_equal 2, result.scheduled.size
      assert_equal [ Date.new(2026, 8, 5), Date.new(2026, 8, 6) ], result.scheduled.map { |s| s.start_time.to_date }
      assert result.scheduled.none? { |s| s.start_time < Time.zone.now }, "must never schedule something in the past"
    end
  end
end
