require 'dotenv'
require 'shopify_api'
require 'date'

Dotenv.load(File.expand_path("../../.env", __dir__))

ShopifyAPI::Context.setup(
	api_key: ENV['SHOPIFY_API_KEY'],
	api_secret_key: ENV['SHOPIFY_API_SECRET'],
	host_name: "https://225c-98-113-19-129.ngrok-free.app",
	scope: "read_inventory, read_orders, read_products, read_locations, read_assigned_fulfillment_orders",
	is_embedded: true,
	is_private: true,
	api_version: "2025-01"
)

def get_inventory_of_location(location_id:, tag: nil)
  session = ShopifyAPI::Auth::Session.new(
    shop: 'sabah-us.myshopify.com',
    access_token: ENV['SHOPIFY_ACCESS_TOKEN']
  )
  ShopifyAPI::Context.activate_session(session)

  client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

  inventory_data = []
  cursor = nil
  has_next_page = true

  while has_next_page
    tag_query_part = tag ? "tag:#{tag}" : ""
    query = <<~QUERY
      query {
        products(first: 250#{tag_query_part.empty? ? "" : ", query: \"#{tag_query_part}\""}#{cursor ? ", after: \"#{cursor}\"" : ""}) {
          edges {
            node {
              title
              productType
              variants(first: 100) {
                edges {
                  node {
                    id
                    title
                    inventoryItem {
                      id
                      inventoryLevel(locationId: "gid://shopify/Location/#{location_id}") {
                        quantities(names: ["available"]) {
                          quantity
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    QUERY

    response = client.query(query: query)
    parsed_response = response.body

    parsed_response.dig("data", "products", "edges")&.each do |edge|
      product = edge.dig("node")
      product_title = product["title"]
      product_type = product["productType"]

      product.dig("variants", "edges")&.each do |variant_edge|
        variant = variant_edge.dig("node")
        inventory_level = variant.dig("inventoryItem", "inventoryLevel")
        available = inventory_level&.dig("quantities", 0, "quantity") || 0

        inventory_data << {
          product_type: product_type,
          product_title: product_title,
          variant_title: variant["title"],
          variant_id: variant["id"],
          sku: variant["sku"],
          available_quantity: available
        }
      end
    end

    page_info = parsed_response.dig("data", "products", "pageInfo") || {}
    has_next_page = page_info["hasNextPage"] || false
    cursor = page_info["endCursor"] if has_next_page
  end
  inventory_data
end

def combine_locations(location1_id:, location2_id:, tag: nil)
  # Get inventory for both locations
  location1_data = get_inventory_of_location(tag: tag, location_id: location1_id)
  location2_data = get_inventory_of_location(tag: tag, location_id: location2_id)

  # Combine data by variant ID
  combined_data = {}
  
  # Process location 1 data
  location1_data.each do |item|
    variant_id = item[:variant_id].split('/').last # Extract numeric ID
    combined_data[variant_id] = {
      product_type: item[:product_type],
      product_title: item[:product_title],
      variant_title: item[:variant_title],
      sku: item[:sku],
      location1: item[:available_quantity],
      location2: 0 # Initialize location 2 quantity
    }
  end

  # Process location 2 data
  location2_data.each do |item|
    variant_id = item[:variant_id].split('/').last # Extract numeric ID
    if combined_data[variant_id]
      combined_data[variant_id][:location2] = item[:available_quantity]
    else
      combined_data[variant_id] = {
      	product_type: item[:product_type],
        product_title: item[:product_title],
        variant_title: item[:variant_title],
        sku: item[:sku],
        location1: 0,
        location2: item[:available_quantity]
      }
    end
end
	combined_data
end