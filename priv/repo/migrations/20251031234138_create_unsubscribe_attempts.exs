defmodule JumpappEmailSorter.Repo.Migrations.CreateUnsubscribeAttempts do
  use Ecto.Migration

  def change do
    create table(:unsubscribe_attempts) do
      add :email_id, references(:emails, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :unsubscribe_url, :string
      add :method, :string
      add :error_message, :text
      add :attempted_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:unsubscribe_attempts, [:email_id])
    create index(:unsubscribe_attempts, [:status])
  end
end
