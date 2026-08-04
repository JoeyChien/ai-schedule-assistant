module Schedules
  class ParserService
    def initialize
      @gemini = Ai::GeminiService.new
    end

    def parse(message)
      prompt = build_prompt(message)

      response = @gemini.generate(prompt)

      ParsedIntent.from_hash(
        Ai::ResponseParser.parse(response)
      )
    end

    private

    def build_prompt(message)
      Ai::PromptBuilder.render(
        "intent_parser",
        message: message,
        date: Date.current
      )
    end
  end
end
