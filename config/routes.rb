# frozen_string_literal: true

VzekcMap::Engine.routes.draw do
  get "/locations" => "map#locations"
end

Discourse::Application.routes.draw do
  mount ::VzekcMap::Engine, at: "vzekc-map"
end
