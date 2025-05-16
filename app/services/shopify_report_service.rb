require_relative 'sales'
require_relative 'inventory'
require 'caxlsx'
require 'dotenv'
require 'logger'
require 'shopify_api'
require 'date'

class ShopifyReportService
  def initialize
    Dotenv.load(File.expand_path("../../.env", __dir__))

    ShopifyAPI::Context.setup(
      api_key: ENV['SHOPIFY_API_KEY'],
      api_secret_key: ENV['SHOPIFY_API_SECRET'],
      host_name: "https://225c-98-113-19-129.ngrok-free.app",
      scope: "read_inventory, read_orders, read_products, read_locations, read_assigned_fulfillment_orders, read_fulfillments, read_merchant_managed_fulfillment_orders, read_third_party_fulfillment_orders, read_custom_fulfillment_orders, read_fulfillment_constraint_rules",
      is_embedded: true,
      is_private: true,
      api_version: "2025-01"
    )
  end

  def get_locations
    session = ShopifyAPI::Auth::Session.new(
      shop: 'sabah-us.myshopify.com',
      access_token: ENV['SHOPIFY_ACCESS_TOKEN']
    )
    ShopifyAPI::Context.activate_session(session)

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    query = <<~QUERY
      query {
        locations(first: 250) {
          edges {
            node {
              id
              name
              address {
                formatted
              }
            }
          }
        }
      }
    QUERY

    response = client.query(query: query)
    locations = response.body.dig("data", "locations", "edges") || []
    locations.map do |edge|
      location = edge["node"]
      {
        id: location['id'].split('/').last,
        name: location['name'],
        address: location.dig('address', 'formatted')
      }
    end
  end

  def get_tags
    session = ShopifyAPI::Auth::Session.new(
      shop: 'sabah-us.myshopify.com',
      access_token: ENV['SHOPIFY_ACCESS_TOKEN']
    )
    ShopifyAPI::Context.activate_session(session)

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    query = <<~GRAPHQL
      query {
        productTags(first: 250) {
          edges {
            node
          }
        }
      }
    GRAPHQL
    response = client.query(query: query)
    tags = response.body.dig("data", "productTags", "edges") || []
    tags.map { |edge| edge["node"] }
  end

  def generate_report(params)
    validate_report_params(params)

    start_date = params[:start_date]
    end_date = params[:end_date]
    origin_location_id = params[:origin_location_id].to_i
    destination_location_id = params[:destination_location_id].to_i
    tag = params[:tag] # Optional

    inventory_data = if tag.present?
                      combine_locations(
                        tag: tag,
                        location1_id: origin_location_id,
                        location2_id: destination_location_id
                      )
                    else
                      combine_locations(
                        location1_id: origin_location_id,
                        location2_id: destination_location_id
                      )
                    end

    sales_data = get_sales(
      location_id: destination_location_id,
      start_date: start_date,
      end_date: end_date
    )
    sales_hash = sales_data.to_h

    combined_data = inventory_data.each_with_object({}) do |(key, value), result|
      result[key] = value.merge(sales: sales_hash[key] || 0)
    end
    generate_excel(combined_data)
  end

  private

  def validate_report_params(params)
    required_params = [:start_date, :end_date, :origin_location_id, :destination_location_id]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      raise ArgumentError, "Missing required parameters: #{missing_params.join(', ')}"
    end

    begin
      Date.parse(params[:start_date]) if params[:start_date]
      Date.parse(params[:end_date]) if params[:end_date]
    rescue ArgumentError
      raise ArgumentError, "Invalid date format. Please use YYYY-MM-DD"
    end

    if params[:start_date] && params[:end_date] && 
       Date.parse(params[:end_date]) < Date.parse(params[:start_date])
      raise ArgumentError, "End date must be after start date"
    end
  end

  def generate_excel(data)
    package = Axlsx::Package.new
    workbook = package.workbook
    
    workbook.add_worksheet(name: "Inventory Report") do |sheet|
      # Freeze the top row
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
      end

      # Define styles
      styles = workbook.styles  # Changed from 'p.workbook.styles' to 'workbook.styles'

      base_style = styles.add_style(
        sz: 10,
        alignment: {horizontal: :center, vertical: :center},
        border: { style: :medium, color: '000000' }
      )

      header_style_blue = styles.add_style(
        b: true,
        bg_color: 'A6C9EC',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      )
      
      header_style_yellow = styles.add_style(
        b: true,
        bg_color: 'FFFF00',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      )

      # Column C (Variant) style - font size 12
      column_c_style = styles.add_style(
        sz: 12,
        alignment: { horizontal: :center, vertical: :center },
        border: { style: :medium, color: '000000' }
      )

      # Column G (SEND) style - font size 14
      column_g_style = styles.add_style(
        sz: 14,
        alignment: { horizontal: :center, vertical: :center },
        border: {style: :medium, color: '000000' }
      )

      # Add headers with new SEND column
      headers = ["Product Type", "Product", "Variant", "Shopify ID", "Store", "Sales", "SEND", "WH"]
      header_row = sheet.add_row headers, style: header_style_blue
      
      # Apply special style to SEND column header
      header_row.cells[6].style = header_style_yellow

      sheet.rows.each { |row| row.height = 20 }
      
      # Set header row height
      header_row.height = 35
      
      # Add filter
      sheet.auto_filter = "A1:H1"

      # Sort and add data
      data.sort_by { |_,p| [p[:product_type], p[:product_title], p[:variant_title]] }.each do |variant_id, p|
        variant_display = if p[:variant_title] == "Default Title"
                      nil
                    elsif p[:variant_title].include?(" / ")
                      p[:variant_title].split(" / ").first
                    elsif p[:variant_title].include?(":")
                      p[:variant_title].split(":").first
                    else
                      p[:variant_title]
                    end
        row = sheet.add_row [
          p[:product_type],
          p[:product_title],
          variant_display,
          variant_id,
          p[:location2],
          p[:sales],
          nil,  # Empty SEND column
          p[:location1]
        ], style: base_style

        row.cells[2].style = column_c_style  # Column C (Variant)
        row.cells[6].style = column_g_style  # Column G (SEND)
      end

      # Set column widths (D is hidden by setting width to 0)
      sheet.column_widths 21, 32, 11, 0, 5, 5, 8, 5
      
      # Hide column D (variant_id)
      sheet.column_info[3].hidden = true
    end

    package.to_stream.read
  end
end