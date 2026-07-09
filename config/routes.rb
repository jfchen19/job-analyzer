Rails.application.routes.draw do
  root "dashboard#index"

  resources :resumes do
    member { put :set_default }
    collection do
      post :extract_pdf
    end
  end

  resources :job_postings do
    member do
      post :analyze
      patch :archive
    end
    # fetch_content is called from the `new` form before any record exists,
    # so it must be a collection route (no :id), not a member route.
    collection do
      post :fetch_content
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
