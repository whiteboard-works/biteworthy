# frozen_string_literal: true

require "timeout"

module Pdfs
  # Rewrites a PDF through Ghostscript so a menu exported at print
  # resolution fits the ingestion per-file limit. `/ebook` resamples the
  # embedded images to 150 dpi and re-encodes them, which keeps dish
  # names and prices legible — the vision call downsamples anyway.
  #
  # Returns a Tempfile holding the smaller PDF, or nil when Ghostscript is
  # missing, fails, overruns its time, or produced nothing smaller. The
  # caller then gives its usual too-large answer; a box without `gs` never
  # turns an upload into a 500.
  class Shrink
    TIMEOUT_SECONDS = 60
    ARGS = %w[
      -q -dSAFER -dBATCH -dNOPAUSE
      -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook
    ].freeze

    def self.call(source_path) = new(source_path).call

    def self.available?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "gs")) }
    end

    def initialize(source_path)
      @source_path = source_path.to_s
    end

    def call
      return nil unless self.class.available?

      output = Tempfile.new([ "shrunk", ".pdf" ], binmode: true)
      shrunk = run("gs", *ARGS, "-sOutputFile=#{output.path}", @source_path) &&
               File.size(output.path).between?(1, File.size(@source_path) - 1)
      return output.tap(&:rewind) if shrunk

      output.close!
      nil
    end

    private

    def run(*command)
      pid = Process.spawn(*command, in: File::NULL, out: File::NULL, err: File::NULL)
      _, status = Timeout.timeout(TIMEOUT_SECONDS) { Process.wait2(pid) }
      status.success?
    rescue Timeout::Error
      Rails.logger.warn("Pdfs::Shrink: gs exceeded #{TIMEOUT_SECONDS}s, killed")
      kill(pid)
      false
    rescue SystemCallError => e
      Rails.logger.warn("Pdfs::Shrink: #{e.class}: #{e.message}")
      false
    end

    def kill(pid)
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue SystemCallError
      nil
    end
  end
end
