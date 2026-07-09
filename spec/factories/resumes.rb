FactoryBot.define do
  factory :resume do
    sequence(:title) { |n| "履歷版本 #{n}" }
    content { "Ruby on Rails 後端工程師，5 年經驗，熟 PostgreSQL、Sidekiq、RSpec。" }
    is_default { false }
  end
end
