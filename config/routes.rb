Rails.application.routes.draw do
  devise_for :users

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  resources :catalogs, only: %i[index show new create destroy] do
    member do
      post :sync
    end
  end

  resources :iceberg_tables, only: %i[show] do
    member do
      post :run_maintenance
    end
  end

  resources :maintenance_schedules
end
