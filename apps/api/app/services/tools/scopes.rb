# frozen_string_literal: true

module Tools
  # What a token is allowed to do, in the vocabulary of tool domains.
  #
  # Connecting Claude Code or Claude Desktop today means handing it a
  # token with everything your account can do — including, for an admin,
  # the taxonomy and the moderation queue. That is a lot of authority to
  # grant something whose job is usually "read menus for me", and there
  # has been no way to grant less.
  #
  # Scopes are derived from `Registry::DOMAINS` rather than listed here,
  # so a new domain cannot be added without a scope existing for it — the
  # same reason `Topology` derives its map from the registry instead of
  # restating it.
  #
  # `read` and `write` split on the tool's own `read_only_hint`, so the
  # split follows the annotation a tool already carries rather than a
  # second list that would drift.
  module Scopes
    # Granted when a token says nothing about scopes. Existing tokens —
    # every one issued before this shipped — keep working exactly as they
    # did, and a scope check on them is a no-op rather than a lockout.
    ALL = "*"

    # What each domain is, in words someone deciding whether to grant it
    # can act on. "taxonomy:write" tells a person nothing; "Change the
    # shared ingredient and tag catalogue" tells them enough to refuse.
    # A spec asserts every registered domain appears here — an OAuth
    # consent screen that shrugs at a scope is not consent.
    SUBJECTS = {
      meta:        "what this server can do",
      discovery:   "restaurants, menus, and why a dish is or is not safe for you",
      profile:     "your avoid lists, strictness, and saved places",
      ingestion:   "menu photos you scan and the items they produce",
      reviews:     "your reviews",
      suggestions: "corrections you suggest to menu data",
      claims:      "restaurant ownership claims",
      history:     "your visit and save history",
      restaurants: "restaurant records",
      structure:   "menu structure — sections, places, and ordering",
      items:       "individual dishes",
      taxonomy:    "the shared ingredient and tag catalogue",
      moderation:  "the moderation queue",
      users:       "user accounts and their roles"
    }.freeze

    class << self
      # Every scope a caller could be granted, as strings.
      def available
        @available ||= Registry::DOMAINS.keys.flat_map { |domain| ["#{domain}:read", "#{domain}:write"] }.freeze
      end

      # The scope a given tool call requires, or nil for a class the
      # registry does not know — an anonymous subclass in a spec, say.
      # Returning nil there means "no scope gates this", which is the only
      # safe answer: a tool nobody can reach through the registry is not
      # something a scope can meaningfully protect.
      def for_tool(tool)
        return nil if tool.nil? || tool.name.blank?

        domain = Registry.domain_of(tool)
        return nil if domain.nil?

        "#{domain}:#{tool.annotations_value&.read_only_hint ? 'read' : 'write'}"
      end

      # A grant covers a required scope when it matches exactly, when it
      # is the wildcard, or when a write grant implies the read on the
      # same domain — asking for permission to edit a menu and then being
      # refused permission to look at one would be nonsense.
      def satisfied?(granted, required)
        return true if required.nil?

        list = Array(granted)
        return true if list.empty? || list.include?(ALL)
        return true if list.include?(required)

        domain, action = required.split(":")
        action == "read" && list.include?("#{domain}:write")
      end

      def valid?(scope)
        scope == ALL || available.include?(scope)
      end

      # A sentence for a consent screen. Falls back to the raw scope
      # rather than raising — a person mid-authorization should not hit a
      # 500 because a domain was added without a description.
      def describe(scope)
        return "Everything this account can do" if scope == ALL

        domain, action = scope.to_s.split(":")
        subject = SUBJECTS[domain&.to_sym]
        return scope.to_s if subject.blank?

        action == "read" ? "Read #{subject}" : "Read and change #{subject}"
      end
    end
  end
end
