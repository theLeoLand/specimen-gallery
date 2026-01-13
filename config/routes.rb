# config/routes.rb
Rails.application.routes.draw do
  root "pages#home"

  # Static pages
  get "about", to: "pages#about"
  get "terms", to: "pages#terms"
  get "browse", to: "taxa#index", as: :browse
  get "taxa", to: redirect("/browse")  # Redirect old URL

  resources :taxa, only: %i[show] do
    collection do
      get :suggest
    end
  end
  resources :specimen_assets, only: %i[new create]

  namespace :admin do
    resources :specimen_assets, only: %i[index update destroy]
  end
end
