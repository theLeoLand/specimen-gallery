# app/services/cutout_quality_checker.rb
# Automated quality gate for pipeline cutouts (transparent PNGs).
#
# Analyzes the alpha channel to catch the two failure modes the Monarch pilot
# exposed:
#   1. Background NOT removed / empty result  -> :reject (auto-skip)
#   2. Multiple disconnected subjects (cluster shots) -> :flag (send to review)
#
# Uses ruby-vips (already a dependency). Falls back to :flag on any analysis
# error so nothing is silently dropped.
require "vips"

class CutoutQualityChecker
  OPAQUE_ALPHA    = 128     # alpha >= this counts as "opaque"
  MAX_OPAQUE_RATIO = 0.82   # above => background likely not removed
  MIN_OPAQUE_RATIO = 0.004  # below => essentially nothing left
  GRID            = 48      # downsample resolution for blob detection
  MIN_BLOB_RATIO  = 0.012   # a blob must cover >= this fraction of cells to count
  MAX_SUBJECT_BLOBS = 1     # more significant blobs than this => multi-subject

  Result = Struct.new(:decision, :reasons, :opaque_ratio, :subject_blobs, keyword_init: true) do
    def ok?     = decision == :ok
    def reject? = decision == :reject
    def flag?   = decision == :flag
  end

  def self.call(png_path)
    new(png_path).call
  end

  def initialize(png_path)
    @png_path = png_path
  end

  def call
    img = Vips::Image.new_from_file(@png_path)
    unless img.bands >= 2 && img.has_alpha?
      return Result.new(decision: :flag, reasons: [ "no_alpha_channel" ], opaque_ratio: nil, subject_blobs: nil)
    end

    alpha = img.extract_band(img.bands - 1)
    opaque_mask = (alpha >= OPAQUE_ALPHA) # 255 where opaque, else 0
    opaque_ratio = opaque_mask.avg / 255.0

    reasons = []
    reasons << "background_not_removed" if opaque_ratio >= MAX_OPAQUE_RATIO
    reasons << "empty_cutout" if opaque_ratio <= MIN_OPAQUE_RATIO

    blobs = count_subject_blobs(opaque_mask)
    reasons << "multi_subject" if blobs && blobs > MAX_SUBJECT_BLOBS

    decision =
      if reasons.intersect?(%w[background_not_removed empty_cutout])
        :reject
      elsif reasons.any?
        :flag
      else
        :ok
      end

    Result.new(
      decision: decision,
      reasons: reasons,
      opaque_ratio: opaque_ratio.round(4),
      subject_blobs: blobs
    )
  rescue => e
    Rails.logger.warn("CutoutQualityChecker failed for #{@png_path}: #{e.class} #{e.message}")
    Result.new(decision: :flag, reasons: [ "qc_error" ], opaque_ratio: nil, subject_blobs: nil)
  end

  private

  # Count significant connected opaque regions on a coarse grid (cheap, robust).
  def count_subject_blobs(mask)
    hscale = GRID.to_f / mask.width
    vscale = GRID.to_f / mask.height
    small = mask.resize(hscale, vscale: vscale)

    pixels = small.to_a # [h][w][bands]
    h = pixels.length
    w = pixels.first.length
    grid = Array.new(h) { |y| Array.new(w) { |x| pixels[y][x][0] >= OPAQUE_ALPHA } }

    visited = Array.new(h) { Array.new(w, false) }
    min_cells = (h * w * MIN_BLOB_RATIO).ceil
    significant = 0

    h.times do |y|
      w.times do |x|
        next if !grid[y][x] || visited[y][x]

        size = 0
        stack = [ [ y, x ] ]
        visited[y][x] = true
        until stack.empty?
          cy, cx = stack.pop
          size += 1
          [ [ -1, 0 ], [ 1, 0 ], [ 0, -1 ], [ 0, 1 ] ].each do |dy, dx|
            ny = cy + dy
            nx = cx + dx
            next if ny.negative? || nx.negative? || ny >= h || nx >= w
            next if visited[ny][nx] || !grid[ny][nx]

            visited[ny][nx] = true
            stack << [ ny, nx ]
          end
        end
        significant += 1 if size >= min_cells
      end
    end

    significant
  rescue => e
    Rails.logger.warn("CutoutQualityChecker blob analysis failed: #{e.message}")
    nil
  end
end
