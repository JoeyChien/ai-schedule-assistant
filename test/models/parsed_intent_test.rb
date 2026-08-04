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
end
