defmodule JumpappEmailSorter.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :color, :string, default: "#3B82F6"
      add :position, :integer, default: 0

      timestamps()
    end

    create index(:categories, [:user_id])
    create index(:categories, [:user_id, :position])
  end
end
