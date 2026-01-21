# app/controllers/flags_controller.rb
class FlagsController < ApplicationController
  # Rate limit: max 5 flags per IP per hour
  RATE_LIMIT = 5
  RATE_WINDOW = 1.hour

  def create
    @specimen_asset = SpecimenAsset.find(params[:specimen_asset_id])

    # Check rate limit
    if rate_limited?
      render json: { error: "Too many flags. Please try again later." }, status: :too_many_requests
      return
    end

    @flag = @specimen_asset.flags.build(flag_params)
    @flag.reporter_ip = request.remote_ip

    if @flag.save
      increment_rate_counter
      render json: { success: true, message: "Thank you for your report. We'll review it shortly." }
    else
      render json: { error: @flag.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def flag_params
    params.require(:flag).permit(:reason, :details)
  end

  def rate_limit_key
    "flag_rate:#{request.remote_ip}"
  end

  def rate_limited?
    count = Rails.cache.read(rate_limit_key) || 0
    count >= RATE_LIMIT
  end

  def increment_rate_counter
    current = Rails.cache.read(rate_limit_key) || 0
    Rails.cache.write(rate_limit_key, current + 1, expires_in: RATE_WINDOW)
  end
end
