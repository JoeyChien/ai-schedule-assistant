require "test_helper"

class Schedules::FreeSlotFinderTest < ActiveSupport::TestCase
  # 用一個明確早於下面測試日期的「現在」，這樣所測的日期都還是未來，不會被「今天不能排過去時間」的邏輯影響
  def before_test_dates
    travel_to(Time.zone.parse("2026-08-01T09:00:00+08:00")) { yield }
  end

  test "free_slots returns the whole window when there is nothing busy" do
    before_test_dates do
      calendar = FakeGoogleCalendarService.new
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(date: Date.new(2026, 8, 4), window_start: "08:00", window_end: "10:00")

      assert_equal [ Time.zone.parse("2026-08-04T08:00")...Time.zone.parse("2026-08-04T10:00") ], slots
    end
  end

  test "free_slots subtracts busy periods from the window" do
    before_test_dates do
      calendar = FakeGoogleCalendarService.new
      calendar.busy_periods = [
        FakeGoogleCalendarService::FakeBusyPeriod.new(
          Time.zone.parse("2026-08-04T09:00"), Time.zone.parse("2026-08-04T09:30")
        )
      ]
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(date: Date.new(2026, 8, 4), window_start: "08:00", window_end: "10:00")

      assert_equal [
        Time.zone.parse("2026-08-04T08:00")...Time.zone.parse("2026-08-04T09:00"),
        Time.zone.parse("2026-08-04T09:30")...Time.zone.parse("2026-08-04T10:00")
      ], slots
    end
  end

  test "free_slots also subtracts the given excluded_ranges (e.g. lunch/dinner breaks)" do
    before_test_dates do
      calendar = FakeGoogleCalendarService.new
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(
        date: Date.new(2026, 8, 4),
        window_start: "10:00",
        window_end: "22:00",
        excluded_ranges: [ { "start" => "12:00", "end" => "13:00" }, { "start" => "18:00", "end" => "19:00" } ]
      )

      assert_equal [
        Time.zone.parse("2026-08-04T10:00")...Time.zone.parse("2026-08-04T12:00"),
        Time.zone.parse("2026-08-04T13:00")...Time.zone.parse("2026-08-04T18:00"),
        Time.zone.parse("2026-08-04T19:00")...Time.zone.parse("2026-08-04T22:00")
      ], slots
    end
  end

  test "free_slots accepts excluded_ranges with symbol keys too" do
    before_test_dates do
      calendar = FakeGoogleCalendarService.new
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(
        date: Date.new(2026, 8, 4),
        window_start: "10:00",
        window_end: "12:00",
        excluded_ranges: [ { start: "11:00", end: "11:30" } ]
      )

      assert_equal [
        Time.zone.parse("2026-08-04T10:00")...Time.zone.parse("2026-08-04T11:00"),
        Time.zone.parse("2026-08-04T11:30")...Time.zone.parse("2026-08-04T12:00")
      ], slots
    end
  end

  test "free_slots returns nothing when a busy period covers the whole window" do
    before_test_dates do
      calendar = FakeGoogleCalendarService.new
      calendar.busy_periods = [
        FakeGoogleCalendarService::FakeBusyPeriod.new(
          Time.zone.parse("2026-08-04T07:00"), Time.zone.parse("2026-08-04T11:00")
        )
      ]
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(date: Date.new(2026, 8, 4), window_start: "08:00", window_end: "10:00")

      assert_empty slots
    end
  end

  test "free_slots never returns a slot that's already in the past" do
    assert_empty Schedules::FreeSlotFinder.new(calendar: FakeGoogleCalendarService.new).free_slots(date: Date.new(2026, 8, 3), window_start: "08:00", window_end: "22:00")
  end

  test "for today, free_slots doesn't return anything starting before now + 1 hour" do
    travel_to Time.zone.parse("2026-08-04T15:20:00+08:00") do
      calendar = FakeGoogleCalendarService.new
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(date: Date.current, window_start: "10:00", window_end: "22:00")

      assert_equal Time.zone.parse("2026-08-04T16:20"), slots.first.begin
    end
  end

  test "for today, free_slots returns nothing when now + 1 hour is already past the window" do
    travel_to Time.zone.parse("2026-08-04T21:30:00+08:00") do
      calendar = FakeGoogleCalendarService.new
      finder = Schedules::FreeSlotFinder.new(calendar: calendar)

      slots = finder.free_slots(date: Date.current, window_start: "10:00", window_end: "22:00")

      assert_empty slots
    end
  end
end
