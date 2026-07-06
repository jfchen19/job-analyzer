class Analysis < ApplicationRecord
  MATCH_LEVELS = %w[high medium low].freeze

  belongs_to :job_posting
  belongs_to :resume

  validates :match_level, inclusion: { in: MATCH_LEVELS }

  def parsed_key_requirements
    JSON.parse(key_requirements) rescue []
  end

  def parsed_matched_skills
    JSON.parse(matched_skills) rescue []
  end

  def parsed_skill_gaps
    JSON.parse(skill_gaps) rescue []
  end
end
