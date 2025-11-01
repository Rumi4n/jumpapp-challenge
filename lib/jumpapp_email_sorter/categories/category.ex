defmodule JumpappEmailSorter.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :description, :string
    field :color, :string, default: "#3B82F6"
    field :position, :integer, default: 0

    belongs_to :user, JumpappEmailSorter.Accounts.User
    has_many :emails, JumpappEmailSorter.Emails.Email

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :color, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 500)
  end
end
