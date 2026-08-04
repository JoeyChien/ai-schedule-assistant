require "test_helper"

class Schedules::FreeSlotFinderTest < ActiveSupport::TestCase
  test "free_slots returns the whole window when there is nothing busy" do
    calendar = FakeGoogleCalendarService.new
    finder = Schedules::FreeSlotFinder.new(calendar: calendar)

    slots = finder.free_slots(date: Date.new(2026, 8, 4), window_start: "08:00", window_end: "10:00")

    assert_equal [ Time.zone.parse("2026-08-04T08:00")...Time.zone.parse("2026-08-04T10:00") ], slots
  end

  test "free_slots subtracts busy periods from the window" do
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

  test "free_slots also subtracts the given excluded_ranges (e.g. lunch/dinner breaks)" do
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

  test "free_slots accepts excluded_ranges with symbol keys too" do
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

  test "free_slots returns nothing when a busy period covers the whole window" do
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
