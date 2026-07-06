# Wraps an Anthropic API call, records token usage + cost into a UsageRecord,
# and returns the original response untouched.
#
#   tracker = LlmUsageTracker.new(
#     provider: "anthropic",
#     model: "claude-sonnet-4-6",
#     request_label: "analyze_job_posting",
#     recordable: job_posting
#   )
#   response = tracker.track { client.messages.create(...) }
#
# The official `anthropic` gem client is created here and picks up
# ENV["ANTHROPIC_API_KEY"] automatically (no initializer needed).
class LlmUsageTracker
  def initialize(provider: "anthropic", model:, request_label: nil, recordable: nil)
    @provider = provider
    @model = model
    @request_label = request_label
    @recordable = recordable
  end

  # Instantiate an Anthropic client (reads ANTHROPIC_API_KEY from ENV).
  def self.client
    Anthropic::Client.new
  end

  # Runs the block (which must return an Anthropic message response), records
  # usage, and returns that same response.
  def track
    response = yield

    usage = response.usage
    input_tokens  = usage&.input_tokens.to_i
    output_tokens = usage&.output_tokens.to_i

    cost_cents =
      begin
        CostCalculator.calculate_cents(
          provider: @provider,
          model: @model,
          input_tokens:,
          output_tokens:
        )
      rescue CostCalculator::UnknownModelError => e
        Rails.logger.warn("[LlmUsageTracker] #{e.message} — recording cost_cents: 0")
        0
      end

    UsageRecord.create!(
      provider: @provider,
      model: @model,
      input_tokens:,
      output_tokens:,
      cost_cents:,
      request_label: @request_label,
      recordable: @recordable
    )

    response
  end
end
