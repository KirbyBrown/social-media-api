# frozen_string_literal: true

Rails.application.routes.draw do
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      resources :users, only: [ :create ]
      resources :sessions, only: [ :create ]
      resource :timeline, only: :show
      resources :posts, only: %i[index show create update destroy] do
        resource :rating, only: :update
      end
    end
  end
end
