# Analyzes a JobPosting against a Resume via the Anthropic API and persists an
# Analysis. Returns the Analysis on success, or nil (with #error set) on failure.
#
#   service = JobAnalyzerService.new(job_posting:, resume:)
#   analysis = service.analyze
#   service.error  # => friendly message when analyze returned nil
class JobAnalyzerService
  DEFAULT_MODEL = "claude-sonnet-4-6".freeze
  MAX_TOKENS = 2000

  SYSTEM_PROMPT = <<~PROMPT.freeze
    你是一位資深的技術招募顧問,專門幫助軟體工程師分析職缺匹配度。
    請根據提供的職缺描述和應徵者履歷,進行客觀的分析。
    你必須只回傳合法的 JSON,不要包含任何其他文字、解釋或 markdown 格式。
  PROMPT

  attr_reader :error

  def initialize(job_posting:, resume:)
    @job_posting = job_posting
    @resume = resume
    @error = nil
  end

  def analyze
    model = ENV.fetch("ANTHROPIC_MODEL", DEFAULT_MODEL)

    tracker = LlmUsageTracker.new(
      provider: "anthropic",
      model: model,
      request_label: "analyze_job_posting",
      recordable: @job_posting
    )

    response = tracker.track do
      LlmUsageTracker.client.messages.create(
        model: model,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        messages: [ { role: "user", content: user_prompt } ]
      )
    end

    raw = extract_text(response)
    parsed = parse_json(raw)

    if parsed.nil?
      # Keep the raw response so we can debug malformed model output.
      Rails.logger.warn("[JobAnalyzerService] JSON parse failed. Raw: #{raw&.truncate(500)}")
      @error = "分析結果格式不正確,請再試一次"
      return nil
    end

    build_analysis(parsed, raw)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.error("[JobAnalyzerService] API error: #{e.class}: #{e.message}")
    @error = "呼叫 AI 服務時發生問題,請確認 API key 設定並稍後再試"
    nil
  rescue => e
    Rails.logger.error("[JobAnalyzerService] #{e.class}: #{e.message}")
    @error = "分析過程發生非預期錯誤,請稍後再試"
    nil
  end

  private

  def build_analysis(parsed, raw)
    match_level = parsed["match_level"].to_s
    match_level = "low" unless Analysis::MATCH_LEVELS.include?(match_level)

    analysis = Analysis.create!(
      job_posting: @job_posting,
      resume: @resume,
      match_level: match_level,
      key_requirements: JSON.generate(Array(parsed["key_requirements"])),
      matched_skills: JSON.generate(Array(parsed["matched_skills"])),
      skill_gaps: JSON.generate(Array(parsed["skill_gaps"])),
      cover_letter_suggestion: parsed["cover_letter_suggestion"].to_s,
      raw_response: raw
    )

    @job_posting.update!(status: "analyzed")
    analysis
  end

  # Concatenate all text blocks from the message response.
  def extract_text(response)
    Array(response.content)
      .select { |block| block.type == :text }
      .map(&:text)
      .join
      .strip
  end

  # Parse the model's reply into a Hash, tolerating common wrappers the model
  # may add despite the "JSON only" instruction: ```json fences, or a sentence
  # of prose before/after the object.
  def parse_json(raw)
    return nil if raw.blank?

    text = raw.strip
    if text.start_with?("```")
      text = text.sub(/\A```[a-zA-Z]*\s*/, "").sub(/```\s*\z/, "").strip
    end

    JSON.parse(text)
  rescue JSON::ParserError
    # Last resort: grab the first {...} block anywhere in the text.
    if (m = raw.match(/\{.*\}/m))
      JSON.parse(m[0]) rescue nil
    end
  end

  def user_prompt
    <<~PROMPT
      ## 職缺資訊
      公司:#{@job_posting.company_name}
      職位:#{@job_posting.job_title}

      ## 職缺描述
      #{@job_posting.raw_content}

      ## 應徵者履歷
      #{@resume.content}

      ## 請分析並回傳以下 JSON 格式:
      {
        "match_level": "high|medium|low",
        "key_requirements": ["技能1", "技能2"],
        "matched_skills": ["符合的技能1"],
        "skill_gaps": ["缺少的技能1"],
        "cover_letter_suggestion": "針對這個職缺,建議在自我介紹中強調...(100-200字)"
      }

      判斷標準:
      - high: 符合 80% 以上的核心要求
      - medium: 符合 50-80% 的核心要求
      - low: 符合 50% 以下的核心要求
    PROMPT
  end
end
