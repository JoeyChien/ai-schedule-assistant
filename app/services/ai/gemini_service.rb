module Ai
  class GeminiService
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

      JSON.parse(response.body)
    end

    def inspect
      "#<#{self.class.name}>"
    end

    private

    def api_url
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{@api_key}"
    end
  end
end
