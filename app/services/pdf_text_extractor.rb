require "pdf/reader"

# Extracts plain text from a PDF, tolerating bad input. Never raises to callers;
# returns a friendly error instead. Knows nothing about HTTP, DB, or Resume.
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

    text = extract_text
    return failure("這份 PDF 抽不到文字(可能是掃描圖),請用可選取文字的 PDF 或直接貼上") if text.blank?

    { success: true, text: text }
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.warn("[PdfTextExtractor] #{e.class}: #{e.message}")
    failure("無法讀取此 PDF(可能加密、損毀或非 PDF),請改用下方貼上")
  rescue => e
    Rails.logger.warn("[PdfTextExtractor] #{e.class}: #{e.message}")
    failure("無法讀取此 PDF,請改用下方貼上")
  end

  private

  def extract_text
    reader = PDF::Reader.new(@io)
    reader.pages.map(&:text).join("\n").strip
  end

  def failure(message)
    { success: false, error: message }
  end
end
