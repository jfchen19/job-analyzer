FactoryBot.define do
  factory :usage_record do
    provider { "anthropic" }
    model { "claude-sonnet-4-6" }
    input_tokens { 1000 }
    output_tokens { 500 }
    cost_cents { 1 }
    request_label { "analyze_job_posting" }
  end
end
