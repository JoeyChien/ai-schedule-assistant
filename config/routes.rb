Rails.application.routes.draw do
  post "line/callback", to: "line_bot#callback"

  namespace :api do
    namespace :v1 do
      resources :schedules do
        collection do
          post :parse
        end
      end
    end
  end
end
