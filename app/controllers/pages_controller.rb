# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
    # Get a sampling of taxa with approved assets for the homepage preview
    @featured_taxa = Taxon.with_approved_assets.order(:scientific_name).limit(10)
  end

  def about
  end

  def terms
  end

  def upload_guide
  end
end

