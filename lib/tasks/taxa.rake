# lib/tasks/taxa.rake
namespace :taxa do
  desc "Backfill group for existing taxa based on GBIF classification"
  task backfill_groups: :environment do
    puts "Backfilling specimen groups for existing taxa..."

    total = Taxon.count
    updated = 0
    skipped = 0
    errors = 0

    Taxon.find_each.with_index do |taxon, index|
      print "\rProcessing #{index + 1}/#{total}..."

      # Skip if already has a group
      if taxon.group.present?
        skipped += 1
        next
      end

      begin
        if taxon.gbif_key.present?
          # Re-fetch from GBIF to get classification data
          match = GbifClient.match(taxon.scientific_name)

          if match
            group = TaxonGroupResolver.resolve(match)
            taxon.update!(group: group)
            updated += 1
          else
            # No GBIF match, set to "other"
            taxon.update!(group: "other")
            updated += 1
          end
        else
          # No GBIF data, set to "other"
          taxon.update!(group: "other")
          updated += 1
        end
      rescue => e
        puts "\nError updating taxon #{taxon.id} (#{taxon.scientific_name}): #{e.message}"
        errors += 1
      end

      # Rate limit GBIF requests
      sleep(0.1) if taxon.gbif_key.present?
    end

    puts "\n\nBackfill complete!"
    puts "  Updated: #{updated}"
    puts "  Skipped (already had group): #{skipped}"
    puts "  Errors: #{errors}"
    puts "  Total: #{total}"
  end

  desc "Show group distribution for taxa"
  task group_stats: :environment do
    puts "Taxon group distribution:"
    puts "-" * 40

    TaxonGroupResolver::GROUPS.each do |group|
      count = Taxon.where(group: group).count
      approved = Taxon.with_approved_assets.where(group: group).count
      puts "  #{TaxonGroupResolver.icon(group)} #{group.ljust(20)} #{count.to_s.rjust(5)} (#{approved} with approved assets)"
    end

    nil_count = Taxon.where(group: nil).count
    puts "  ❓ #{'(no group)'.ljust(20)} #{nil_count.to_s.rjust(5)}"
    puts "-" * 40
    puts "  Total: #{Taxon.count}"
  end
end
