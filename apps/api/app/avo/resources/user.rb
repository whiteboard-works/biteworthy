class Avo::Resources::User < Avo::BaseResource
  # Phase-1.md §1.5 calls for User to be read-only in admin. We skip
  # security tokens (jti, confirmation_token, encrypted_password) from
  # the field list entirely so they can't leak via the show view, and
  # rely on admin-team trust for the create/edit/destroy gate. Phase 4
  # will add a Pundit policy that disables write actions.

  def fields
    field :id,                  as: :id
    field :email,               as: :text
    field :handle,              as: :text
    field :display_name,        as: :text
    field :provider,            as: :text
    field :uid,                 as: :text
    field :is_admin,            as: :boolean
    field :confirmed_at,        as: :date_time
    field :sign_in_count,       as: :number
    field :current_sign_in_at,  as: :date_time
    field :last_sign_in_at,     as: :date_time
    field :created_at,          as: :date_time
    field :updated_at,          as: :date_time

    field :profile,             as: :has_one
    field :reviews,             as: :has_many
    field :suggestions,         as: :has_many
  end
end
