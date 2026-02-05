# app/controllers/concerns/anonymous_identity.rb
# Provides anonymous identity for community voting without user accounts
module AnonymousIdentity
  extend ActiveSupport::Concern

  VOTE_RATE_LIMIT = 10
  VOTE_RATE_WINDOW = 1.hour

  included do
    before_action :ensure_fingerprint
  end

  private

  # Ensure a permanent cookie fingerprint exists for this visitor
  def ensure_fingerprint
    cookies.permanent.signed[:sg_fingerprint] ||= SecureRandom.hex(16)
  end

  # Get the visitor's fingerprint (cookie-based)
  def voter_fingerprint
    cookies.signed[:sg_fingerprint]
  end

  # Compute a hashed IP (never store raw IP)
  def voter_ip_hash
    secret = Rails.application.credentials.secret_key_base || Rails.application.secret_key_base
    Digest::SHA256.hexdigest("#{request.remote_ip}-#{secret}-sg")
  end

  # Check if voter is rate limited
  def vote_rate_limited?
    count = Rails.cache.read(vote_rate_limit_key) || 0
    count >= VOTE_RATE_LIMIT
  end

  # Increment vote rate counter
  def increment_vote_rate
    current = Rails.cache.read(vote_rate_limit_key) || 0
    Rails.cache.write(vote_rate_limit_key, current + 1, expires_in: VOTE_RATE_WINDOW)
  end

  def vote_rate_limit_key
    "vote_rate:#{voter_ip_hash}"
  end
end



