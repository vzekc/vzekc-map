# frozen_string_literal: true

VzekcMap::Engine.routes.draw do
  get "/locations" => "map#locations"
  post "/locations" => "map#add_location"
  delete "/locations/:index" => "map#delete_location"
  get "/pois" => "map#pois"
end

Discourse::Application.routes.draw do
  mount ::VzekcMap::Engine, at: "vzekc-map"
end
