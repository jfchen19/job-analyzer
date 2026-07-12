require "rails_helper"

RSpec.describe JobAnalyzerService do
  let(:job_posting) { create(:job_posting) }
  let(:resume) { create(:resume, is_default: true) }
  let(:service) { described_class.new(job_posting: job_posting, resume: resume) }

  # 假 usage / content block，讓 tracker 與 extract_text 都能運作
  def fake_response(text)
    usage = double("usage", input_tokens: 1000, output_tokens: 500)
    block = double("block", type: :text, text: text)
    double("response", usage: usage, content: [ block ])
  end

  # 把 LlmUsageTracker.client 換成回傳指定 response 的假 client
  def stub_client_returning(text)
    messages = double("messages")
    allow(messages).to receive(:create).and_return(fake_response(text))
    allow(LlmUsageTracker).to receive(:client).and_return(double("client", messages: messages))
  end

  let(:valid_json) do
    JSON.generate(
      "match_level" => "high",
      "key_requirements" => [ "Rails", "SQL" ],
      "matched_skills" => [ "Rails" ],
      "skill_gaps" => [ "K8s" ],
      "cover_letter_suggestion" => "強調 Rails 經驗"
    )
  end

  describe "#analyze 成功" do
    before { stub_client_returning(valid_json) }

    it "建立 Analysis 並把 job_posting 轉為 analyzed" do
      analysis = service.analyze
      expect(analysis).to be_a(Analysis)
      expect(analysis.match_level).to eq("high")
      expect(analysis.parsed_key_requirements).to eq([ "Rails", "SQL" ])
      expect(job_posting.reload.status).to eq("analyzed")
    end

    it "同時建立一筆 UsageRecord（記帳）" do
      expect { service.analyze }.to change(UsageRecord, :count).by(1)
    end
  end

  it "非法 match_level 收斂為 low" do
    stub_client_returning(JSON.generate("match_level" => "excellent",
      "key_requirements" => [], "matched_skills" => [], "skill_gaps" => [],
      "cover_letter_suggestion" => ""))
    expect(service.analyze.match_level).to eq("low")
  end

  it "回應非 JSON 時不建 Analysis、設 error、回 nil" do
    stub_client_returning("這不是 JSON")
    expect {
      expect(service.analyze).to be_nil
    }.not_to change(Analysis, :count)
    expect(service.error).to be_present
  end

  it "APIError 被攔截：設 error、回 nil" do
    messages = double("messages")
    allow(messages).to receive(:create).and_raise(
      Anthropic::Errors::APIError.new(url: "https://api.anthropic.com/v1/messages", message: "boom")
    )
    allow(LlmUsageTracker).to receive(:client).and_return(double("client", messages: messages))

    expect(service.analyze).to be_nil
    expect(service.error).to be_present
  end

  describe "#parse_json 容錯（私有，send 測）" do
    it "純 JSON" do
      expect(service.send(:parse_json, '{"a":1}')).to eq("a" => 1)
    end

    it "剝去 ```json code fence" do
      expect(service.send(:parse_json, "```json\n{\"a\":1}\n```")).to eq("a" => 1)
    end

    it "前後夾雜文字時抓第一個 {...}" do
      expect(service.send(:parse_json, "說明：\n{\"a\":1}\n以上")).to eq("a" => 1)
    end

    it "無法解析回 nil" do
      expect(service.send(:parse_json, "完全不是 json")).to be_nil
    end

    it "空字串回 nil" do
      expect(service.send(:parse_json, "")).to be_nil
    end
  end

  describe "#extract_text（私有，send 測）" do
    it "串接所有 type == :text 的 block" do
      blocks = [ double(type: :text, text: "前段"), double(type: :text, text: "後段") ]
      response = double("response", content: blocks)
      expect(service.send(:extract_text, response)).to eq("前段後段")
    end

    it "過濾掉非 :text 的 block（例如 tool_use）" do
      blocks = [
        double(type: :text, text: "保留"),
        double(type: :tool_use, text: "應被略過"),
        double(type: :text, text: "這段")
      ]
      response = double("response", content: blocks)
      expect(service.send(:extract_text, response)).to eq("保留這段")
    end
  end
end
