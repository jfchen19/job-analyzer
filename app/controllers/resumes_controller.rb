class ResumesController < ApplicationController
  before_action :set_resume, only: %i[edit update set_default destroy]

  def index
    @resumes = Resume.order(is_default: :desc, updated_at: :desc)
  end

  def new
    @resume = Resume.new
  end

  def create
    @resume = Resume.new(resume_params)
    if @resume.save
      redirect_to resumes_path, notice: "履歷已建立"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @resume.update(resume_params)
      redirect_to resumes_path, notice: "履歷已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def set_default
    @resume.update!(is_default: true)
    redirect_to resumes_path, notice: "已設為預設履歷"
  end

  def destroy
    @resume.destroy
    redirect_to resumes_path, notice: "履歷已刪除"
  end

  private

  def set_resume
    @resume = Resume.find(params[:id])
  end

  def resume_params
    params.require(:resume).permit(:title, :content, :is_default)
  end
end
