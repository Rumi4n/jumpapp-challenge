defmodule JumpappEmailSorter.CategoriesTest do
  use JumpappEmailSorter.DataCase, async: true

  alias JumpappEmailSorter.{Categories, Accounts}
  alias JumpappEmailSorter.Categories.Category

  setup do
    {:ok, user} =
      Accounts.upsert_user_from_oauth(%{
        email: "test@example.com",
        google_id: "google_#{:rand.uniform(100_000)}",
        name: "Test User"
      })

    %{user: user}
  end

  describe "list_categories/1" do
    test "returns all categories for a user ordered by position", %{user: user} do
      {:ok, cat1} = Categories.create_category(user.id, %{name: "First", description: "Desc 1"})
      {:ok, cat2} = Categories.create_category(user.id, %{name: "Second", description: "Desc 2"})
      {:ok, cat3} = Categories.create_category(user.id, %{name: "Third", description: "Desc 3"})

      categories = Categories.list_categories(user.id)

      assert length(categories) == 3
      assert Enum.at(categories, 0).id == cat1.id
      assert Enum.at(categories, 1).id == cat2.id
      assert Enum.at(categories, 2).id == cat3.id
    end

    test "returns empty list when user has no categories", %{user: user} do
      assert Categories.list_categories(user.id) == []
    end

    test "does not return categories from other users", %{user: user} do
      {:ok, other_user} =
        Accounts.upsert_user_from_oauth(%{
          email: "other@example.com",
          google_id: "other_google_id",
          name: "Other User"
        })

      {:ok, _cat1} = Categories.create_category(user.id, %{name: "User 1 Category"})
      {:ok, _cat2} = Categories.create_category(other_user.id, %{name: "User 2 Category"})

      categories = Categories.list_categories(user.id)
      assert length(categories) == 1
      assert hd(categories).name == "User 1 Category"
    end
  end

  describe "list_categories_with_counts/1" do
    test "returns categories with email counts", %{user: user} do
      {:ok, cat1} = Categories.create_category(user.id, %{name: "Category 1"})
      {:ok, cat2} = Categories.create_category(user.id, %{name: "Category 2"})

      # Create gmail account and emails
      {:ok, gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Create emails for cat1
      create_email(gmail_account.id, cat1.id)
      create_email(gmail_account.id, cat1.id)

      # Create one email for cat2
      create_email(gmail_account.id, cat2.id)

      results = Categories.list_categories_with_counts(user.id)

      assert length(results) == 2
      cat1_result = Enum.find(results, fn r -> r.category.id == cat1.id end)
      cat2_result = Enum.find(results, fn r -> r.category.id == cat2.id end)

      assert cat1_result.email_count == 2
      assert cat2_result.email_count == 1
    end

    test "returns zero count for categories with no emails", %{user: user} do
      {:ok, cat} = Categories.create_category(user.id, %{name: "Empty Category"})

      results = Categories.list_categories_with_counts(user.id)

      assert length(results) == 1
      assert hd(results).email_count == 0
      assert hd(results).category.id == cat.id
    end
  end

  describe "get_category!/1" do
    test "returns the category with given id", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Test Category"})
      found_category = Categories.get_category!(category.id)
      assert found_category.id == category.id
      assert found_category.name == "Test Category"
    end

    test "raises when category does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Categories.get_category!(999_999)
      end
    end
  end

  describe "get_user_category/2" do
    test "returns category when user_id and category_id match", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Test"})
      found_category = Categories.get_user_category(user.id, category.id)
      assert found_category.id == category.id
    end

    test "returns nil when category does not belong to user", %{user: user} do
      {:ok, other_user} =
        Accounts.upsert_user_from_oauth(%{
          email: "other@example.com",
          google_id: "other_google",
          name: "Other"
        })

      {:ok, category} = Categories.create_category(other_user.id, %{name: "Other's Category"})

      assert Categories.get_user_category(user.id, category.id) == nil
    end

    test "returns nil when category does not exist", %{user: user} do
      assert Categories.get_user_category(user.id, 999_999) == nil
    end
  end

  describe "create_category/2" do
    test "creates a category with valid attributes", %{user: user} do
      attrs = %{name: "Work", description: "Work-related emails"}

      assert {:ok, category} = Categories.create_category(user.id, attrs)
      assert category.name == "Work"
      assert category.description == "Work-related emails"
      assert category.user_id == user.id
      assert category.position == 1
    end

    test "assigns sequential positions to categories", %{user: user} do
      {:ok, cat1} = Categories.create_category(user.id, %{name: "First"})
      {:ok, cat2} = Categories.create_category(user.id, %{name: "Second"})
      {:ok, cat3} = Categories.create_category(user.id, %{name: "Third"})

      assert cat1.position == 1
      assert cat2.position == 2
      assert cat3.position == 3
    end

    test "returns error when name is missing", %{user: user} do
      assert {:error, changeset} = Categories.create_category(user.id, %{})
      assert changeset.errors[:name] != nil
    end

    test "accepts atom keys in attributes", %{user: user} do
      attrs = %{name: "Shopping", description: "Shopping emails"}
      assert {:ok, category} = Categories.create_category(user.id, attrs)
      assert category.name == "Shopping"
    end

    test "accepts string keys in attributes", %{user: user} do
      attrs = %{"name" => "Shopping", "description" => "Shopping emails"}
      assert {:ok, category} = Categories.create_category(user.id, attrs)
      assert category.name == "Shopping"
    end
  end

  describe "update_category/2" do
    test "updates category with valid attributes", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Old Name"})

      assert {:ok, updated_category} =
               Categories.update_category(category, %{name: "New Name", description: "New Desc"})

      assert updated_category.name == "New Name"
      assert updated_category.description == "New Desc"
    end

    test "returns error when name is invalid", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Valid"})

      assert {:error, changeset} = Categories.update_category(category, %{name: ""})
      assert changeset.errors[:name] != nil
    end
  end

  describe "delete_category/1" do
    test "deletes the category", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "To Delete"})

      assert {:ok, _deleted_category} = Categories.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> Categories.get_category!(category.id) end
    end
  end

  describe "change_category/2" do
    test "returns a changeset for a new category" do
      changeset = Categories.change_category(%Category{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns a changeset with changes", %{user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Test"})
      changeset = Categories.change_category(category, %{name: "Updated"})

      assert changeset.changes.name == "Updated"
    end
  end

  # Helper functions

  defp create_email(gmail_account_id, category_id) do
    alias JumpappEmailSorter.Emails

    Emails.create_email(%{
      gmail_account_id: gmail_account_id,
      category_id: category_id,
      gmail_message_id: "msg_#{:rand.uniform(100_000)}",
      thread_id: "thread_#{:rand.uniform(100_000)}",
      subject: "Test Email",
      from_email: "sender@example.com",
      from_name: "Sender",
      received_at: DateTime.utc_now(),
      summary: "Test summary",
      body_preview: "Preview",
      body_text: "Body"
    })
  end
end

