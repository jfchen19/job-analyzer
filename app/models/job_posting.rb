class JobPosting < ApplicationRecord
  STATUSES = %w[pending analyzed archived].freeze

  has_many :analyses, dependent: :destroy

  validates :job_title, presence: true
  validates :raw_content, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Most recent analysis for this posting (if any)
  def latest_analysis
    analyses.order(created_at: :desc).first
  end

  # source_url 由使用者輸入，直接進 link_to href 會有 javascript:/data: 等 XSS 風險。
  # 只在確定是 http(s) 時才回傳可當連結的值，否則回 nil（畫面改顯示純文字）。
  def safe_source_url
    source_url if source_url&.match?(%r{\Ahttps?://}i)
  end
end
