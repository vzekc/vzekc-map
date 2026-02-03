# frozen_string_literal: true

module ::VzekcMap
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace VzekcMap
  end
end
