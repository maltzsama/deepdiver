Rails.application.routes.draw do
  # Public registration closed: accounts come from the IdP or from seed.
  devise_for :users,
             skip: %i[registrations],
             controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  # Allow signed-in users to edit their own account, without exposing /users/sign_up.
  devise_scope :user do
    get  "users/edit" => "devise/registrations#edit",   as: :edit_user_registration
    put  "users"      => "devise/registrations#update", as: :user_registration
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"

  # Paper/ink theme toggle (account preference since CR-69).
  post "theme/toggle" => "theme#toggle", as: :toggle_theme

  # Own-account preferences (CR-69).
  resource :profile, only: %i[show update], controller: "profiles" do
    patch :password, on: :collection
  end

  # What is happening right now.
  resource :activity, only: :show, controller: "activity" do
    member { post :restart }
  end

  # Superfície de erro (CR-72): opens the list of recorded failures.
  resources :error_events, only: %i[index] do
    collection do
      post :acknowledge
      post :resolve
    end
  end

  resources :catalogs, only: %i[index show new create edit update destroy] do
    member do
      post :sync
      post :verify
    end
  end

  # Global tables view with filters.
  resources :iceberg_tables, only: %i[index show] do
    member do
      post :run_maintenance
    end

    resource :freshness_sla, only: %i[edit update], controller: "freshness_slas"
  end

  # Global log of operations.
  resources :execution_histories, only: %i[index] do
    member { post :cancel }
  end

  # Maintenance plans.
  resources :maintenance_plans, only: %i[index show edit update] do
    member do
      post :run
      post :pause
      post :resume
    end
  end

  # Maintenance policies.
  resources :maintenance_policies do
    member { post :apply }
  end

  resources :maintenance_schedules

  # User & team administration (CR-64).
  resources :users, only: %i[index new create update] do
    member do
      post :suspend
      post :reactivate
    end
  end

  resources :teams

  # Alerting (CR-84): channels and the global SMTP/Slack settings.
  resources :alert_channels, only: %i[index show new create edit update destroy] do
    member { post :test }
  end
  resource :alert_settings, only: %i[show update]
end
