require "test_helper"

class ParsedIntentTest < ActiveSupport::TestCase
  test "from_hash builds a ParsedIntent from Gemini's JSON shape" do
    intent = ParsedIntent.from_hash(
      "action" => "CREATE",
      "title" => "健身",
      "start_time" => "2026-08-05T17:00:00+08:00",
      "end_time" => "2026-08-05T18:00:00+08:00",
      "location" => ""
    )

    assert intent.create?
    assert_equal "健身", intent.title
    assert_equal Time.zone.parse("2026-08-05T17:00:00+08:00"), intent.start_time
    assert_nil intent.location
  end

  test "to_schedule_attributes defaults end_time to start_time + 1 hour when missing" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"))

    attributes = intent.to_schedule_attributes

    assert_equal Time.zone.parse("2026-08-05T18:00:00+08:00"), attributes[:end_time]
    assert_equal "line", attributes[:source]
  end

  test "query_range uses the given start_time/end_time" do
    intent = ParsedIntent.new(
      action: "QUERY",
      start_time: Time.zone.parse("2026-08-04T00:00:00+08:00"),
      end_time: Time.zone.parse("2026-08-04T23:59:59+08:00")
    )

    assert intent.query?
    assert_equal Time.zone.parse("2026-08-04T00:00:00+08:00"), intent.query_range.begin
    assert_equal Time.zone.parse("2026-08-04T23:59:59.999999999+08:00"), intent.query_range.end
  end

  test "query_range defaults to today when Gemini doesn't return a time" do
    travel_to Time.zone.parse("2026-08-04T12:00:00+08:00") do
      intent = ParsedIntent.new(action: "QUERY")

      assert_equal Date.current.beginning_of_day, intent.query_range.begin
      assert_equal Date.current.end_of_day, intent.query_range.end
    end
  end

  test "from_hash carries time_specified/duration_minutes/date through for CREATE without an explicit time" do
    intent = ParsedIntent.from_hash(
      "action" => "CREATE",
      "title" => "做伸展",
      "time_specified" => false,
      "start_time" => "",
      "end_time" => "",
      "duration_minutes" => 30,
      "date" => "2026-08-04",
      "location" => ""
    )

    assert intent.needs_auto_schedule?
    assert_equal 30.minutes, intent.requested_duration
    assert_equal Date.new(2026, 8, 4), intent.target_date
  end

  test "time_specified? defaults to true when Gemini omits the field, so old-style intents don't trigger auto-schedule" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.now)

    assert intent.time_specified?
    assert_not intent.needs_auto_schedule?
  end

  test "needs_auto_schedule? is false for non-CREATE actions even without time_specified" do
    intent = ParsedIntent.new(action: "QUERY", time_specified: false)

    assert_not intent.needs_auto_schedule?
  end

  test "requested_duration defaults to 60 minutes when duration_minutes is missing" do
    intent = ParsedIntent.new(action: "CREATE", time_specified: false)

    assert_equal 60.minutes, intent.requested_duration
  end

  test "target_date falls back to start_time's date, then today, when date is missing" do
    intent = ParsedIntent.new(action: "CREATE", start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"))
    assert_equal Date.new(2026, 8, 5), intent.target_date

    travel_to Time.zone.parse("2026-08-04T12:00:00+08:00") do
      assert_equal Date.current, ParsedIntent.new(action: "CREATE").target_date
    end
  end

  test "from_hash builds an UPDATE_SCHEDULE_SETTINGS intent" do
    intent = ParsedIntent.from_hash(
      "action" => "UPDATE_SCHEDULE_SETTINGS",
      "window_start" => "09:00",
      "window_end" => "21:00",
      "excluded_ranges" => [ { "start" => "12:30", "end" => "13:30" } ]
    )

    assert intent.update_schedule_settings?
    assert_equal "09:00", intent.window_start
    assert_equal "21:00", intent.window_end
    assert_equal [ { "start" => "12:30", "end" => "13:30" } ], intent.excluded_ranges
  end

  test "from_hash builds a FIND_FREE_TIME intent with occurrences/range_start/range_end" do
    intent = ParsedIntent.from_hash(
      "action" => "FIND_FREE_TIME",
      "title" => "閱讀",
      "occurrences" => 2,
      "duration_minutes" => 60,
      "range_start" => "2026-08-04",
      "range_end" => "2026-08-09",
      "preferred_period" => "evening"
    )

    assert intent.find_free_time?
    assert_equal 2, intent.requested_occurrences
    assert_equal 60.minutes, intent.requested_duration
    assert_equal Date.new(2026, 8, 4)..Date.new(2026, 8, 9), intent.schedule_range
  end

  test "requested_occurrences defaults to 1 and schedule_range defaults to today only, when missing" do
    travel_to Time.zone.parse("2026-08-04T12:00:00+08:00") do
      intent = ParsedIntent.new(action: "FIND_FREE_TIME", title: "閱讀")

      assert_equal 1, intent.requested_occurrences
      assert_equal Date.current..Date.current, intent.schedule_range
    end
  end
end
