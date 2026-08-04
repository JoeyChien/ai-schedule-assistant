require "test_helper"

class Ai::ResponseParserTest < ActiveSupport::TestCase
  test "parse extracts JSON from a normal Gemini response, stripping markdown fences" do
    response = {
      "candidates" => [
        { "content" => { "parts" => [ { "text" => "```json\n{\"action\":\"CREATE\"}\n```" } ] } }
      ]
    }

    assert_equal({ "action" => "CREATE" }, Ai::ResponseParser.parse(response))
  end

  test "parse raises ParseError with the block reason when Gemini blocks the prompt" do
    response = {
      "candidates" => [],
      "promptFeedback" => { "blockReason" => "SAFETY" }
    }

    error = assert_raises(Ai::ResponseParser::ParseError) { Ai::ResponseParser.parse(response) }
    assert_includes error.message, "SAFETY"
  end
end
