require "rails_helper"

RSpec.describe "系統測試基建", type: :system do
  it "能用 headless Chrome 載入首頁" do
    visit "/"
    expect(page).to have_content("職缺")
  end
end
