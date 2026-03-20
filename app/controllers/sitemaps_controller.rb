class SitemapsController < ApplicationController
  def show
    @taxa = Taxon.with_approved_assets
    @specimen_assets = SpecimenAsset.where(status: "approved")

    respond_to do |format|
      format.xml
    end
  end
end
