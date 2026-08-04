require "test_helper"

class DailyHabitSchedulingJobTest < ActiveSupport::TestCase
  class FakeLine
    attr_reader :pushed

    def initialize
      @pushed = []
    end

    def push_text(user_id, text)
      @pushed << [ user_id, text ]
    end
  end

  test "pushes a LINE summary of what got scheduled" do
    calendar = FakeGoogleCalendarService.new
    line = FakeLine.new

    DailyHabitSchedulingJob.perform_now(
      date: Date.new(2026, 8, 4),
      habit_scheduling_service: Schedules::HabitSchedulingService.new(calendar: calendar),
      line: line,
      line_user_id: "U-fake-user"
    )

    assert_equal 1, line.pushed.size
    user_id, text = line.pushed.first
    assert_equal "U-fake-user", user_id
    assert_includes text, "閱讀"
    assert_includes text, "冥想"
  end

  test "logs and skips the push when line_user_id isn't configured" do
    calendar = FakeGoogleCalendarService.new
    line = FakeLine.new

    DailyHabitSchedulingJob.perform_now(
      date: Date.new(2026, 8, 4),
      habit_scheduling_service: Schedules::HabitSchedulingService.new(calendar: calendar),
      line: line,
      line_user_id: nil
    )

    assert_empty line.pushed
  end
end
