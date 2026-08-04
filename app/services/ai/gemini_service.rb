module Ai
  class GeminiService
    class RequestError < StandardError; end

    def initialize
      @api_key = Rails.application.credentials.dig(
        :gemini,
        :api_key
      )
    end

    def generate(prompt)
      response = Faraday.post(api_url) do |request|
        request.headers["Content-Type"] = "application/json"

        request.body = {
          contents: [
            {
              parts: [
                {
                  text: prompt
                }
              ]
            }
          ]
        }.to_json
      end

      body = JSON.parse(response.body)

      unless response.success?
        message = body.dig("error", "message") || response.body
        raise RequestError, "Gemini API 回傳錯誤（HTTP #{response.status}）：#{message}"
      end

      body
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def api_url
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=#{@api_key}"
    end
  end
end
