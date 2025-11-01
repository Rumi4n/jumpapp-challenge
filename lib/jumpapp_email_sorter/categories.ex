defmodule JumpappEmailSorter.Categories do
  @moduledoc """
  The Categories context.
  """

  import Ecto.Query, warn: false
  alias JumpappEmailSorter.Repo

  alias JumpappEmailSorter.Categories.Category

  @doc """
  Returns the list of categories for a user.
  """
  def list_categories(user_id) do
    Category
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.position, asc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of categories with email counts.
  """
  def list_categories_with_counts(user_id) do
    from(c in Category,
      left_join: e in assoc(c, :emails),
      where: c.user_id == ^user_id,
      group_by: c.id,
      select: %{category: c, email_count: count(e.id)},
      order_by: [asc: c.position, asc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single category.
  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Gets a category by user_id and category_id.
  """
  def get_user_category(user_id, category_id) do
    Category
    |> where([c], c.user_id == ^user_id and c.id == ^category_id)
    |> Repo.one()
  end

  @doc """
  Creates a category.
  """
  def create_category(user_id, attrs \\ %{}) do
    # Get the next position
    max_position =
      Category
      |> where([c], c.user_id == ^user_id)
      |> select([c], max(c.position))
      |> Repo.one()

    position = (max_position || 0) + 1

    # Ensure attrs is a map with string keys for proper casting
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("position", position)

    %Category{user_id: user_id}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end
end
