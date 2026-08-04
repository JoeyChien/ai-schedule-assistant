require "test_helper"

class Schedules::SlotAllocatorTest < ActiveSupport::TestCase
  # 固定在測試日期（2026-08-04）之前，這樣「今天不能排過去時間」的邏輯不會影響這些測試
  setup { travel_to(Time.zone.parse("2026-08-01T09:00:00+08:00")) }
  teardown { travel_back }

  def build_allocator(busy_periods: [])
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = busy_periods
    Schedules::SlotAllocator.new(free_slot_finder: Schedules::FreeSlotFinder.new(calendar: calendar))
  end

  def preference(window_start: "10:00", window_end: "22:00", excluded_ranges: [ { "start" => "12:00", "end" => "13:00" }, { "start" => "18:00", "end" => "19:00" } ])
    SchedulingPreference.new(window_start: window_start, window_end: window_end, excluded_ranges: excluded_ranges)
  end

  test "with no preferred_period, returns the first free slot in the whole window" do
    allocator = build_allocator

    slot = allocator.find_slot(date: Date.new(2026, 8, 4), duration: 30.minutes, preference: preference)

    assert_equal Time.zone.parse("2026-08-04T10:00"), slot.begin
  end

  test "with a preferred_period, prioritizes a slot inside that period" do
    allocator = build_allocator

    slot = allocator.find_slot(date: Date.new(2026, 8, 4), duration: 30.minutes, preference: preference, preferred_period: "evening")

    # 晚上是 18:00-22:00，扣掉晚餐 18:00-19:00 後第一個空檔是 19:00
    assert_equal Time.zone.parse("2026-08-04T19:00"), slot.begin
  end

  test "falls back to the whole window when the preferred period has no room" do
    allocator = build_allocator(busy_periods: [
      FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T18:00"), Time.zone.parse("2026-08-04T22:00"))
    ])

    slot = allocator.find_slot(date: Date.new(2026, 8, 4), duration: 30.minutes, preference: preference, preferred_period: "evening")

    assert_equal Time.zone.parse("2026-08-04T10:00"), slot.begin
  end

  test "returns nil when the whole window is full" do
    allocator = build_allocator(busy_periods: [
      FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T22:00"))
    ])

    assert_nil allocator.find_slot(date: Date.new(2026, 8, 4), duration: 15.minutes, preference: preference)
  end

  test "for today, never returns a slot starting before now + 1 hour, even inside the preferred period" do
    travel_to(Time.zone.parse("2026-08-04T15:20:00+08:00")) do
      allocator = build_allocator

      slot = allocator.find_slot(date: Date.current, duration: 30.minutes, preference: preference, preferred_period: "afternoon")

      assert_equal Time.zone.parse("2026-08-04T16:20"), slot.begin
    end
  end
end
