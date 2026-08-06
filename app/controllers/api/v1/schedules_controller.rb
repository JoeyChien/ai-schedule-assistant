module Api
  module V1
    class SchedulesController < ApplicationController
      # date 是給 n8n 這類外部排程呼叫用的，例如 ?date=2026-08-05 只回傳當天的行程；
      # start_date/end_date 是通用的區間查詢，例如 ?start_date=2026-07-27&end_date=2026-08-02；
      # 都沒帶就維持原本「回傳全部」的行為
      #
      # 註：FR-010（每週項目時間統計）原本規劃呼叫這裡，後來 n8n 那條工作流程改成直接打
      # Google Calendar API（見 docs/n8n_workflows.md 工作流程 C），不會再經過這個 endpoint；
      # 這裡的 start_date/end_date 目前沒有任何呼叫端在用，先保留當通用能力。
      def index
        schedules = Schedule.order(start_time: :asc)

        if params[:date].present?
          schedules = schedules.on_date(Date.parse(params[:date]))
        elsif params[:start_date].present? && params[:end_date].present?
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date])
          schedules = schedules.in_range(start_date.beginning_of_day..end_date.end_of_day)
        elsif params[:start_date].present? || params[:end_date].present?
          return render json: { error: "start_date 和 end_date 要一起帶" }, status: :bad_request
        end

        render json: schedules
      rescue ArgumentError
        render json: { error: "date 格式錯誤，請用 YYYY-MM-DD" }, status: :bad_request
      end


      def show
        schedule = Schedule.find(params[:id])

        render json: schedule
      end


      def create
        schedule = Schedule.new(schedule_params)

        if schedule.save
          render json: schedule,
                 status: :created
        else
          render json: {
            errors: schedule.errors.full_messages
          },
          status: :unprocessable_entity
        end
      end


      def destroy
        schedule = Schedule.find(params[:id])

        schedule.destroy

        head :no_content
      end

      def parse
        schedule = Schedules::CreationService.new.create_from_message(
          params[:message]
        )

        render json: schedule, status: :created
      rescue Ai::GeminiService::RequestError => e
        render json: { error: e.message }, status: :bad_gateway
      rescue Ai::ResponseParser::ParseError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue GoogleCalendarService::Error => e
        render json: { error: e.message }, status: :bad_gateway
      end

      private


      def schedule_params
        params.require(:schedule)
              .permit(
                :title,
                :description,
                :start_time,
                :end_time,
                :source,
                :status
              )
      end
    end
  end
end
