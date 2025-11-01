defmodule JumpappEmailSorter.Accounts.GmailAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_accounts" do
    field :email, :string
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime
    field :watch_expiration, :utc_datetime
    field :history_id, :string

    belongs_to :user, JumpappEmailSorter.Accounts.User
    has_many :emails, JumpappEmailSorter.Emails.Email

    timestamps()
  end

  @doc false
  def changeset(gmail_account, attrs) do
    gmail_account
    |> cast(attrs, [
      :user_id,
      :email,
      :access_token,
      :refresh_token,
      :token_expires_at,
      :watch_expiration,
      :history_id
    ])
    |> validate_required([:email, :user_id])
    |> unique_constraint([:user_id, :email])
  end

  def token_changeset(gmail_account, attrs) do
    gmail_account
    |> cast(attrs, [:access_token, :refresh_token, :token_expires_at])
    |> validate_required([:access_token])
  end
end
