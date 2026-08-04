module Ai
  class ResponseParser
    class ParseError < StandardError; end

    def self.parse(response)
      text = response.dig(
        "candidates",
        0,
        "content",
        "parts",
        0,
        "text"
      )

      raise ParseError, "Gemini 回傳內容為空" if text.blank?

      cleaned_text = remove_markdown(text)

      JSON.parse(cleaned_text)
    rescue JSON::ParserError => e
      raise ParseError, "JSON 解析失敗：#{e.message}"
    end

    def self.remove_markdown(text)
      text
        .gsub(/```json/i, "")
        .gsub(/```/, "")
        .strip
    end

    private_class_method :remove_markdown
  end
end
