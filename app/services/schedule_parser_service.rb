class ScheduleParserService

  def initialize
    @gemini = GeminiService.new
  end


  def parse(input)
    response = @gemini.generate(prompt(input))

    extract_json(response)
  end


  private


  def prompt(input)
    current_date = Time.current.strftime("%Y-%m-%d")

    <<~PROMPT
        你是一個行程管理助手。

        今天日期是 #{current_date}。

        請將使用者輸入轉換成 JSON。

        規則：
        - title: 行程名稱
        - start_time: 開始時間
        - end_time: 結束時間
        - 如果使用者沒有提供年份，請使用今天日期之後最近的日期
        - 如果沒有結束時間，預設持續60分鐘
        - 時間格式使用 YYYY-MM-DD HH:mm

        只回傳 JSON，不要加入 markdown。

        使用者輸入：
        #{input}
    PROMPT
    end


  def extract_json(response)
    text = response.dig(
      "candidates",
      0,
      "content",
      "parts",
      0,
      "text"
    )

    JSON.parse(text)
  end

end
