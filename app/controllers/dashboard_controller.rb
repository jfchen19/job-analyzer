class DashboardController < ApplicationController
  def index
    @total_count    = JobPosting.count
    @analyzed_count = JobPosting.where(status: "analyzed").count

    match_counts = Analysis.group(:match_level).count
    @high_count   = match_counts["high"]   || 0
    @medium_count = match_counts["medium"] || 0
    @low_count    = match_counts["low"]    || 0

    @recent_analyses = Analysis.includes(:job_posting, :resume)
                               .order(created_at: :desc)
                               .limit(5)

    @month_cost_cents = UsageRecord.where(created_at: Time.current.all_month).sum(:cost_cents)
  end
end
