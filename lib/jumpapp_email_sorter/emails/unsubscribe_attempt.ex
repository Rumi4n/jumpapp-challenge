defmodule JumpappEmailSorter.Emails.UnsubscribeAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "unsubscribe_attempts" do
    field :status, :string, default: "pending"
    field :unsubscribe_url, :string
    field :method, :string
    field :error_message, :string
    field :attempted_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :email, JumpappEmailSorter.Emails.Email

    timestamps()
  end

  @doc false
  def changeset(unsubscribe_attempt, attrs) do
    unsubscribe_attempt
    |> cast(attrs, [
      :status,
      :unsubscribe_url,
      :method,
      :error_message,
      :attempted_at,
      :completed_at
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["pending", "processing", "success", "failed"])
  end
end
