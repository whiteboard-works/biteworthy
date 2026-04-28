# See Pagy::Backend API documentation: https://ddnexus.github.io/pagy/api/backend
# encoding: utf-8
# frozen_string_literal: true

class Pagy
  module Backend ; private         # the whole module is private so no problem with including it in a controller

    def pagy_to_a(collection, vars={})
      pagy = Pagy.new(pagy_get_vars(collection, vars))
      return pagy, pagy_get_items(collection, pagy).to_a
    end

  end
end
