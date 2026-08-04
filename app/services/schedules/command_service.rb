module Schedules
  # 接收使用者的一句話，解析意圖後派發給對應的 CRUD service，
  # 回傳可直接回覆給使用者（例如 LINE）的結果。
  class CommandService
    Result = Struct.new(:reply_text, :schedule, keyword_init: true)

    def initialize(
      parser: ParserService.new,
      creation_service: CreationService.new,
      update_service: UpdateService.new,
      deletion_service: DeletionService.new
    )
      @parser = parser
      @creation_service = creation_service
      @update_service = update_service
      @deletion_service = deletion_service
    end

    def call(message)
      parsed_intent = @parser.parse(message)

      case parsed_intent.action
      when "CREATE"
        schedule = @creation_service.create(parsed_intent)
        Result.new(reply_text: created_reply(schedule), schedule: schedule)
      when "UPDATE"
        schedule = @update_service.update(parsed_intent)
        Result.new(reply_text: updated_reply(schedule), schedule: schedule)
      when "DELETE"
        schedule = @deletion_service.delete(parsed_intent)
        Result.new(reply_text: deleted_reply(schedule), schedule: schedule)
      else
        Result.new(reply_text: unsupported_reply, schedule: nil)
      end
    rescue Ai::ResponseParser::ParseError
      Result.new(reply_text: parse_error_reply, schedule: nil)
    rescue Finder::NotFound => e
      Result.new(reply_text: e.message, schedule: nil)
    rescue GoogleCalendarService::Error
      Result.new(reply_text: calendar_error_reply, schedule: nil)
    end

    private

    def created_reply(schedule)
      "✅ 已為您安排行程：\n📌 #{schedule.title}\n⏰ #{format_time(schedule.start_time)}"
    end

    def updated_reply(schedule)
      "✅ 已更新行程：\n📌 #{schedule.title}\n⏰ #{format_time(schedule.start_time)}"
    end

    def deleted_reply(schedule)
      "🗑️ 已取消行程：#{schedule.title}"
    end

    def unsupported_reply
      "這個功能還在開發中，敬請期待！"
    end

    def parse_error_reply
      "我無法判斷你的時間。\n例如可以輸入：\n明天下午三點開會"
    end

    def calendar_error_reply
      "抱歉，Google 日曆暫時發生問題，請稍後再試一次。"
    end

    def format_time(time)
      time.strftime("%m/%d %H:%M")
    end
  end
end
