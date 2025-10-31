defmodule JumpappEmailSorter.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :gmail_account_id, references(:gmail_accounts, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :gmail_message_id, :string, null: false
      add :thread_id, :string
      add :subject, :string
      add :from_email, :string
      add :from_name, :string
      add :received_at, :utc_datetime
      add :summary, :text
      add :body_preview, :text
      add :body_html, :text
      add :body_text, :text
      add :archived_at, :utc_datetime
      add :list_unsubscribe_header, :text
      add :unsubscribe_link, :string

      timestamps()
    end

    create index(:emails, [:gmail_account_id])
    create index(:emails, [:category_id])
    create unique_index(:emails, [:gmail_account_id, :gmail_message_id])
    create index(:emails, [:received_at])
  end
end
