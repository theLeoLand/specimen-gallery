# app/controllers/admin/flags_controller.rb
module Admin
  class FlagsController < ApplicationController
    include AdminAuth

    def index
      @flags = Flag.open_flags.newest_first.includes(specimen_asset: :taxon)
      @open_count = @flags.count
    end

    def resolve
      @flag = Flag.find(params[:id])
      @flag.update(status: "resolved")
      redirect_to admin_flags_path, notice: "Flag resolved."
    end

    def dismiss
      @flag = Flag.find(params[:id])
      @flag.update(status: "dismissed")
      redirect_to admin_flags_path, notice: "Flag dismissed."
    end

    def mark_needs_review
      @flag = Flag.find(params[:id])
      @flag.specimen_asset.update(needs_review: true)
      redirect_to admin_flags_path, notice: "Specimen marked for review."
    end
  end
end
