require "test_helper"

class DailySummaryJobTest < ActiveSupport::TestCase
  class FakeLine
    attr_reader :pushed

    def initialize
      @pushed = []
    end

    def push_text(user_id, text)
      @pushed << [ user_id, text ]
    end
  end

  class FakeSummaryService
    def call(date:) = "📅 #{date} 摘要"
  end

  test "pushes the summary text to the configured LINE user" do
    line = FakeLine.new

    DailySummaryJob.perform_now(
      date: Date.new(2026, 8, 4),
      daily_summary_service: FakeSummaryService.new,
      line: line,
      line_user_id: "U-fake-user"
    )

    assert_equal [ [ "U-fake-user", "📅 2026-08-04 摘要" ] ], line.pushed
  end

  test "logs and skips the push when line_user_id isn't configured" do
    line = FakeLine.new

    DailySummaryJob.perform_now(
      date: Date.new(2026, 8, 4),
      daily_summary_service: FakeSummaryService.new,
      line: line,
      line_user_id: nil
    )

    assert_empty line.pushed
  end
end
