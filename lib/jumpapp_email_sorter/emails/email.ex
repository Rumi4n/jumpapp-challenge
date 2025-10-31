defmodule JumpappEmailSorter.Emails.Email do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emails" do
    field :gmail_message_id, :string
    field :thread_id, :string
    field :subject, :string
    field :from_email, :string
    field :from_name, :string
    field :received_at, :utc_datetime
    field :summary, :string
    field :body_preview, :string
    field :body_html, :string
    field :body_text, :string
    field :archived_at, :utc_datetime
    field :list_unsubscribe_header, :string
    field :unsubscribe_link, :string

    belongs_to :gmail_account, JumpappEmailSorter.Accounts.GmailAccount
    belongs_to :category, JumpappEmailSorter.Categories.Category
    has_many :unsubscribe_attempts, JumpappEmailSorter.Emails.UnsubscribeAttempt

    timestamps()
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_message_id,
      :thread_id,
      :subject,
      :from_email,
      :from_name,
      :received_at,
      :summary,
      :body_preview,
      :body_html,
      :body_text,
      :archived_at,
      :list_unsubscribe_header,
      :unsubscribe_link,
      :category_id
    ])
    |> validate_required([:gmail_message_id, :gmail_account_id])
    |> unique_constraint([:gmail_account_id, :gmail_message_id])
  end
end

