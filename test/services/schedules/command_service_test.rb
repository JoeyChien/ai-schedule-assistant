require "test_helper"

class Schedules::CommandServiceTest < ActiveSupport::TestCase
  # 固定在測試日期（2026-08-04/05）之前，這樣「今天不能排過去時間」的邏輯不會影響這些測試
  setup { travel_to(Time.zone.parse("2026-08-01T09:00:00+08:00")) }
  teardown { travel_back }

  # intent 可以是單一個 ParsedIntent，也可以是多個（模擬一次訊息包含多筆行程指示）
  FakeParser = Struct.new(:intent) do
    def parse_all(_message) = Array(intent)
  end

  class RaisingParser
    def initialize(error) = @error = error
    def parse_all(_message) = raise(@error)
  end

  def build_service(intent:, calendar: FakeGoogleCalendarService.new)
    Schedules::CommandService.new(
      parser: FakeParser.new(intent),
      creation_service: Schedules::CreationService.new(calendar: calendar),
      update_service: Schedules::UpdateService.new(calendar: calendar),
      deletion_service: Schedules::DeletionService.new(calendar: calendar),
      bulk_schedule_service: Schedules::BulkScheduleService.new(calendar: calendar)
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

  test "CREATE with a conflicting time replies with the conflict message instead of double-booking" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-04T19:00"), end_time: Time.zone.parse("2026-08-04T19:30"))
    intent = ParsedIntent.new(
      action: "CREATE",
      title: "做伸展",
      start_time: Time.zone.parse("2026-08-04T19:00"),
      end_time: Time.zone.parse("2026-08-04T19:30")
    )
    calendar = FakeGoogleCalendarService.new

    result = build_service(intent: intent, calendar: calendar).call("今天晚上做伸展30分")

    assert_includes result.reply_text, "看中醫"
    assert_includes result.reply_text, "撞期"
    assert_nil result.schedule
    assert_empty calendar.calls
  end

  test "CREATE without an explicit time auto-schedules into a free slot and says so in the reply" do
    intent = ParsedIntent.new(action: "CREATE", title: "做伸展", time_specified: false, duration_minutes: 30, date: "2026-08-04", preferred_period: "evening")

    result = build_service(intent: intent).call("今天晚上做伸展30分")

    assert_includes result.reply_text, "幫您找空檔安排"
    assert_includes result.reply_text, "做伸展"
    # 晚上時段是 18:00-22:00，扣掉預設的晚餐排除時段 18:00-19:00 後，第一個空檔是 19:00
    assert_equal Time.zone.parse("2026-08-04T19:00"), result.schedule.start_time
  end

  test "CREATE without an explicit time replies with a clear message when there's no room left" do
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [ FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T22:00")) ]
    intent = ParsedIntent.new(action: "CREATE", title: "冥想", time_specified: false, duration_minutes: 15, date: "2026-08-04")

    result = build_service(intent: intent, calendar: calendar).call("今天找空檔冥想15分")

    assert_includes result.reply_text, "沒有空檔"
    assert_nil result.schedule
  end

  test "UPDATE_SCHEDULE_SETTINGS updates the shared preference and confirms the new window" do
    intent = ParsedIntent.new(
      action: "UPDATE_SCHEDULE_SETTINGS",
      window_start: "09:00",
      window_end: "21:00",
      excluded_ranges: [ { "start" => "12:30", "end" => "13:30" } ]
    )

    result = build_service(intent: intent).call("把可排程時間改成9點到21點，午休改成12:30到13:30")

    assert_includes result.reply_text, "09:00-21:00"
    assert_includes result.reply_text, "12:30-13:30"
    assert_equal "09:00", SchedulingPreference.current.window_start
  end

  test "unrecognized action replies with an unsupported message" do
    intent = ParsedIntent.new(action: "SOMETHING_GEMINI_MADE_UP", title: nil)

    result = build_service(intent: intent).call("...")

    assert_includes result.reply_text, "開發中"
  end

  test "FIND_FREE_TIME schedules multiple occurrences across the requested range and replies with a summary" do
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME",
      title: "閱讀",
      occurrences: 2,
      duration_minutes: 60,
      range_start: "2026-08-04",
      range_end: "2026-08-05"
    )

    result = build_service(intent: intent).call("這週找時間安排兩次閱讀1小時")

    assert_includes result.reply_text, "已幫您安排 2/2 次「閱讀」"
    assert_equal 2, Schedule.where(title: "閱讀").count
  end

  test "FIND_FREE_TIME requested late at night never schedules something already in the past (the reported bug)" do
    travel_to(Time.zone.parse("2026-08-04T22:00:00+08:00")) do
      intent = ParsedIntent.new(
        action: "FIND_FREE_TIME",
        title: "閱讀",
        occurrences: 2,
        duration_minutes: 60,
        range_start: "2026-08-04",
        range_end: "2026-08-09"
      )

      result = build_service(intent: intent).call("在這週找時間安排兩次閱讀1小時")

      assert_includes result.reply_text, "已幫您安排 2/2 次「閱讀」"
      schedules = Schedule.where(title: "閱讀").order(:start_time)
      assert_equal [ Date.new(2026, 8, 5), Date.new(2026, 8, 6) ], schedules.map { |s| s.start_time.to_date }
    end
  end

  test "FIND_FREE_TIME reports how many occurrences it couldn't fit" do
    calendar = FakeGoogleCalendarService.new
    calendar.busy_periods = [ FakeGoogleCalendarService::FakeBusyPeriod.new(Time.zone.parse("2026-08-04T10:00"), Time.zone.parse("2026-08-04T22:00")) ]
    intent = ParsedIntent.new(
      action: "FIND_FREE_TIME",
      title: "閱讀",
      occurrences: 2,
      duration_minutes: 60,
      range_start: "2026-08-04",
      range_end: "2026-08-04"
    )

    result = build_service(intent: intent, calendar: calendar).call("今天找時間安排兩次閱讀1小時")

    assert_includes result.reply_text, "剩下 2 次"
    assert_equal 0, Schedule.where(title: "閱讀").count
  end

  test "a message with multiple schedule instructions creates each one and numbers the combined reply" do
    intents = [
      ParsedIntent.new(action: "CREATE", title: "整理履歷", start_time: Time.zone.parse("2026-08-01T20:00:00+08:00")),
      ParsedIntent.new(action: "CREATE", title: "慢跑", start_time: Time.zone.parse("2026-08-01T21:00:00+08:00"))
    ]

    result = build_service(intent: intents).call("今天晚上8點整理履歷\n今天晚上9點慢跑")

    assert_includes result.reply_text, "1. "
    assert_includes result.reply_text, "整理履歷"
    assert_includes result.reply_text, "2. "
    assert_includes result.reply_text, "慢跑"
    assert_nil result.schedule
    assert_equal 2, Schedule.where(title: [ "整理履歷", "慢跑" ]).count
  end

  test "a message with multiple schedule instructions handles each independently, so one conflict doesn't block the others" do
    Schedule.create!(title: "看中醫", start_time: Time.zone.parse("2026-08-01T21:00:00+08:00"), end_time: Time.zone.parse("2026-08-01T21:30:00+08:00"))
    intents = [
      ParsedIntent.new(action: "CREATE", title: "慢跑", start_time: Time.zone.parse("2026-08-01T21:00:00+08:00")),
      ParsedIntent.new(action: "CREATE", title: "閱讀", start_time: Time.zone.parse("2026-08-01T22:00:00+08:00"))
    ]

    result = build_service(intent: intents).call("今天晚上9點慢跑還有10點閱讀")

    assert_includes result.reply_text, "撞期"
    assert_includes result.reply_text, "已為您安排行程"
    assert_includes result.reply_text, "閱讀"
    assert_equal 0, Schedule.where(title: "慢跑").count # 撞期被擋下，不會建立
    assert_equal 1, Schedule.where(title: "閱讀").count
  end

  test "a single-item array behaves exactly like the old single-intent path (same Result, no numbering)" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"))

    result = build_service(intent: [ intent ]).call("明天下午五點健身")

    assert_equal "✅ 已為您安排行程：\n📌 健身\n⏰ 08/05 17:00", result.reply_text
    assert_equal "健身", result.schedule.title
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
