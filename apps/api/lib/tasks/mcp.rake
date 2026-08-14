# frozen_string_literal: true

# Least-privilege credentials for MCP clients.
#
# The alternative — and what a connected Claude Code uses without one — is
# the same JWT the web app holds, which carries everything the account can
# do. A token here names what it may touch and can be revoked on its own.
#
# The secret prints once. There is nothing stored that could print it
# again, which is the point.
#
# Usage:
#   bin/rails "mcp:issue[you@example.com,Claude Code,discovery:read profile:read]"
#   bin/rails "mcp:issue[you@example.com,ops,*]"        # full access, said out loud
#   bin/rails "mcp:list[you@example.com]"
#   bin/rails "mcp:revoke[<token id>]"
#   bin/rails mcp:scopes
namespace :mcp do
  desc "Issue a scoped MCP token. Scopes are space-separated; '*' grants full access."
  task :issue, [:email, :name, :scopes] => :environment do |_t, args|
    abort("usage: mcp:issue[email,name,scopes]") if args[:email].blank? || args[:name].blank?

    user = User.find_by(email: args[:email].to_s.downcase)
    abort("no user with email #{args[:email]}") if user.nil?

    scopes = args[:scopes].to_s.split.map(&:strip).compact_blank
    # Omission used to mean "everything", which made the shortest command
    # the most powerful one. Ask for `*` instead — the box's own shell is
    # not a reason for a credential to be vague about its authority.
    abort("no scopes given; pass '*' for full access or run mcp:scopes to see the list") if scopes.empty?

    active = McpToken.active.where(user: user).count
    abort("that account already has #{McpToken::MAX_ACTIVE} active tokens; revoke one first") if
      active >= McpToken::MAX_ACTIVE

    token, secret = McpToken.issue!(user: user, name: args[:name], scopes: scopes)

    puts "id:     #{token.id}"
    puts "scopes: #{describe_grant(scopes)}"
    puts
    puts "  #{secret}"
    puts
    puts "That is the only time it will be shown — nothing stored can print it again."
  end

  desc "List a user's active MCP tokens"
  task :list, [:email] => :environment do |_t, args|
    user = User.find_by(email: args[:email].to_s.downcase)
    abort("no user with email #{args[:email]}") if user.nil?

    tokens = McpToken.active.where(user: user).order(:created_at)
    puts "no active tokens" if tokens.empty?
    tokens.each do |t|
      used = t.last_used_at ? "last used #{t.last_used_at.to_fs(:short)}" : "never used"
      puts format("%s  %-24s %-40s %s", t.id, t.name, describe_grant(t.scopes), used)
    end
  end

  desc "Revoke one MCP token by id"
  task :revoke, [:id] => :environment do |_t, args|
    token = McpToken.find_by(id: args[:id])
    abort("no token #{args[:id]}") if token.nil?

    token.revoke!
    puts "revoked #{token.name}"
  end

  desc "List every scope a token can be granted"
  task scopes: :environment do
    Tools::Scopes.available.each_slice(2) { |read, write| puts "#{read}\t#{write}" }
    puts "#{Tools::Scopes::ALL}\t\t(#{Tools::Scopes.describe(Tools::Scopes::ALL).downcase})"
  end

  # A wildcard grant reads as a scope list of one otherwise, which is the
  # least informative way to print the most powerful token on the page.
  def describe_grant(scopes)
    scopes.include?(Tools::Scopes::ALL) ? "full access (#{Tools::Scopes::ALL})" : scopes.join(", ")
  end
end
