# frozen_string_literal: true

module Tools
  # `completion/complete` — what a client offers as a dropdown while
  # somebody fills in a prompt argument.
  #
  # This matters more here than it would elsewhere. Every write path in
  # this system takes a **slug**, and slugs are the one thing nobody can
  # guess: `search_taxonomy` exists because a model cannot turn "garbanzo"
  # into `chickpea` on its own. A person picking "Scan a menu into the
  # database" out of a prompt list is in exactly the same position, and
  # until now the argument box was a blank one.
  #
  # **Every source here is public data**, and deliberately so: completions
  # arrive before a tool call, carry no scope of their own, and a
  # suggestion list is a read even when it looks like a hint. Restaurants
  # are filtered to `published` for the same reason the discovery tools
  # are. A source that could ever return something non-public belongs
  # behind a tool, not here — `completions_spec` asserts an unpublished
  # restaurant never appears.
  module Completions
    LIMIT = 25

    # Argument name → how to resolve it. Declared on the workflow in
    # `Topology::WORKFLOWS`, so a prompt and its completions come from one
    # place; adding an argument nothing here knows about is a spec failure
    # rather than a silently empty dropdown.
    ARGUMENTS = {
      restaurant: {
        description: "Restaurant slug. Start typing the name.",
        resolve: ->(prefix) { Restaurant.published.then { |scope| Completions.by_prefix(scope, prefix) } }
      },
      city: {
        description: "City slug, e.g. \"durango\".",
        resolve: ->(prefix) { Completions.by_prefix(City.all, prefix) }
      },
      avoid: {
        description: "Ingredient or tag slug — what to avoid, or what to look up.",
        resolve: lambda { |prefix|
          (Completions.by_prefix(Ingredient.all, prefix) + Completions.by_prefix(Tag.all, prefix))
            .sort.first(LIMIT)
        }
      }
    }.freeze

    class << self
      # The MCP shape. `hasMore` is honest rather than always false: a
      # client that shows "25 of many" prompts someone to type another
      # letter, which is the only thing that will actually help them.
      def call(argument_name:, value: nil)
        spec = ARGUMENTS[argument_name.to_s.to_sym]
        return empty if spec.nil?

        values = spec[:resolve].call(value.to_s)
        { completion: { values: values.first(LIMIT), hasMore: values.size > LIMIT } }
      end

      def describe(argument_name) = ARGUMENTS.dig(argument_name.to_s.to_sym, :description)

      def known?(argument_name) = ARGUMENTS.key?(argument_name.to_s.to_sym)

      # Prefix, not substring: a slug is a name someone is part-way
      # through typing, and matching the middle of one turns "cheese" into
      # a list of every dish that mentions it. LIMIT + 1 so `hasMore` can
      # be answered without a second count query.
      def by_prefix(scope, prefix)
        scope = scope.where("slug LIKE ?", "#{sanitize_prefix(prefix)}%") if prefix.present?
        scope.order(:slug).limit(LIMIT + 1).pluck(:slug)
      end

      private

      # LIKE metacharacters in a prefix someone typed are literal
      # characters, not a pattern they meant.
      def sanitize_prefix(prefix)
        ActiveRecord::Base.sanitize_sql_like(prefix.to_s)
      end

      def empty = { completion: { values: [], hasMore: false } }
    end
  end
end
