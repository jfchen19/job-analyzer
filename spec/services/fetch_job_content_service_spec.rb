require "rails_helper"

RSpec.describe FetchJobContentService do
  describe "#extract_job_id（send）" do
    {
      "https://www.104.com.tw/job/8wjw0" => "8wjw0",
      "https://www.104.com.tw/job/8wjw0?jobsource=joblist" => "8wjw0",
      "https://www.104.com.tw/jobs/main/?jobno=1234567" => "1234567"
    }.each do |url, expected|
      it "從 #{url} 取出 #{expected}" do
        expect(described_class.new(url).send(:extract_job_id, url)).to eq(expected)
      end
    end

    it "非 104 網址回 nil" do
      expect(described_class.new("https://google.com").send(:extract_job_id, "https://google.com")).to be_nil
    end
  end

  describe "#challenged?（send）" do
    let(:service) { described_class.new("https://www.104.com.tw/job/8wjw0") }

    it "403 視為被擋" do
      resp = double(status: double(code: 403), headers: {}, to_s: "")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "有 Cf-Mitigated header 視為被擋" do
      resp = double(status: double(code: 200), headers: { "Cf-Mitigated" => "challenge" }, to_s: "")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "html 內含 Just a moment 視為被擋" do
      resp = double(status: double(code: 200),
                    headers: { "Content-Type" => "text/html" },
                    to_s: "<html>Just a moment...</html>")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "正常 JSON 回應不算被擋" do
      resp = double(status: double(code: 200),
                    headers: { "Content-Type" => "application/json" }, to_s: "{}")
      expect(service.send(:challenged?, resp)).to be(false)
    end
  end

  describe "#call" do
    let(:job_id) { "8wjw0" }
    let(:url) { "https://www.104.com.tw/job/#{job_id}" }
    let(:json_endpoint) { "https://www.104.com.tw/job/ajax/content/#{job_id}" }

    it "JSON 端點成功時回傳解析欄位" do
      body = JSON.generate(
        "data" => {
          "header" => { "jobName" => "Rails Engineer", "custName" => "Acme" },
          "jobDetail" => { "jobDescription" => "我們正在找 Rails 工程師" }
        }
      )
      stub_request(:get, json_endpoint)
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = described_class.new(url).call
      expect(result[:success]).to be(true)
      expect(result[:job_title]).to eq("Rails Engineer")
      expect(result[:company_name]).to eq("Acme")
      expect(result[:raw_content]).to include("我們正在找 Rails 工程師")
    end

    it "兩層都被 403 擋時回手動貼上的友善錯誤" do
      stub_request(:get, json_endpoint).to_return(status: 403, body: "Just a moment...")
      stub_request(:get, url).to_return(status: 403, body: "Just a moment...")

      result = described_class.new(url).call
      expect(result[:success]).to be(false)
      expect(result[:error]).to include("手動貼上")
    end
  end
end
