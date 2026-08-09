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

  # index e novo: visão global de tabelas com filtros (CR-25)
  resources :iceberg_tables, only: %i[index show] do
    member do
      post :run_maintenance
    end
  end

  # log global de operações (CR-26)
  resources :execution_histories, only: %i[index]

  # políticas de manutenção (CR-28)
  resources :maintenance_policies do
    member { post :apply }
  end

  resources :maintenance_schedules
end
