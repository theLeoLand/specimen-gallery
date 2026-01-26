# app/controllers/concerns/admin_auth.rb
# Provides HTTP Basic authentication for admin routes.
#
# Required ENV variables for production:
#   ADMIN_USERNAME - admin login username
#   ADMIN_PASSWORD - admin login password
#   ADMIN_ROUTE_SECRET - secret path segment (e.g., "__sg_abc123")
#
# In development/test, defaults to admin/admin if ENV not set.
module AdminAuth
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    # In production, require ENV variables - no fallbacks
    if Rails.env.production?
      unless ENV["ADMIN_USERNAME"].present? && ENV["ADMIN_PASSWORD"].present?
        Rails.logger.error("Admin access attempted but ADMIN_USERNAME/ADMIN_PASSWORD not configured")
        head :service_unavailable
        return
      end
    end

    admin_username = ENV.fetch("ADMIN_USERNAME") { Rails.env.production? ? nil : "admin" }
    admin_password = ENV.fetch("ADMIN_PASSWORD") { Rails.env.production? ? nil : "admin" }

    authenticate_or_request_with_http_basic("Specimen Gallery Admin") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username.to_s, admin_username.to_s) &&
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, admin_password.to_s)
    end
  end
end
