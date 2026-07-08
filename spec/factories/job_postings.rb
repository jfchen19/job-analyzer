FactoryBot.define do
  factory :job_posting do
    job_title { "Senior Rails Engineer" }
    company_name { "Acme Inc." }
    raw_content { "我們正在尋找資深 Rails 工程師，需熟悉 API 設計與測試。" }
    status { "pending" }
  end
end
