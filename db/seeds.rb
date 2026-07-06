# Idempotent seed: create a single default resume if none exists yet.
if Resume.default_resume.nil?
  Resume.create!(
    title: "後端工程師版本(預設)",
    is_default: true,
    content: <<~TEXT
      ## 技術技能
      - Ruby on Rails 3-5 年經驗
      - PostgreSQL、Redis
      - RESTful API 設計
      - Git、GitHub

      ## 工作經歷
      [請替換成你的實際履歷內容]

      ## 專案經歷
      [請替換成你的實際專案經歷]
    TEXT
  )
  puts "Seeded default resume."
else
  puts "Default resume already exists — skipping."
end
