require 'dotenv'
require 'logger'
require 'shopify_api'
require 'date'

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

def get_sales(location_id:, start_date:, end_date:)
	session = ShopifyAPI::Auth::Session.new(
		shop: 'sabah-us.myshopify.com',
		access_token: ENV['SHOPIFY_ACCESS_TOKEN']
	)
	ShopifyAPI::Context.activate_session(session)

	client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)


# Set start and end dates (adjust as needed)

	order_data = []
  	has_next_page = true
  	cursor = nil

# GraphQL query to fetch fulfillment orders with location information
	while has_next_page
	query = <<~QUERY
	  	query($cursor: String) {
	    	orders(
	    		first: 250,
	    		after: $cursor,
	    		query: "created_at:>=#{start_date} AND created_at:<=#{end_date} AND fulfillment_location_id:#{location_id}"
	     	) {
	     		pageInfo {
	     			hasNextPage
	     			endCursor
	     		}
	      		edges {
	      			node {
	      				lineItems(first: 20) {
	      					edges {
	      						node {
	      							name
	      							quantity
	      							variant {
	      								id
	      								title
	      							}
	      						}
	      					}
	      				}
	      			}
			    }
	    	}
	  	}
	QUERY

	response = client.query(query: query)

	parsed_response = response.body

	parsed_response.dig("data", "orders", "edges")&.each do |edge|
		order = edge.dig("node")
		order.dig("lineItems", "edges")&.each do |variant_edge|
			item = variant_edge.dig("node")
			quantity = item["quantity"]
			product_title = item["name"]
			variant = item.dig("variant")

			next unless variant

	      	order_data << {
	        	product_title: product_title,
	        	variant: variant["title"] || "Default Variant",
	        	variant_id: variant["id"],
	        	quantity: quantity
	      }
	    end
	  end

	page_info = parsed_response.dig("data", "orders", "pageInfo") || {}
	has_next_page = page_info["hasNextPage"] || false
	cursor = page_info["endCursor"] if has_next_page
  end

  sales_data = {}
  order_data.each do |item|
  	numeric_id = item[:variant_id].split('/').last
  	sales_data[numeric_id] ||= 0
  	sales_data[numeric_id] += item[:quantity]
  end
  sales_data
end