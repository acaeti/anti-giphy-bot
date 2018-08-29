require 'rest-client'
require 'dotenv'
require 'json'

#load .env variables
Dotenv.load

RestClient.log = STDOUT

OAUTH_TOKEN = ENV["OAUTH_TOKEN"]
WEBHOOK_TARGET = ENV["WEBHOOK_TARGET"]

AUTHORIZATION = "Bearer #{OAUTH_TOKEN}"

RESOURCE = RestClient::Resource.new 'https://api.ciscospark.com/v1'

#wildcard
new_webhook_name = "firehose"
new_webhook_target_url = WEBHOOK_TARGET
new_webhook_resource = "messages"
new_webhook_event = "created"
new_webhook_init = {"name" => new_webhook_name, "targetUrl" => new_webhook_target_url, "resource" => new_webhook_resource, "event" => new_webhook_event}
new_webhook_init_json = new_webhook_init.to_json
new_webhook = RESOURCE["webhooks"].post(new_webhook_init_json, {:content_type => :json, :authorization => AUTHORIZATION})








