module Schedules
  class ParserService
    def initialize(gemini: Ai::GeminiService.new)
      @gemini = gemini
    end

    # 相容舊有呼叫方式：一次訊息只處理成一筆意圖（例如 REST API 的 /parse 端點）
    def parse(message)
      parse_all(message).first
    end

    # 一次訊息可能包含多筆不同的行程指示（分行寫，或用「還有」「跟」連接在一起），
    # Gemini 會視情況回傳單一個 JSON 物件或一個 JSON 陣列，這裡統一轉成 ParsedIntent 陣列回傳
    def parse_all(message)
      response = @gemini.generate(build_prompt(message))
      parsed = Ai::ResponseParser.parse(response)

      intents = Array.wrap(parsed).map { |hash| ParsedIntent.from_hash(hash) }

      raise Ai::ResponseParser::ParseError, "Gemini 沒有回傳任何可辨識的行程" if intents.empty?

      intents
    end

    private

    def build_prompt(message)
      Ai::PromptBuilder.render(
        "intent_parser",
        message: message,
        date: Date.current,
        scheduling_preference: SchedulingPreference.current
      )
    end
  end
end
