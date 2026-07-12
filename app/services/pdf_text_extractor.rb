require "open3"
require "tempfile"

# Extracts plain text from a PDF using poppler's `pdftotext -layout`, which
# preserves the visual layout far better than a positional reconstruction
# (fewer spurious blank lines inside wrapped bullets). Tolerates bad input:
# never raises to callers, returns a friendly error instead. Knows nothing
# about HTTP, DB, or Resume.
#
#   PdfTextExtractor.new(io).call
#   => { success: true,  text: "..." }
#   => { success: false, error: "..." }
class PdfTextExtractor
  def initialize(io)
    @io = io
  end

  def call
    return failure("請先選擇 PDF 檔") if @io.nil?

    text = normalize(extract)
    return failure("這份 PDF 抽不到文字(可能是掃描圖),請用可選取文字的 PDF 或直接貼上") if text.blank?

    { success: true, text: text }
  rescue => e
    Rails.logger.warn("[PdfTextExtractor] #{e.class}: #{e.message}")
    failure("無法讀取此 PDF(可能加密、損毀或非 PDF),請改用下方貼上")
  end

  private

  # Run `pdftotext -layout` on the uploaded bytes and return its stdout.
  # Uses the array form of the command (no shell) so the tempfile path can't be
  # interpreted as shell input.
  def extract
    bytes = @io.read
    raise "empty input" if bytes.nil? || bytes.empty?

    Tempfile.create([ "resume", ".pdf" ], binmode: true) do |file|
      file.write(bytes)
      file.flush
      out, err, status = Open3.capture3("pdftotext", "-layout", file.path, "-")
      raise "pdftotext exited #{status.exitstatus}: #{err}" unless status.success?
      out
    end
  end

  # `pdftotext -layout` output is already close to the visual layout. Just trim
  # each line's trailing whitespace and collapse any run of 3+ newlines into a
  # single blank line (keeps meaningful section breaks, drops the rest).
  def normalize(text)
    text.to_s.lines.map(&:rstrip).join("\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def failure(message)
    { success: false, error: message }
  end
end
