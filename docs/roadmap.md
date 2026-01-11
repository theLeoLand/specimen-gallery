# Specimen Gallery Roadmap

## Completed

### Step 1: GBIF Taxonomy Validation ✅
- Autocomplete suggestions from GBIF Species API
- Scientific name matching on upload
- Store GBIF taxon key, rank, canonical name, confidence
- `needs_review` flag for unverified names
- Admin queue shows GBIF verification status

### Cloudinary Background Removal ✅
- Optional "Remove background automatically (beta)" checkbox on upload form
- Accepts any image format (JPG, PNG, HEIC, WebP) when enabled
- Sends image to Cloudinary for AI background removal
- Downloads transformed PNG with transparency
- Stores metadata: `bg_removed`, `cloudinary_public_id`, `cloudinary_asset_url`
- **Graceful fallback:** If Cloudinary fails, attaches original image and sets `needs_review = true`
- Admin queue shows "Cutout generated" badge for processed images

---

## Future Steps

### Step 2: Computer Vision Taxon Suggestion
**Goal:** Use CV model to suggest species from uploaded image, compare with user-provided name.

**Database fields to add (SpecimenAsset):**
```ruby
# TODO: Migration for CV fields
# cv_taxon_source:string    # e.g., "inaturalist_vision", "plantnet"
# cv_taxon_id:string        # suggested taxon ID from CV
# cv_scientific_name:string # suggested scientific name
# cv_confidence:float       # CV confidence score (0.0-1.0)
# cv_mismatch:boolean       # true if CV suggestion differs from user-provided name
```

**Implementation notes:**
- Call CV API (iNaturalist Vision, PlantNet, or custom model) on image upload
- Compare CV suggestion with user-provided scientific name
- If mismatch, set `cv_mismatch = true` and flag for review
- Show CV suggestion in admin for comparison

---

### Step 3: Community ID Confirmation Votes
**Goal:** Allow community members to confirm or dispute specimen identifications.

**New model:**
```ruby
# TODO: Create IdVote model
# class IdVote < ApplicationRecord
#   belongs_to :specimen_asset
#   belongs_to :user, optional: true  # anonymous votes for now
#
#   # vote_type: enum { confirm: 0, disagree: 1 }
#   # suggested_taxon_id: integer (optional, for disagree votes)
#   # suggested_scientific_name: string (optional)
#   # created_at, updated_at
# end
```

**Implementation notes:**
- Add voting UI on taxon show page
- "Confirm ID" button increments confirmation count
- "Suggest different ID" opens modal for alternative suggestion
- After N confirmations, auto-approve if pending
- Track vote counts on SpecimenAsset or Taxon

---

### Step 4: User Accounts (Optional)
**Goal:** Track contributors, enable reputation system.

- Basic Devise/auth setup
- Link uploads to user accounts
- Contributor profiles with upload history
- Reputation based on approved uploads and correct IDs

---

### Step 5: Bulk Import
**Goal:** Allow batch uploads via CSV + ZIP.

- CSV with metadata (scientific_name, common_name, license, etc.)
- ZIP with images named to match CSV rows
- Background job processing
- Import status dashboard

---

## API Endpoints Reference

### GBIF Species API
- Suggest: `GET https://api.gbif.org/v1/species/suggest?q=...&limit=10`
- Match: `GET https://api.gbif.org/v1/species/match?name=...&verbose=true`

### iNaturalist Vision API (future)
- Requires API key and OAuth
- `POST https://api.inaturalist.org/v1/computervision/score_image`

### PlantNet API (future)
- `POST https://my-api.plantnet.org/v2/identify/all`
- Requires API key

