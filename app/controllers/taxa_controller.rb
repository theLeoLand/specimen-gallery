# app/controllers/taxa_controller.rb
class TaxaController < ApplicationController
  # 5-across grid × 26 rows. Extra pages appear only after the gallery outgrows this.
  BROWSE_PER_PAGE = 130

  def index
    # ID status filter: default to "all" to show gallery liveliness
    @id_status_filter = params[:id_status].presence || "all"
    @taxa = Taxon.with_assets_by_id_status(@id_status_filter)

    @current_group = params[:group].presence
    @groups = TaxonGroupResolver.all_with_metadata

    # Store filter params
    @filters = {
      sex: params[:sex].presence,
      life_stage: params[:life_stage].presence,
      view: params[:view].presence,
      part: params[:part].presence
    }

    # Filter by group
    if @current_group.present? && @current_group != "all"
      @taxa = @taxa.where(group: @current_group)
    end

    # Literal name matches stay first. Embeddings add records whose wording is close
    # even when the typed text is not stored on the specimen.
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      text_ids = @taxa
        .left_joins(:specimen_assets)
        .where(
          "taxa.scientific_name ILIKE :q OR specimen_assets.specimen_name ILIKE :q OR " \
          "specimen_assets.common_name ILIKE :q OR specimen_assets.morph ILIKE :q OR " \
          "specimen_assets.region ILIKE :q",
          q: search_term
        )
        .distinct
        .pluck("taxa.id")
      semantic_ids = SpecimenEmbedder.matching_taxon_ids(params[:q], taxon_scope: @taxa, id_status: @id_status_filter)
      @text_match_ids = text_ids
      @taxa = @taxa.where(id: (text_ids + semantic_ids).uniq)
    end

    # Filter by specimen traits (only show taxa that have matching specimens)
    if @filters.values.any?(&:present?)
      asset_conditions = { status: "approved" }
      asset_conditions[:id_status] = @id_status_filter unless @id_status_filter == "all"

      @taxa = @taxa
        .joins(:specimen_assets)
        .where(specimen_assets: asset_conditions)
        .then { |scope| @filters[:sex].present? ? scope.where(specimen_assets: { sex: @filters[:sex] }) : scope }
        .then { |scope| @filters[:life_stage].present? ? scope.where(specimen_assets: { life_stage: @filters[:life_stage] }) : scope }
        .then { |scope| @filters[:view].present? ? scope.where(specimen_assets: { view: @filters[:view] }) : scope }
        .then { |scope| @filters[:part].present? ? scope.where(specimen_assets: { part: @filters[:part] }) : scope }
        .distinct
    end

    # The gallery scopes join specimens and call DISTINCT. Postgres rejects an
    # ORDER BY expression (the "exact name first" rank) unless that expression
    # is also selected. Collapse to ids first, then sort the plain taxon rows.
    @taxa = Taxon.where(id: @taxa.except(:order).reselect("taxa.id"))
    @taxa = if @text_match_ids.present?
      list = @text_match_ids.map(&:to_i).join(",")
      @taxa.order(Arel.sql("CASE WHEN taxa.id IN (#{list}) THEN 0 ELSE 1 END"), :scientific_name)
    else
      @taxa.order(:scientific_name)
    end
    @gallery_species_count = matching_species_count
    @gallery_image_count = matching_image_count
    paginate_browse
  end

  def show
    @taxon = Taxon.find(params[:id])
    # Respect id_status filter if passed from browse page
    @id_status_filter = params[:id_status].presence
    @specimen_assets = if @id_status_filter.present? && @id_status_filter != "all"
      @taxon.assets_by_id_status(@id_status_filter).includes(image_attachment: :blob)
    else
      @taxon.approved_assets.includes(image_attachment: :blob)
    end

    @vernacular_name = @taxon.vernacular_name

    if @specimen_assets.empty?
      head :not_found
    end
  end

  # Plain-text citation: scientific name, license, canonical taxon URL.
  def citation
    taxon = Taxon.find(params[:id])
    if taxon.approved_assets.none?
      head :not_found
      return
    end

    render plain: helpers.taxon_citation(taxon)
  end

  # GET /gbif/:gbif_key — permanent redirect onto the canonical taxon page.
  def gbif
    taxon = Taxon.with_approved_assets.find_by(gbif_key: params[:gbif_key])
    if taxon
      redirect_to taxon_path(taxon), status: :moved_permanently
    else
      head :not_found
    end
  end

  # GET /gbif/:gbif_key/image — the current hero cutout for that GBIF taxon.
  def gbif_image
    taxon = Taxon.find_by(gbif_key: params[:gbif_key])
    specimen = taxon&.hero_asset
    if specimen&.image&.attached?
      redirect_to rails_blob_path(specimen.image, disposition: "inline"),
        status: :found
    else
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

  private

  def paginate_browse
    @total_count = @gallery_species_count
    @total_pages = [ (@total_count / BROWSE_PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i
    @page = 1 if @page < 1
    @page = @total_pages if @page > @total_pages
    @taxa = @taxa.offset((@page - 1) * BROWSE_PER_PAGE).limit(BROWSE_PER_PAGE)
  end

  def matching_species_count
    count = @taxa.except(:order).count
    count.is_a?(Hash) ? count.size : count
  end

  def matching_image_count
    taxon_ids = @taxa.except(:order).reselect("taxa.id")
    scope = SpecimenAsset.where(status: "approved").where(taxon_id: taxon_ids)

    scope = case @id_status_filter
    when "verified" then scope.where(id_status: "verified")
    when "unverified" then scope.where.not(id_status: "verified")
    else scope
    end

    scope = scope.where(sex: @filters[:sex]) if @filters[:sex].present?
    scope = scope.where(life_stage: @filters[:life_stage]) if @filters[:life_stage].present?
    scope = scope.where(view: @filters[:view]) if @filters[:view].present?
    scope = scope.where(part: @filters[:part]) if @filters[:part].present?
    scope.count
  end
end
