class Resume < ApplicationRecord
  has_many :analyses, dependent: :nullify

  validates :title, presence: true
  validates :content, presence: true

  # NOTE: intentionally a class method, not a `scope`. A scope whose block
  # returns nil (no default exists) silently returns `all` instead — which
  # would break callers that check `Resume.default_resume.nil?`.
  def self.default_resume
    where(is_default: true).order(:id).first
  end

  before_save :unset_other_defaults, if: -> { is_default? }

  private

  # When this resume is marked default, clear the flag on all others.
  def unset_other_defaults
    Resume.where.not(id: id).update_all(is_default: false)
  end
end
