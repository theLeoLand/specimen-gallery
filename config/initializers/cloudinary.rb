# Cloudinary configuration
# Set these environment variables in your shell or .env file:
#   CLOUDINARY_CLOUD_NAME
#   CLOUDINARY_API_KEY
#   CLOUDINARY_API_SECRET

if ENV["CLOUDINARY_CLOUD_NAME"].present?
  Cloudinary.config do |config|
    config.cloud_name = ENV.fetch("CLOUDINARY_CLOUD_NAME")
    config.api_key    = ENV.fetch("CLOUDINARY_API_KEY")
    config.api_secret = ENV.fetch("CLOUDINARY_API_SECRET")
    config.secure     = true
  end
elsif Rails.env.production?
  # Warn but don't crash - allows db:prepare and other tasks to run
  # Uploads will fail gracefully if Cloudinary isn't configured
  Rails.logger.warn "⚠️  Cloudinary credentials not configured. Image uploads will not work until CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET are set."
end
