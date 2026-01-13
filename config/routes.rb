# config/routes.rb
Rails.application.routes.draw do
  root "taxa#index"

  # Static pages
  get "about", to: "pages#about"
  get "terms", to: "pages#terms"

  resources :taxa, only: %i[index show] do
    collection do
      get :suggest
    end
  end
  resources :specimen_assets, only: %i[new create]

  namespace :admin do
    resources :specimen_assets, only: %i[index update destroy]
  end
end
