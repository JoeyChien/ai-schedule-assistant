require "test_helper"

class Schedules::HabitSchedulingServiceTest < ActiveSupport::TestCase
  test "schedules every pending habit into the free slots, in order" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal %w[閱讀 散步 英文 冥想], result.scheduled.map(&:title)
    assert_empty result.skipped
    assert_equal Time.zone.parse("2026-08-04T08:00"), result.scheduled.first.start_time
    assert_equal Time.zone.parse("2026-08-04T08:30"), result.scheduled.first.end_time
    assert result.scheduled.all?(&:persisted?)
    assert result.scheduled.all? { |s| s.source == "habit_auto" }
  end

  test "skips a habit that's already scheduled for that day" do
    Schedule.create!(title: "閱讀", start_time: Time.zone.parse("2026-08-04T09:00"), end_time: Time.zone.parse("2026-08-04T09:30"))
    calendar = FakeGoogleCalendarService.new
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal %w[散步 英文 冥想], result.scheduled.map(&:title)
    assert_equal [ { title: "閱讀", reason: "今天已經安排過了" } ], result.skipped
  end

  test "skips habits that don't fit in the remaining free slots" do
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [
      FakeGoogleCalendarService::FakeBusyPeriod.new(
        Time.zone.parse("2026-08-04T08:30"), Time.zone.parse("2026-08-04T22:00")
      )
    ]
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal %w[閱讀], result.scheduled.map(&:title)
    assert_equal [ { title: "散步", reason: "找不到空檔" }, { title: "英文", reason: "找不到空檔" }, { title: "冥想", reason: "找不到空檔" } ],
                 result.skipped
  end
end
