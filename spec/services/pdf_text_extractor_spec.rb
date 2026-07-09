require "rails_helper"
require_relative "../support/pdf_fixtures"

RSpec.describe PdfTextExtractor do
  include PdfFixtures

  it "從可選取文字的 PDF 抽出文字" do
    result = described_class.new(StringIO.new(pdf_with_text("RESUME-CONTENT-ABC"))).call
    expect(result[:success]).to be(true)
    expect(result[:text]).to include("RESUME-CONTENT-ABC")
  end

  it "無文字層的 PDF(掃描圖型)回抽不到文字的 error" do
    result = described_class.new(StringIO.new(blank_pdf)).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to include("抽不到文字")
  end

  it "非 PDF 的 bytes 回 error、不 raise" do
    result = described_class.new(StringIO.new("這根本不是 PDF")).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end

  it "加密 PDF(PDF::Reader raise)回 error、不 raise" do
    allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError.new("encrypted"))
    result = described_class.new(StringIO.new(pdf_with_text)).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end

  it "nil io 回友善 error" do
    result = described_class.new(nil).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end

  describe "#normalize（私有，send 測）" do
    it "把多餘的連續空白行壓成單一空行、去掉每行尾端空白" do
      ext = described_class.new(nil)
      raw = "A\n\n\n\nB\n   \n\n\nC   \n"
      expect(ext.send(:normalize, raw)).to eq("A\n\nB\n\nC")
    end

    it "抽出的文字不含 3 個以上連續換行(端到端,以有間距的 PDF)" do
      result = described_class.new(StringIO.new(pdf_with_gaps)).call
      expect(result[:success]).to be(true)
      expect(result[:text]).not_to match(/\n{3,}/)
      expect(result[:text]).to include("EXPERIENCE").and include("SKILLS")
    end
  end
end
