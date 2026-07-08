require "rails_helper"

RSpec.describe "測試地基" do
  it "RSpec 與 factory_bot 可用" do
    resume = create(:resume)
    expect(resume).to be_persisted
  end

  it "WebMock 封鎖對外真實請求（保證不碰真 API）" do
    expect {
      Net::HTTP.get(URI("https://api.anthropic.com/v1/messages"))
    }.to raise_error(WebMock::NetConnectNotAllowedError)
  end
end
