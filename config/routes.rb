# config/routes.rb
Rails.application.routes.draw do
  root "pages#home"

  # Static pages
  get "about", to: "pages#about"
  get "terms", to: "pages#terms"
  get "upload-guide", to: "pages#upload_guide", as: :upload_guide
  get "browse", to: "taxa#index", as: :browse
  get "taxa", to: redirect("/browse")  # Redirect old URL

  resources :taxa, only: %i[show] do
    collection do
      get :suggest
    end
  end
  resources :specimen_assets, only: %i[new create] do
    resources :flags, only: %i[create]
  end

  namespace :admin do
    resources :specimen_assets, only: %i[index edit update destroy] do
      member do
        patch :unpublish
      end
    end
    resources :flags, only: %i[index] do
      member do
        patch :resolve
        patch :dismiss
        patch :mark_needs_review
      end
    end
  end
end
