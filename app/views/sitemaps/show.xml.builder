xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url do
    xml.loc root_url
    xml.changefreq "daily"
    xml.priority "1.0"
  end

  xml.url do
    xml.loc browse_url
    xml.changefreq "daily"
    xml.priority "0.9"
  end

  xml.url do
    xml.loc about_url
    xml.changefreq "monthly"
    xml.priority "0.3"
  end

  xml.url do
    xml.loc upload_guide_url
    xml.changefreq "monthly"
    xml.priority "0.3"
  end

  @taxa.each do |taxon|
    xml.url do
      xml.loc taxon_url(taxon)
      xml.lastmod taxon.updated_at.iso8601
      xml.changefreq "weekly"
      xml.priority "0.8"
    end
  end

  @specimen_assets.each do |specimen|
    xml.url do
      xml.loc specimen_asset_url(specimen)
      xml.lastmod specimen.updated_at.iso8601
      xml.changefreq "monthly"
      xml.priority "0.7"
    end
  end
end
