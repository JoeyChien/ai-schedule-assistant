require "test_helper"

class Schedules::HabitSchedulingServiceTest < ActiveSupport::TestCase
  # 固定在測試日期（2026-08-04）之前，這樣「今天不能排過去時間」的邏輯不會影響這些測試
  # （這個 Job 實際上是每天 07:00 觸發，當天一早排，本來就不會撞到這個問題）
  setup { travel_to(Time.zone.parse("2026-08-01T09:00:00+08:00")) }
  teardown { travel_back }

  test "schedules every pending habit into the free slots, in order" do
    calendar = FakeGoogleCalendarService.new
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal %w[閱讀 散步 英文 冥想], result.scheduled.map(&:title)
    assert_empty result.skipped
    # 預設可排程時間是 10:00-22:00，所以第一個空檔從 10:00 開始（而不是 08:00）
    assert_equal Time.zone.parse("2026-08-04T10:00"), result.scheduled.first.start_time
    assert_equal Time.zone.parse("2026-08-04T10:30"), result.scheduled.first.end_time
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
        Time.zone.parse("2026-08-04T10:30"), Time.zone.parse("2026-08-04T22:00")
      )
    ]
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal %w[閱讀], result.scheduled.map(&:title)
    assert_equal [ { title: "散步", reason: "找不到空檔" }, { title: "英文", reason: "找不到空檔" }, { title: "冥想", reason: "找不到空檔" } ],
                 result.skipped
  end

  test "respects SchedulingPreference's excluded ranges (e.g. lunch break), not just Google Calendar busy periods" do
    SchedulingPreference.current.update!(window_start: "11:30", window_end: "22:00")
    calendar = FakeGoogleCalendarService.new
    service = Schedules::HabitSchedulingService.new(calendar: calendar)

    result = service.call(date: Date.new(2026, 8, 4))

    assert_equal 4, result.scheduled.size
    assert_equal Time.zone.parse("2026-08-04T11:30"), result.scheduled.first.start_time

    result.scheduled.each do |schedule|
      in_lunch_break = schedule.end_time > Time.zone.parse("2026-08-04T12:00") && schedule.start_time < Time.zone.parse("2026-08-04T13:00")
      assert_not in_lunch_break, "#{schedule.title} (#{schedule.start_time}-#{schedule.end_time}) overlaps the lunch break"
    end
  end
end
