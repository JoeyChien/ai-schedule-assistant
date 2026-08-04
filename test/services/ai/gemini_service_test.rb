require "test_helper"

class Ai::GeminiServiceTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body) do
    def success? = status < 300
  end

  def with_faraday_post_stubbed(response)
    original_post = Faraday.method(:post)
    Faraday.define_singleton_method(:post) { |*_args, **_kwargs, &_block| response }
    yield
  ensure
    Faraday.define_singleton_method(:post, original_post)
  end

  test "generate returns the parsed body on success" do
    with_faraday_post_stubbed(FakeResponse.new(200, { candidates: [] }.to_json)) do
      result = Ai::GeminiService.new.generate("hello")
      assert_equal({ "candidates" => [] }, result)
    end
  end

  test "generate raises RequestError with Gemini's message when the API call fails" do
    error_body = { error: { code: 429, message: "quota exceeded" } }.to_json

    with_faraday_post_stubbed(FakeResponse.new(429, error_body)) do
      error = assert_raises(Ai::GeminiService::RequestError) do
        Ai::GeminiService.new.generate("hello")
      end
      assert_includes error.message, "429"
      assert_includes error.message, "quota exceeded"
    end
  end
end
