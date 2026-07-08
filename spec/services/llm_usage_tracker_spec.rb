require "rails_helper"

RSpec.describe LlmUsageTracker do
  let(:job_posting) { create(:job_posting) }
  let(:usage) { double("usage", input_tokens: 1000, output_tokens: 500) }
  let(:response) { double("response", usage: usage) }

  def build_tracker(model:)
    described_class.new(
      provider: "anthropic", model: model,
      request_label: "analyze_job_posting", recordable: job_posting
    )
  end

  it "建立 UsageRecord 並記錄正確 tokens 與 cost" do
    tracker = build_tracker(model: "claude-sonnet-4-6")
    expect { tracker.track { response } }.to change(UsageRecord, :count).by(1)

    record = UsageRecord.last
    expect(record.input_tokens).to eq(1000)
    expect(record.output_tokens).to eq(500)
    expect(record.cost_cents).to eq(1) # 1000*300 + 500*1500 = 1050000 /1e6 = 1.05 -> 1
    expect(record.request_label).to eq("analyze_job_posting")
    expect(record.recordable).to eq(job_posting)
  end

  it "回傳原本的 response 物件不變" do
    tracker = build_tracker(model: "claude-sonnet-4-6")
    expect(tracker.track { response }).to eq(response)
  end

  it "未知 model 時吞掉錯誤、cost 記 0，仍建 record" do
    tracker = build_tracker(model: "unknown-model")
    expect { tracker.track { response } }.to change(UsageRecord, :count).by(1)
    expect(UsageRecord.last.cost_cents).to eq(0)
  end
end
