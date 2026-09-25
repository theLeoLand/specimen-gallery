# app/services/birefnet_background_remover.rb
# Local, self-hosted background removal for the bulk ingestion pipeline.
#
# Uses `rembg` with the BiRefNet "birefnet-general" model:
#   - MIT-licensed code AND weights (commercial use OK)  <-- important: the
#     rembg default model (bria-rmbg) is NON-commercial, so we pin the model.
#   - $0 per image, no API quotas, far better edges than generic removers.
#
# One-time setup on the machine running the pipeline:
#   pipx install "rembg[cpu,cli]"     (or: pip install "rembg[cpu,cli]")
#   # first run auto-downloads the ~1GB model to ~/.u2net/
#
# Runs OFFLINE/locally (not on the tiny Fly machine). Shells out to the rembg
# CLI with array args (no shell interpolation).
require "open3"
require "tmpdir"
require "securerandom"

class BirefnetBackgroundRemover
  MODEL = "birefnet-general".freeze
  # `-dc` = "decompose" alpha post-process recommended for the newer models
  # (produces a clean soft mask; faster and safer than `-a` for batch runs).
  EXTRA_ARGS = %w[-dc].freeze

  # Pin onnxruntime to a single thread. Its multi-threaded path intermittently
  # crashes on macOS ("recursive_mutex lock failed") when invoked in a loop.
  RUN_ENV = { "OMP_NUM_THREADS" => "1" }.freeze
  MAX_ATTEMPTS = 2 # one retry to ride out the flaky native crash

  class Error < StandardError; end
  class NotInstalled < Error; end

  # @return [String] path to the rembg executable (override with REMBG_BIN)
  def self.rembg_bin
    ENV["REMBG_BIN"].presence || "rembg"
  end

  # @return [Boolean] whether rembg is callable on this machine (memoized per run)
  def self.available?
    return @available unless @available.nil?

    _out, _err, status = Open3.capture3(rembg_bin, "--help")
    @available = status.success?
  rescue Errno::ENOENT
    @available = false
  end

  # Remove the background from an image, writing a transparent PNG.
  # @param input_path [String] path to the source image (jpg/png/webp)
  # @param output_path [String, nil] where to write the PNG. If omitted, a stable
  #   temp path is generated; the CALLER owns cleanup (do not rely on GC).
  # @return [String] path to the resulting transparent PNG
  def self.call(input_path, output_path: nil)
    raise NotInstalled, "rembg not found (set REMBG_BIN or `pipx install rembg[cpu,cli]`)" unless available?
    raise Error, "input image not found: #{input_path}" unless File.exist?(input_path)

    # NOTE: build a plain path (not Tempfile) so the file is never auto-unlinked
    # by the GC mid-pipeline. Cleanup is the caller's responsibility.
    output = output_path || File.join(Dir.tmpdir, "cutout-#{SecureRandom.hex(8)}.png")

    cmd = [ rembg_bin, "i", "-m", MODEL, *EXTRA_ARGS, input_path, output ]

    attempts = 0
    begin
      attempts += 1
      _out, err, status = Open3.capture3(RUN_ENV, *cmd)

      unless status.success? && File.exist?(output) && File.size(output).positive?
        raise Error, "rembg failed: #{err.presence || "no output produced"}"
      end
    rescue Error
      if attempts < MAX_ATTEMPTS
        File.delete(output) if File.exist?(output)
        sleep(0.5)
        retry
      end
      raise
    end

    output
  end
end
