# Specimen Gallery

An open-source, community-built collection of high-quality, transparent-background specimen images for scientific illustration, education, and creative projects.

🌐 **Live:** [specimen.gallery](https://specimen.gallery)

📖 **[Project Vision](VISION.md)** — Guiding principles and what we're building

## Features

- **Community uploads** with automatic background removal (via Cloudinary)
- **GBIF integration** for taxonomic name validation
- **Community ID verification** — confirm or suggest identifications
- **Clean licensing** — CC0 (public domain) or CC-BY
- **Quality moderation** — auto-publish for verified names, review queue for uncertain IDs
- **Trait tagging** — sex, life stage, view angle, body part

## Tech Stack

- **Framework:** Ruby on Rails 8.1
- **Database:** PostgreSQL
- **Styling:** Tailwind CSS
- **Frontend:** Hotwire (Turbo + Stimulus)
- **File Storage:** Active Storage (S3 in production)
- **Background Removal:** Cloudinary AI
- **Taxonomy:** GBIF Species API
- **Hosting:** Fly.io

## Local Development

### Prerequisites

- Ruby 3.3+
- PostgreSQL (or SQLite for simple local dev)
- Node.js (for Tailwind CSS builds)

### Setup

```bash
# Clone the repo
git clone https://github.com/chispainnov/specimen-gallery.git
cd specimen-gallery

# Install dependencies
bundle install

# Set up database
bin/rails db:setup

# Copy environment template
cp .env.example .env
# Edit .env with your values (see below)

# Start development server
bin/dev
```

Visit `http://localhost:3000`

### Environment Variables

See `.env.example` for all options. At minimum for local dev:

```bash
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your_password
ADMIN_ROUTE_SECRET=your_secret
```

For background removal, you'll need Cloudinary credentials (free tier available).

### Admin Access

Visit `/your_route_secret/admin/specimen_assets` to access the moderation queue.

## Image Requirements

- **Transparent background** (PNG or WebP with alpha channel)
- **Single specimen** per image
- **Minimum 512×512 pixels**
- **Clean isolation** — no artifacts, halos, or background remnants
- **Accurate colors** — minimal post-processing

## Licensing

Contributors choose their license:

- **CC0** — Public domain, no attribution required
- **CC-BY** — Free to use, attribution required

By uploading, contributors confirm they hold rights to the image.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- **Bug reports:** Open an issue with steps to reproduce
- **Features:** Open an issue first to discuss
- **Code:** Small PRs preferred, follow Rails conventions

## Security

Found a vulnerability? See [SECURITY.md](SECURITY.md) for responsible disclosure.

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

Note: The *code* is MIT licensed. *Specimen images* in the gallery are licensed individually by their contributors (CC0 or CC-BY).

## Acknowledgments

- [GBIF](https://www.gbif.org/) for taxonomic data
- [Cloudinary](https://cloudinary.com/) for image processing
- All contributors who share their specimen images
