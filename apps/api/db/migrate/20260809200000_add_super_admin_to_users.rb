class AddSuperAdminToUsers < ActiveRecord::Migration[8.1]
  # A second tier above `is_admin`, for the operator whose spend the
  # ceilings exist to protect *from other people*.
  #
  # Why a second bit rather than making `is_admin` unlimited: any admin
  # can promote any user (`set_user_role`, PATCH /admin/users/:id), so
  # "admin means no spend ceiling" turns one promotion into an uncapped
  # Anthropic bill. This bit is granted only from the env roster and the
  # rake task — never from a tool, never over HTTP — so the set of people
  # who can spend without a ceiling is the set of people with shell
  # access, which is the property the ceilings were protecting.
  #
  # `skip_confirmations` is separate on purpose. It turns off the gate
  # that parks a destructive tool call for a human answer — including an
  # avoid-list removal, which un-hides dishes (see docs/plans/chat-engine.md
  # Safety Property 5). Being a super admin should not silently imply
  # wanting that, and keeping it its own column means it can be turned
  # back on for one account without a deploy.
  def change
    add_column :users, :is_super_admin,     :boolean, null: false, default: false
    add_column :users, :skip_confirmations, :boolean, null: false, default: false
    add_index  :users, :is_super_admin, where: "is_super_admin = true"

    # A super admin is always an admin, enforced in the database rather
    # than by a Ruby predicate that overrides the reader.
    #
    # The alternative — `def is_admin? = super || is_super_admin` — makes
    # Ruby and SQL disagree, and this codebase reads `is_admin` both ways:
    # `Api::V1::Admin::DashboardsController` filters community traffic
    # with `.where(users: { is_admin: false })`, which would silently
    # count a super admin's scans as community spend. One constraint keeps
    # every existing `is_admin?` call site and every SQL scope correct
    # without touching either.
    add_check_constraint :users,
                         "NOT (is_super_admin AND NOT is_admin)",
                         name: "super_admin_implies_admin"
  end
end
