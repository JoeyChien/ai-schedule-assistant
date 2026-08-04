require "test_helper"

class Schedules::CommandServiceTest < ActiveSupport::TestCase
  FakeParser = Struct.new(:intent) do
    def parse(_message) = intent
  end

  class RaisingParser
    def initialize(error) = @error = error
    def parse(_message) = raise(@error)
  end

  def build_service(intent:, calendar: FakeGoogleCalendarService.new)
    Schedules::CommandService.new(
      parser: FakeParser.new(intent),
      creation_service: Schedules::CreationService.new(calendar: calendar),
      update_service: Schedules::UpdateService.new(calendar: calendar),
      deletion_service: Schedules::DeletionService.new(calendar: calendar)
    )
  end

  test "CREATE creates a schedule and replies with a confirmation" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"))

    result = build_service(intent: intent).call("明天下午五點健身")

    assert_includes result.reply_text, "已為您安排行程"
    assert_includes result.reply_text, "健身"
    assert_equal "健身", result.schedule.title
  end

  test "DELETE with no matching schedule replies with a not-found message instead of raising" do
    intent = ParsedIntent.new(action: "DELETE", title: "不存在")

    result = build_service(intent: intent).call("取消不存在")

    assert_includes result.reply_text, "找不到"
    assert_nil result.schedule
  end

  test "QUERY lists schedules in range and does not touch Google Calendar" do
    Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T17:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T18:00:00+08:00"))
    intent = ParsedIntent.new(
      action: "QUERY",
      start_time: Time.zone.parse("2026-08-04T00:00:00+08:00"),
      end_time: Time.zone.parse("2026-08-04T23:59:59+08:00")
    )
    calendar = FakeGoogleCalendarService.new

    result = build_service(intent: intent, calendar: calendar).call("今天有什麼安排？")

    assert_includes result.reply_text, "健身"
    assert_includes result.reply_text, "17:00"
    assert_nil result.schedule
    assert_empty calendar.calls
  end

  test "QUERY with nothing scheduled replies that the range is free" do
    intent = ParsedIntent.new(
      action: "QUERY",
      start_time: Time.zone.parse("2026-08-04T00:00:00+08:00"),
      end_time: Time.zone.parse("2026-08-04T23:59:59+08:00")
    )

    result = build_service(intent: intent).call("今天有什麼安排？")

    assert_includes result.reply_text, "沒有安排"
  end

  test "unrecognized action replies with an unsupported message" do
    intent = ParsedIntent.new(action: "FIND_FREE_TIME", title: nil)

    result = build_service(intent: intent).call("幫我找空檔")

    assert_includes result.reply_text, "開發中"
  end

  test "a Gemini parsing error replies with the spec's guidance message" do
    service = Schedules::CommandService.new(parser: RaisingParser.new(Ai::ResponseParser::ParseError.new("boom")))

    result = service.call("嗯嗯嗯")

    assert_equal "我無法判斷你的時間。\n例如可以輸入：\n明天下午三點開會", result.reply_text
  end

  test "a Gemini API error (e.g. quota exceeded) replies with an AI-unavailable message" do
    service = Schedules::CommandService.new(parser: RaisingParser.new(Ai::GeminiService::RequestError.new("HTTP 429: quota exceeded")))

    result = service.call("明天下午五點健身")

    assert_includes result.reply_text, "AI 服務暫時無法使用"
    assert_nil result.schedule
  end

  test "a Google Calendar error replies with a friendly retry message" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.now)
    failing_calendar = Object.new
    def failing_calendar.create_event(**) = raise(GoogleCalendarService::Error, "boom")

    result = build_service(intent: intent, calendar: failing_calendar).call("明天下午五點健身")

    assert_includes result.reply_text, "Google 日曆"
    assert_nil result.schedule
  end
end
