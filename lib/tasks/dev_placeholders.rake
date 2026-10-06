# lib/tasks/dev_placeholders.rake
#
# DEV-ONLY fake gallery filler so we can test browse pagination locally.
# These never ship: the task refuses to run outside development / local disk,
# blobs live in gitignored storage/, and they're tagged for one-command cleanup.
#
#   bin/rails specimen:seed_placeholders          # 500
#   COUNT=200 bin/rails specimen:seed_placeholders
#   bin/rails specimen:clear_placeholders

require "vips"

namespace :specimen do
  PLACEHOLDER_FLAG = "dev_placeholder"

  desc "DEV ONLY: seed N fake approved taxa+images (default 500)"
  task seed_placeholders: :environment do
    ensure_placeholder_sandbox!

    target = (ENV["COUNT"] || 500).to_i
    abort("COUNT must be > 0") if target < 1

    existing = placeholder_assets.count
    needed = target - existing
    if needed <= 0
      puts "[placeholders] already have #{existing} (target #{target}). Nothing to do."
      next
    end

    groups = TaxonGroupResolver::GROUPS
    created = 0
    start_index = existing + 1

    puts "[placeholders] creating #{needed} fake taxa (#{existing} already present)..."

    needed.times do |offset|
      i = start_index + offset
      name = "Placeholderia devensis-#{i.to_s.rjust(4, '0')}"
      group = groups[i % groups.size]

      taxon = Taxon.find_or_create_by!(scientific_name: name) do |t|
        t.group = group
      end

      asset = taxon.specimen_assets.build(
        specimen_name: "Placeholder #{i}",
        common_name: "Dev placeholder #{i}",
        license: "CC0",
        status: "approved",
        needs_review: false,
        bg_removed: true,
        notes: nil,
        qc_flags: { "placeholder" => true, "import_source" => PLACEHOLDER_FLAG }
      )

      png = placeholder_png_bytes(i)
      asset.image.attach(
        io: StringIO.new(png),
        filename: "placeholder-#{i}.png",
        content_type: "image/png"
      )

      unless asset.save
        puts "[placeholders] skip ##{i}: #{asset.errors.full_messages.join(', ')}"
        next
      end

      created += 1
      puts "[placeholders] #{created}/#{needed}  ##{asset.id}  #{name}" if (created % 50).zero? || created == needed
    end

    total = placeholder_assets.count
    puts "[placeholders] done. created=#{created} total_placeholders=#{total} browse_taxa=#{Taxon.with_approved_assets.count}"
    puts "[placeholders] wipe later with: bin/rails specimen:clear_placeholders"
  end

  desc "DEV ONLY: delete fake placeholder specimens+taxa"
  task clear_placeholders: :environment do
    ensure_placeholder_sandbox!

    assets = placeholder_assets.to_a
    taxon_ids = assets.map(&:taxon_id).uniq
    count = assets.size
    assets.each(&:destroy)

    deleted_taxa = Taxon.where(id: taxon_ids)
      .left_joins(:specimen_assets)
      .where(specimen_assets: { id: nil })
      .destroy_all
      .size

    puts "[placeholders] deleted #{count} assets, #{deleted_taxa} empty placeholder taxa."
  end
end

def placeholder_assets
  SpecimenAsset.where("qc_flags ->> 'import_source' = ?", "dev_placeholder")
end

def ensure_placeholder_sandbox!
  unless Rails.env.development?
    abort("Refusing: placeholders are development-only (RAILS_ENV=#{Rails.env}).")
  end

  url = ENV["DATABASE_URL"].to_s
  if url.match?(/neon\.tech|fly\.io|tigris|amazonaws\.com/i)
    abort("Refusing: DATABASE_URL looks like production. Unset it and use local Postgres.")
  end

  service = Rails.application.config.active_storage.service.to_s
  unless service == "local"
    abort("Refusing: Active Storage service is #{service.inspect}, not local disk.")
  end
end

# Unique solid-color PNG so SHA256 dedup doesn't collapse them all.
def placeholder_png_bytes(index)
  r = (index * 47) % 180 + 50
  g = (index * 91) % 180 + 50
  b = (index * 13) % 180 + 50
  img = Vips::Image.black(240, 240, bands: 3) + [ r, g, b ]
  # stamp a unique pixel so every file hashes differently even if colors collide
  img = img.draw_rect([ index % 256, (index / 2) % 256, (index / 3) % 256 ], 0, 0, 8, 8)
  img.write_to_buffer(".png")
end
