# Calculates the cost (in integer cents) of an Anthropic API call from token usage.
#
# PRICING numbers are US cents per 1,000,000 tokens.
#   e.g. Sonnet 4.6 = $3.00 / 1M input, $15.00 / 1M output  -> 300 / 1500 cents
#        Haiku 4.5  = $1.00 / 1M input, $5.00  / 1M output   -> 100 /  500 cents
# Keep these in sync with the official pricing page when models/prices change.
class CostCalculator
  PRICING = {
    "anthropic" => {
      "claude-sonnet-4-6" => { input: 300, output: 1500 },
      "claude-haiku-4-5"  => { input: 100, output: 500 }
    }
  }.freeze

  class UnknownModelError < StandardError; end

  # Returns the cost in integer cents. Raises UnknownModelError when the
  # provider/model pair is not in the PRICING table.
  def self.calculate_cents(provider:, model:, input_tokens:, output_tokens:)
    rates = PRICING.dig(provider, model)
    raise UnknownModelError, "No pricing for #{provider}/#{model}" if rates.nil?

    total = (input_tokens.to_i * rates[:input]) + (output_tokens.to_i * rates[:output])
    # total is in (cents * tokens); divide by 1M tokens, rounding to nearest cent.
    (total / 1_000_000.0).round
  end
end
