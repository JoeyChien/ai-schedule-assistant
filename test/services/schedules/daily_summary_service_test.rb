require "test_helper"

class Schedules::DailySummaryServiceTest < ActiveSupport::TestCase
  class FakeAi
    def initialize(text: nil, error: nil)
      @text = text
      @error = error
    end

    def generate(_prompt)
      raise @error if @error

      { "candidates" => [ { "content" => { "parts" => [ { "text" => @text } ] } } ] }
    end
  end

  test "returns Gemini's text when the AI call succeeds" do
    ai = FakeAi.new(text: "📅 摘要內容")

    text = Schedules::DailySummaryService.new(ai: ai).call(date: Date.new(2026, 8, 4))

    assert_equal "📅 摘要內容", text
  end

  test "falls back to a plain-text summary when Gemini fails" do
    travel_to Time.zone.parse("2026-08-04T23:00:00+08:00") do
      Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T17:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T18:00:00+08:00"))
      Schedule.create!(title: "英文", start_time: Time.zone.parse("2026-08-04T21:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T23:30:00+08:00"))
      ai = FakeAi.new(error: Ai::GeminiService::RequestError.new("quota exceeded"))

      text = Schedules::DailySummaryService.new(ai: ai).call(date: Date.new(2026, 8, 4))

      assert_includes text, "健身"
      assert_includes text, "英文"
      assert_includes text, "完成率：50%"
      assert_includes text, "建議"
    end
  end

  test "falls back to a plain-text summary when Gemini returns a blank response" do
    ai = FakeAi.new(text: "")

    text = Schedules::DailySummaryService.new(ai: ai).call(date: Date.new(2026, 8, 4))

    assert_includes text, "每日摘要"
    assert_includes text, "還沒有完成的行程"
  end
end
