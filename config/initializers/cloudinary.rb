Cloudinary.config do |config|
  config.cloud_name = ENV.fetch("CLOUDINARY_CLOUD_NAME", "dgjsvefqd")
  config.api_key    = ENV.fetch("CLOUDINARY_API_KEY", "376523848662931")
  config.api_secret = ENV.fetch("CLOUDINARY_API_SECRET", "J68sDY41ZJpIySKV1GP3-kIx2zc")
  config.secure     = true
end
