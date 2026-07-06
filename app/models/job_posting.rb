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
end
