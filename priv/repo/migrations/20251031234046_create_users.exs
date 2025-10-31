defmodule JumpappEmailSorter.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :google_id, :string, null: false
      add :name, :string
      add :picture, :string
      add :access_token, :text
      add :refresh_token, :text
      add :token_expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_id])
  end
end
