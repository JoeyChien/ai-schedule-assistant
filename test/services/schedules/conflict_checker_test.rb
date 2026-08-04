require "test_helper"

class Schedules::ConflictCheckerTest < ActiveSupport::TestCase
  test "raises when the given range overlaps an existing schedule" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))

    error = assert_raises(Schedules::ConflictChecker::ConflictError) do
      Schedules::ConflictChecker.check!(Time.zone.parse("2026-08-04T19:00"), Time.zone.parse("2026-08-04T19:30"))
    end

    assert_includes error.message, "看中醫"
    assert_includes error.message, "19:00-19:30"
  end

  test "raises on a partial overlap, not just an exact match" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))

    assert_raises(Schedules::ConflictChecker::ConflictError) do
      Schedules::ConflictChecker.check!(Time.zone.parse("2026-08-04T19:15"), Time.zone.parse("2026-08-04T20:00"))
    end
  end

  test "does not raise when the range is free" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))

    assert_nothing_raised do
      Schedules::ConflictChecker.check!(Time.zone.parse("2026-08-04T20:00"), Time.zone.parse("2026-08-04T20:30"))
    end
  end

  test "excludes the given id, so moving a schedule doesn't conflict with its own old slot" do
    schedule = Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))

    assert_nothing_raised do
      Schedules::ConflictChecker.check!(
        Time.zone.parse("2026-08-04T19:00"), Time.zone.parse("2026-08-04T19:30"), exclude_id: schedule.id
      )
    end
  end
end
