# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_30_051516) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.string "reason", null: false
    t.string "reporter_ip"
    t.bigint "specimen_asset_id", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["specimen_asset_id", "status"], name: "index_flags_on_specimen_asset_id_and_status"
    t.index ["specimen_asset_id"], name: "index_flags_on_specimen_asset_id"
    t.index ["status"], name: "index_flags_on_status"
  end

  create_table "id_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "specimen_asset_id", null: false
    t.bigint "suggested_taxon_id"
    t.datetime "updated_at", null: false
    t.string "vote_kind", null: false
    t.string "voter_fingerprint", null: false
    t.string "voter_ip_hash", null: false
    t.index ["specimen_asset_id", "voter_fingerprint"], name: "index_id_votes_on_specimen_asset_id_and_voter_fingerprint", unique: true
    t.index ["specimen_asset_id"], name: "index_id_votes_on_specimen_asset_id"
    t.index ["suggested_taxon_id"], name: "index_id_votes_on_suggested_taxon_id"
    t.index ["voter_ip_hash"], name: "index_id_votes_on_voter_ip_hash"
  end

  create_table "specimen_assets", force: :cascade do |t|
    t.string "attribution_name"
    t.string "attribution_url"
    t.boolean "bg_removed", default: false, null: false
    t.text "cloudinary_asset_url"
    t.string "cloudinary_public_id"
    t.string "common_name"
    t.integer "confirm_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "id_status", default: "unverified", null: false
    t.string "license"
    t.string "life_stage"
    t.string "morph"
    t.boolean "needs_review", default: false, null: false
    t.text "notes"
    t.string "part"
    t.jsonb "qc_flags"
    t.string "region"
    t.string "sex"
    t.string "sha256_hash"
    t.string "specimen_name"
    t.string "status"
    t.integer "suggest_count", default: 0, null: false
    t.bigint "taxon_id"
    t.integer "top_suggested_count", default: 0, null: false
    t.bigint "top_suggested_taxon_id"
    t.datetime "updated_at", null: false
    t.string "view"
    t.index ["bg_removed"], name: "index_specimen_assets_on_bg_removed"
    t.index ["id_status"], name: "index_specimen_assets_on_id_status"
    t.index ["life_stage"], name: "index_specimen_assets_on_life_stage"
    t.index ["needs_review"], name: "index_specimen_assets_on_needs_review"
    t.index ["part"], name: "index_specimen_assets_on_part"
    t.index ["sex"], name: "index_specimen_assets_on_sex"
    t.index ["sha256_hash"], name: "index_specimen_assets_on_sha256_hash", unique: true
    t.index ["specimen_name"], name: "index_specimen_assets_on_specimen_name"
    t.index ["taxon_id"], name: "index_specimen_assets_on_taxon_id"
    t.index ["top_suggested_taxon_id"], name: "index_specimen_assets_on_top_suggested_taxon_id"
    t.index ["view"], name: "index_specimen_assets_on_view"
  end

  create_table "taxa", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "gbif_canonical_name"
    t.integer "gbif_confidence"
    t.integer "gbif_key"
    t.string "gbif_match_type"
    t.string "gbif_rank"
    t.string "group"
    t.string "rank"
    t.string "scientific_name", null: false
    t.string "taxon_id"
    t.string "taxon_source"
    t.datetime "updated_at", null: false
    t.index "lower((scientific_name)::text)", name: "index_taxa_on_lower_scientific_name", unique: true
    t.index ["gbif_key"], name: "index_taxa_on_gbif_key"
    t.index ["group"], name: "index_taxa_on_group"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "flags", "specimen_assets"
  add_foreign_key "id_votes", "specimen_assets"
  add_foreign_key "id_votes", "taxa", column: "suggested_taxon_id"
  add_foreign_key "specimen_assets", "taxa"
  add_foreign_key "specimen_assets", "taxa", column: "top_suggested_taxon_id"
end
