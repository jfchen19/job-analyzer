FactoryBot.define do
  factory :analysis do
    association :job_posting
    association :resume
    match_level { "high" }
    key_requirements { JSON.generate([ "Rails", "PostgreSQL" ]) }
    matched_skills { JSON.generate([ "Rails" ]) }
    skill_gaps { JSON.generate([ "Kubernetes" ]) }
    cover_letter_suggestion { "建議強調 Rails 與測試經驗。" }
    raw_response { "{}" }
  end
end
