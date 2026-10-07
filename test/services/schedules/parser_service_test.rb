require "test_helper"

class Schedules::ParserServiceTest < ActiveSupport::TestCase
  class FakeGemini
    attr_reader :prompts

    def initialize(json:)
      @json = json
      @prompts = []
    end

    def generate(prompt)
      @prompts << prompt
      { "candidates" => [ { "content" => { "parts" => [ { "text" => @json } ] } } ] }
    end
  end

  test "parse_all returns one ParsedIntent per item when Gemini replies with a JSON array" do
    json = [
      { "action" => "CREATE", "title" => "整理履歷", "start_time" => "2026-08-01T20:00:00+08:00" },
      { "action" => "CREATE", "title" => "慢跑", "start_time" => "2026-08-01T21:00:00+08:00" }
    ].to_json
    service = Schedules::ParserService.new(gemini: FakeGemini.new(json: json))

    intents = service.parse_all("今天晚上8點整理履歷\n今天晚上9點慢跑")

    assert_equal 2, intents.size
    assert_equal %w[整理履歷 慢跑], intents.map(&:title)
    assert intents.all? { |i| i.is_a?(ParsedIntent) }
  end

  test "parse_all wraps a single JSON object into a one-element array (backward compatible shape)" do
    json = { "action" => "CREATE", "title" => "健身", "start_time" => "2026-08-05T17:00:00+08:00" }.to_json
    service = Schedules::ParserService.new(gemini: FakeGemini.new(json: json))

    intents = service.parse_all("明天下午五點健身")

    assert_equal 1, intents.size
    assert_equal "健身", intents.first.title
  end

  test "parse delegates to parse_all and returns just the first intent" do
    json = { "action" => "CREATE", "title" => "健身", "start_time" => "2026-08-05T17:00:00+08:00" }.to_json
    service = Schedules::ParserService.new(gemini: FakeGemini.new(json: json))

    intent = service.parse("明天下午五點健身")

    assert_equal "健身", intent.title
  end

  test "parse_all raises ParseError when Gemini returns an empty array" do
    service = Schedules::ParserService.new(gemini: FakeGemini.new(json: "[]"))

    assert_raises(Ai::ResponseParser::ParseError) do
      service.parse_all("...")
    end
  end

  test "the prompt sent to Gemini includes the raw message" do
    gemini = FakeGemini.new(json: { "action" => "CREATE", "title" => "健身" }.to_json)
    service = Schedules::ParserService.new(gemini: gemini)

    service.parse_all("今天晚上8點整理履歷")

    assert_includes gemini.prompts.first, "今天晚上8點整理履歷"
  end
end
