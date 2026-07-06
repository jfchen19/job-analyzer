class JobPostingsController < ApplicationController
  before_action :set_job_posting, only: %i[show analyze archive destroy]

  def index
    @job_postings = JobPosting.order(created_at: :desc)
  end

  def new
    @job_posting = JobPosting.new
  end

  def create
    @job_posting = JobPosting.new(job_posting_params)
    if @job_posting.save
      redirect_to @job_posting, notice: "職缺已建立"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @analysis = @job_posting.latest_analysis
  end

  # Fetch JD content from a 104 URL and return JSON to populate the new form.
  # Collection route — no record exists yet.
  def fetch_content
    result = FetchJobContentService.new(params[:source_url]).call

    if result[:success]
      render json: {
        job_title: result[:job_title],
        company_name: result[:company_name],
        raw_content: result[:raw_content]
      }
    else
      render json: { error: result[:error] || "無法抓取此頁面,請手動貼上 JD 內容" },
             status: :unprocessable_entity
    end
  end

  def analyze
    resume = Resume.default_resume
    if resume.nil?
      redirect_to resumes_path, alert: "請先建立一份預設履歷,才能進行分析"
      return
    end

    service = JobAnalyzerService.new(job_posting: @job_posting, resume: resume)
    if service.analyze
      redirect_to @job_posting, notice: "分析完成"
    else
      redirect_to @job_posting, alert: service.error || "分析失敗,請稍後再試"
    end
  end

  def archive
    @job_posting.update!(status: "archived")
    redirect_to job_postings_path, notice: "職缺已封存"
  end

  def destroy
    @job_posting.destroy
    redirect_to job_postings_path, notice: "職缺已刪除"
  end

  private

  def set_job_posting
    @job_posting = JobPosting.find(params[:id])
  end

  def job_posting_params
    params.require(:job_posting).permit(:company_name, :job_title, :raw_content, :source_url)
  end
end
