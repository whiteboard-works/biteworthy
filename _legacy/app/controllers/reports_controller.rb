class ReportsController < ApplicationController
  before_action :set_report, only: [:show, :edit, :update, :destroy]
  before_action :check_recaptcha, only: [ :create ]
  def new
    @report = Report.new
  end

  def edit
  end

  def create
    @report = Report.new(report_params)

    respond_to do |format|
      if @recaptcha_success && @report.valid?
        @report.save
        format.html { redirect_to root_path, notice: 'Report was successfully created.' }
      else
        format.html { render :new }
      end
    end
  end

  private
  def check_recaptcha
    @recaptcha_success = verify_recaptcha
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_report
    @report = Report.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def report_params
    params.require(:report).permit(:name, :description, :page_url, :report_type)
  end
end
