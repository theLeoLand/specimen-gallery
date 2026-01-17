# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
    # Get taxa with approved assets, ordered by most recent upload (newest first)
    @featured_taxa = Taxon.ordered_by_latest_approved.limit(10)
  end

  def about
  end

  def terms
  end

  def upload_guide
  end
end

