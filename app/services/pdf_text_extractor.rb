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
    normalize(reader.pages.map(&:text).join("\n"))
  end

  # pdf-reader 用大量換行還原版面垂直間距,常產生成串多餘空白行。這裡去掉每行
  # 尾端空白,並把「連續 3 個以上的換行」壓成「一個空白行」——保留段落/區塊分隔,
  # 去掉噪音。
  def normalize(text)
    text.lines.map(&:rstrip).join("\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def failure(message)
    { success: false, error: message }
  end
end
