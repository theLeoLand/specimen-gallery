# Specimen Gallery Format v0.1

Specification for specimen image metadata and file requirements.

## File Constraints

| Constraint | Value |
|------------|-------|
| Format | PNG, WebP |
| Minimum size | 512×512 px |
| Background | Transparent (alpha channel required) |
| Color space | sRGB |
| Max file size | 20 MB |

## Metadata Fields

### Required

| Field | Type | Description |
|-------|------|-------------|
| `scientific_name` | string | Binomial nomenclature (e.g., `"Papilio machaon"`) |
| `license` | enum | `"CC0"` or `"CC_BY"` |
| `image` | file | Attached image blob |

### Conditionally Required

| Field | Type | Condition | Description |
|-------|------|-----------|-------------|
| `attribution_name` | string | license = CC_BY | Creator name or organization |
| `attribution_url` | string | license = CC_BY | URL for attribution link |

### Recommended

| Field | Type | Description |
|-------|------|-------------|
| `common_name` | string | Vernacular name (e.g., `"Old World Swallowtail"`) |
| `taxon_source` | string | Taxonomy database (e.g., `"iNaturalist"`, `"GBIF"`, `"ITIS"`) |
| `taxon_id` | string | External taxon identifier |

### System Fields

| Field | Type | Description |
|-------|------|-------------|
| `status` | enum | `"pending"`, `"approved"`, `"rejected"` |
| `qc_flags` | jsonb | Quality control flags set during moderation |
| `created_at` | datetime | Upload timestamp |
| `updated_at` | datetime | Last modification timestamp |

## Status Values

- `pending` — Awaiting moderation
- `approved` — Visible in public gallery
- `rejected` — Failed moderation review

## QC Flags Schema

Optional flags stored in `qc_flags` (jsonb):

```json
{
  "low_resolution": true,
  "background_artifacts": true,
  "taxonomy_unverified": true,
  "duplicate_suspected": true
}
```

## Naming Conventions (Optional)

Recommended filename pattern for bulk imports:

```
<scientific_name_underscored>_<view>_<sequence>.<ext>
```

Examples:
- `papilio_machaon_dorsal_01.png`
- `apis_mellifera_lateral_01.webp`

Views: `dorsal`, `ventral`, `lateral`, `anterior`, `posterior`, `detail`

## Example Metadata

```json
{
  "scientific_name": "Papilio machaon",
  "common_name": "Old World Swallowtail",
  "license": "CC_BY",
  "attribution_name": "Jane Doe",
  "attribution_url": "https://example.com/janedoe",
  "taxon_source": "iNaturalist",
  "taxon_id": "52775",
  "status": "approved",
  "qc_flags": {},
  "created_at": "2025-12-31T10:00:00Z",
  "updated_at": "2025-12-31T12:30:00Z"
}
```

## Changelog

- **v0.1** — Initial specification

