Rails.application.routes.draw do
  # Report routes
  resources :reports, only: [:new, :create] do
    collection do
      get :locations  # GET /reports/locations
      get :tags       # GET /reports/tags
    end
  end

  # Optional root route
  root 'reports#new'

  # Other routes...
  # resources :products, etc.
end