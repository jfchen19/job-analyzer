require "http"
require "nokogiri"

# Fetches a 104 job posting and returns parsed fields, or a friendly error.
#
#   FetchJobContentService.new(url).call
#   => { success: true,  job_title:, company_name:, raw_content: }
#   => { success: false, error: "..." }
#
# IMPORTANT REALITY: 104 sits behind Cloudflare's "challenge" mitigation. A
# plain server-side HTTP request (this service) is answered with an HTTP 403
# "Just a moment..." page for BOTH the JSON content endpoint and the HTML page,
# unless the request happens to escape the challenge. So this service is
# best-effort: when it can't get through, it returns success: false and the
# controller/UI falls back to manual JD entry (the reliable path).
#
# Field paths for the JSON endpoint follow 104's documented content structure
# (data.header.jobName / custName, data.jobDetail.jobDescription). They could
# not be live-verified here because of the Cloudflare block; confirm them
# against a real response if/when the challenge is bypassable.
class FetchJobContentService
  USER_AGENT =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36".freeze

  TIMEOUT = 10 # seconds

  def initialize(url)
    @url = url.to_s.strip
  end

  def call
    job_id = extract_job_id(@url)
    return failure("網址格式不正確，請確認是 104 職缺連結（例如 https://www.104.com.tw/job/xxxxx）") if job_id.blank?

    # Tier 1: JSON content endpoint
    result = fetch_via_json(job_id)
    return result if result[:success]

    # Tier 2: HTML page + Nokogiri selectors
    result = fetch_via_html(job_id)
    return result if result[:success]

    # Tier 3: give up gracefully
    failure("無法自動抓取此頁面（104 可能有防爬蟲保護），請手動貼上 JD 內容")
  rescue HTTP::TimeoutError
    failure("抓取逾時，請稍後再試或手動貼上 JD 內容")
  rescue => e
    Rails.logger.warn("[FetchJobContentService] #{e.class}: #{e.message}")
    failure("無法抓取此頁面，請手動貼上 JD 內容")
  end

  private

  # Accepts:
  #   https://www.104.com.tw/job/8wjw0
  #   https://www.104.com.tw/job/8wjw0?jobsource=...
  #   ...?jobno=1234567  (older style)
  def extract_job_id(url)
    return nil if url.blank?

    if (m = url.match(%r{104\.com\.tw/job/([A-Za-z0-9]+)}))
      m[1]
    elsif (m = url.match(/[?&]jobno=([A-Za-z0-9]+)/))
      m[1]
    end
  end

  def fetch_via_json(job_id)
    endpoint = "https://www.104.com.tw/job/ajax/content/#{job_id}"
    resp = http_client(referer: "https://www.104.com.tw/job/#{job_id}")
             .headers("Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest")
             .get(endpoint)

    return failure(:blocked) if challenged?(resp)

    body = resp.to_s
    data = JSON.parse(body)["data"]
    return failure(:blocked) if data.blank?

    job_title    = data.dig("header", "jobName").to_s.strip
    company_name = data.dig("header", "custName").to_s.strip
    raw_content  = extract_json_description(data)

    return failure(:blocked) if job_title.blank? || raw_content.blank?

    success(job_title:, company_name:, raw_content:)
  rescue JSON::ParserError
    failure(:blocked)
  end

  # Pulls the description plus a few useful condition fields into plain text.
  def extract_json_description(data)
    detail = data["jobDetail"] || {}
    parts = []
    parts << detail["jobDescription"]
    if (cond = data["condition"])
      parts << "\n【工作條件】"
      parts << "工作經歷：#{cond['workExp']}" if cond["workExp"].present?
      parts << "學歷要求：#{cond['edu']}"     if cond["edu"].present?
      parts << "科系要求：#{Array(cond['major']).join('、')}" if cond["major"].present?
      parts << "擅長工具：#{Array(cond['specialty']).map { |s| s['description'] }.join('、')}" if cond["specialty"].present?
      parts << "工作技能：#{Array(cond['skill']).map { |s| s['description'] }.join('、')}" if cond["skill"].present?
    end
    parts.compact.join("\n").strip
  end

  def fetch_via_html(job_id)
    page_url = "https://www.104.com.tw/job/#{job_id}"
    resp = http_client(referer: "https://www.104.com.tw/").get(page_url)
    return failure(:blocked) if challenged?(resp)

    doc = Nokogiri::HTML(resp.to_s)
    job_title    = text_from(doc, "h1.job-name", ".job-header h1", "h1")
    company_name = text_from(doc, ".company-name", "[data-v] .company", ".job-header .name")
    raw_content  = text_from(doc, ".job-description", "#job-description", ".content")

    return failure(:blocked) if job_title.blank? || raw_content.blank?

    success(job_title:, company_name:, raw_content:)
  end

  def text_from(doc, *selectors)
    selectors.each do |sel|
      node = doc.at_css(sel)
      return node.text.strip if node && node.text.strip.present?
    end
    nil
  end

  def http_client(referer:)
    HTTP
      .timeout(connect: 5, write: 5, read: TIMEOUT)
      .headers(
        "User-Agent" => USER_AGENT,
        "Referer" => referer,
        "Accept-Language" => "zh-TW,zh;q=0.9,en;q=0.8"
      )
      .follow
  end

  # Cloudflare challenge / anti-bot detection.
  def challenged?(resp)
    return true if resp.status.code == 403
    return true if resp.headers["Cf-Mitigated"].present?

    ctype = resp.headers["Content-Type"].to_s
    ctype.include?("text/html") && resp.to_s.include?("Just a moment")
  end

  def success(job_title:, company_name:, raw_content:)
    { success: true, job_title:, company_name:, raw_content: }
  end

  # Internal :blocked marker collapses to the tiered fallback; a String is a
  # user-facing message returned directly.
  def failure(message)
    return { success: false, error: nil, blocked: true } if message == :blocked

    { success: false, error: message }
  end
end
