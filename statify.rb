#!/usr/bin/env ruby
#
# Cabify Statify
#

require 'sinatra'
require 'haml'
require 'sinatra/sequel'
require 'active_support/core_ext'
require 'yajl/json_gem'

require './model/query'

configure do 
  set :server, :puma

  #set :database, 'sqlite://database.db'
  set :database, ENV['STATIFY_DATABASE']
end

use Rack::Auth::Basic, "Protected Area" do |username, password|
  username == 'cabify' && password == 'statify'
end

get '/' do
  "Nothing to see here."
end

get '/pivot' do
  haml :pivot
end

post '/pivot' do
  query = params[:query]
  @data = database.fetch(query)
  haml :pivot
end

get "/pivot.js" do
  content_type "text/javascript"
  coffee :pivot
end

post "/query" do
  content_type "application/json"
  query = Query.new(database, params)
  JSON.dump(query.fetch_all_as_json)
end

