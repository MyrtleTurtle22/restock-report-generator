# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  def new
    @service = ShopifyReportService.new
    @locations = @service.get_locations
    @tags = @service.get_tags
  end

  def create
    @service = ShopifyReportService.new
    
    begin
      report_data = @service.generate_report(
        start_date: params[:start_date],
        end_date: params[:end_date],
        origin_location_id: params[:origin_location_id],
        destination_location_id: params[:destination_location_id],
        tag: params[:tag].presence
      )

      send_data report_data,
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                disposition: 'attachment',
                filename: "restock_report_#{Date.today}.xlsx"
    rescue ArgumentError => e
      flash[:error] = e.message
      redirect_to new_report_path
    rescue => e
      flash[:error] = "Failed to generate report: #{e.message}"
      redirect_to new_report_path
    end
  end
end