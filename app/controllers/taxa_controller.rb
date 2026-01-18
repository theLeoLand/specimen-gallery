# app/controllers/taxa_controller.rb
class TaxaController < ApplicationController
  def index
    @taxa = Taxon.with_approved_assets
    @current_group = params[:group].presence
    @groups = TaxonGroupResolver.all_with_metadata

    # Filter by group
    if @current_group.present? && @current_group != "all"
      @taxa = @taxa.where(group: @current_group)
    end

    # Search by name (specimen_name, scientific_name, or common_name)
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @taxa = @taxa
        .left_joins(:specimen_assets)
        .where("taxa.scientific_name ILIKE :q OR specimen_assets.specimen_name ILIKE :q OR specimen_assets.common_name ILIKE :q", q: search_term)
        .distinct
    end

    @taxa = @taxa.order(:scientific_name)
  end

  def show
    @taxon = Taxon.find(params[:id])
    @specimen_assets = @taxon.approved_assets

    if @specimen_assets.empty?
      head :not_found
    end
  end

  # GET /taxa/suggest?q=...
  # Returns JSON array of GBIF suggestions for autocomplete
  def suggest
    query = params[:q].to_s.strip
    suggestions = GbifClient.suggest(query, limit: 8)

    render json: suggestions.map { |s|
      {
        key: s[:key],
        name: s[:scientific_name],
        canonical: s[:canonical_name],
        rank: s[:rank]
      }
    }
  end
end
