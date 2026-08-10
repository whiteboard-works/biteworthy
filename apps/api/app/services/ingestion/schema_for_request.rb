# frozen_string_literal: true

module Ingestion
  # Turns one of our JSON Schemas into the subset Anthropic's structured
  # outputs accept, so the model is *constrained* to emit the shape rather
  # than asked nicely and checked afterwards.
  #
  # Why derive instead of hand-writing a second schema: the two would
  # drift, and the direction of the drift is silent — a wire schema that
  # forgot a field still produces valid-looking output, just without the
  # field. One source of truth (`MenuExtractionSchema`), one mechanical
  # transformation.
  #
  # The transformation exists because the two schemas answer different
  # questions. The wire schema constrains **shape** while the model
  # generates; the full schema still validates **values** after. So the
  # keywords stripped here are not lost — `minLength`, `minimum`,
  # `maximum` and `exclusiveMinimum` are all still enforced by
  # `JSON::Validator` on the way in. Sending them is simply a 400:
  # structured outputs support types, `enum`, `const`, `anyOf`, `allOf`
  # and `$ref`, and reject numeric and length constraints.
  #
  # Verified against the live API rather than inferred: posting
  # `MenuExtractionSchema` unmodified returns
  # `Invalid JSON Schema in output format`; posting the derived form
  # returns 200 with parseable JSON.
  class SchemaForRequest
    # Keywords structured outputs reject. Enforced post-hoc instead.
    UNSUPPORTED = %i[minLength maxLength minimum maximum exclusiveMinimum
                     exclusiveMaximum multipleOf minItems maxItems pattern format].freeze

    # Keys whose *values* are maps of property names, not more schema
    # keywords. One level below these, `format` or `minimum` is the name
    # of a field the model must emit — dropping it would leave `required`
    # naming a property the wire schema no longer defines (a 400), or a
    # field the model is grammatically unable to produce and the post-hoc
    # validator then demands.
    NAME_MAPS = %i[properties patternProperties definitions $defs].freeze

    def self.derive(schema)
      case schema
      when Hash  then derive_hash(schema)
      when Array then schema.map { |item| derive(item) }
      else schema
      end
    end

    # Named `derive_hash`, not `hash`. A `self.hash` taking one argument
    # shadows `Object#hash` on the class object, and Ruby calls that with
    # zero arguments from its own internals — so `[SchemaForRequest,
    # …].uniq` raises `ArgumentError`. Private visibility does not help;
    # the interpreter does not care.
    def self.derive_hash(schema)
      schema.each_with_object({}) do |(key, value), out|
        name = key.to_sym
        next if UNSUPPORTED.include?(name)

        out[name == :oneOf ? :anyOf : name] =
          # `oneOf` is not in the supported set; `anyOf` is, and for these
          # schemas they mean the same thing — the branches are disjoint
          # (a null or a fully-specified object), so "exactly one" and "at
          # least one" cannot disagree.
          NAME_MAPS.include?(name) ? derive_properties(value) : derive(value)
      end
    end
    private_class_method :derive_hash

    # Every key here is a property name, so recurse into the values
    # without ever testing a key against `UNSUPPORTED`.
    def self.derive_properties(properties)
      return derive(properties) unless properties.is_a?(Hash)

      properties.transform_values { |sub| derive(sub) }
    end
    private_class_method :derive_properties
  end
end
