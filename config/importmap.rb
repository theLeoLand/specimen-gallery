# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Client-side image compression for mobile uploads
pin "browser-image-compression", to: "https://cdn.jsdelivr.net/npm/browser-image-compression@2.0.2/dist/browser-image-compression.mjs"
