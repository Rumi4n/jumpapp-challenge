defmodule JumpappEmailSorter.AccountsTest do
  use JumpappEmailSorter.DataCase, async: true

  alias JumpappEmailSorter.Accounts
  alias JumpappEmailSorter.Accounts.{User, GmailAccount}

  describe "get_user!/1" do
    test "returns the user with given id" do
      {:ok, user} = create_user()
      assert Accounts.get_user!(user.id).id == user.id
    end

    test "raises when user does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(999_999)
      end
    end
  end

  describe "get_user_by_email/1" do
    test "returns user when email exists" do
      {:ok, user} = create_user(%{email: "test@example.com"})
      found_user = Accounts.get_user_by_email("test@example.com")
      assert found_user.id == user.id
    end

    test "returns nil when email does not exist" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end
  end

  describe "get_user_by_google_id/1" do
    test "returns user when google_id exists" do
      {:ok, user} = create_user(%{google_id: "google123"})
      found_user = Accounts.get_user_by_google_id("google123")
      assert found_user.id == user.id
    end

    test "returns nil when google_id does not exist" do
      assert Accounts.get_user_by_google_id("nonexistent") == nil
    end
  end

  describe "upsert_user_from_oauth/1" do
    test "creates a new user when google_id does not exist" do
      oauth_data = %{
        email: "new@example.com",
        google_id: "new_google_id",
        name: "New User",
        picture: "https://example.com/pic.jpg"
      }

      assert {:ok, user} = Accounts.upsert_user_from_oauth(oauth_data)
      assert user.email == "new@example.com"
      assert user.google_id == "new_google_id"
      assert user.name == "New User"
    end

    test "updates existing user when google_id exists" do
      {:ok, existing_user} =
        create_user(%{
          email: "old@example.com",
          google_id: "existing_google_id",
          name: "Old Name"
        })

      oauth_data = %{
        email: "updated@example.com",
        google_id: "existing_google_id",
        name: "Updated Name",
        picture: "https://example.com/new.jpg"
      }

      assert {:ok, updated_user} = Accounts.upsert_user_from_oauth(oauth_data)
      assert updated_user.id == existing_user.id
      assert updated_user.email == "updated@example.com"
      assert updated_user.name == "Updated Name"
    end
  end

  describe "update_user_tokens/2" do
    test "updates user tokens successfully" do
      {:ok, user} = create_user()

      token_attrs = %{
        access_token: "new_access_token",
        refresh_token: "new_refresh_token",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, updated_user} = Accounts.update_user_tokens(user, token_attrs)
      assert updated_user.access_token == "new_access_token"
      assert updated_user.refresh_token == "new_refresh_token"
    end
  end

  describe "list_gmail_accounts/1" do
    test "returns all gmail accounts for a user" do
      {:ok, user} = create_user()
      {:ok, account1} = create_gmail_account(user, %{email: "account1@gmail.com"})
      {:ok, account2} = create_gmail_account(user, %{email: "account2@gmail.com"})

      accounts = Accounts.list_gmail_accounts(user.id)
      assert length(accounts) == 2
      assert Enum.any?(accounts, fn a -> a.id == account1.id end)
      assert Enum.any?(accounts, fn a -> a.id == account2.id end)
    end

    test "returns empty list when user has no gmail accounts" do
      {:ok, user} = create_user()
      assert Accounts.list_gmail_accounts(user.id) == []
    end

    test "does not return accounts from other users" do
      {:ok, user1} = create_user(%{email: "user1@example.com", google_id: "google1"})
      {:ok, user2} = create_user(%{email: "user2@example.com", google_id: "google2"})

      {:ok, _account1} = create_gmail_account(user1, %{email: "account1@gmail.com"})
      {:ok, _account2} = create_gmail_account(user2, %{email: "account2@gmail.com"})

      accounts = Accounts.list_gmail_accounts(user1.id)
      assert length(accounts) == 1
      assert hd(accounts).email == "account1@gmail.com"
    end
  end

  describe "get_gmail_account!/1" do
    test "returns the gmail account with given id" do
      {:ok, user} = create_user()
      {:ok, account} = create_gmail_account(user)
      assert Accounts.get_gmail_account!(account.id).id == account.id
    end

    test "raises when gmail account does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_gmail_account!(999_999)
      end
    end
  end

  describe "get_gmail_account_by_email/2" do
    test "returns gmail account when user_id and email match" do
      {:ok, user} = create_user()
      {:ok, account} = create_gmail_account(user, %{email: "test@gmail.com"})

      found_account = Accounts.get_gmail_account_by_email(user.id, "test@gmail.com")
      assert found_account.id == account.id
    end

    test "returns nil when email does not exist for user" do
      {:ok, user} = create_user()
      assert Accounts.get_gmail_account_by_email(user.id, "nonexistent@gmail.com") == nil
    end

    test "returns nil when email exists but for different user" do
      {:ok, user1} = create_user(%{email: "user1@example.com", google_id: "google1"})
      {:ok, user2} = create_user(%{email: "user2@example.com", google_id: "google2"})

      {:ok, _account} = create_gmail_account(user1, %{email: "test@gmail.com"})

      assert Accounts.get_gmail_account_by_email(user2.id, "test@gmail.com") == nil
    end
  end

  describe "create_gmail_account/2" do
    test "creates a gmail account successfully" do
      {:ok, user} = create_user()

      attrs = %{
        email: "new@gmail.com",
        access_token: "token123",
        refresh_token: "refresh123",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, account} = Accounts.create_gmail_account(user, attrs)
      assert account.email == "new@gmail.com"
      assert account.user_id == user.id
    end

    test "returns error when required fields are missing" do
      {:ok, user} = create_user()
      assert {:error, changeset} = Accounts.create_gmail_account(user, %{})
      assert changeset.errors[:email] != nil
    end
  end

  describe "upsert_gmail_account_from_oauth/2" do
    test "creates new gmail account when it does not exist" do
      {:ok, user} = create_user()

      oauth_data = %{
        email: "new@gmail.com",
        access_token: "token123",
        refresh_token: "refresh123",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, account} = Accounts.upsert_gmail_account_from_oauth(user, oauth_data)
      assert account.email == "new@gmail.com"
      assert account.user_id == user.id
    end

    test "updates existing gmail account when it exists" do
      {:ok, user} = create_user()
      {:ok, existing_account} = create_gmail_account(user, %{email: "existing@gmail.com"})

      oauth_data = %{
        email: "existing@gmail.com",
        access_token: "new_token",
        refresh_token: "new_refresh",
        token_expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
      }

      assert {:ok, updated_account} =
               Accounts.upsert_gmail_account_from_oauth(user, oauth_data)

      assert updated_account.id == existing_account.id
      assert updated_account.access_token == "new_token"
    end
  end

  describe "update_gmail_account/2" do
    test "updates gmail account successfully" do
      {:ok, user} = create_user()
      {:ok, account} = create_gmail_account(user)

      assert {:ok, updated_account} =
               Accounts.update_gmail_account(account, %{email: "updated@gmail.com"})

      assert updated_account.email == "updated@gmail.com"
    end
  end

  describe "update_gmail_account_tokens/2" do
    test "updates gmail account tokens successfully" do
      {:ok, user} = create_user()
      {:ok, account} = create_gmail_account(user)

      token_attrs = %{
        access_token: "new_token",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      assert {:ok, updated_account} =
               Accounts.update_gmail_account_tokens(account, token_attrs)

      assert updated_account.access_token == "new_token"
    end
  end

  describe "delete_gmail_account/1" do
    test "deletes gmail account successfully" do
      {:ok, user} = create_user()
      {:ok, account} = create_gmail_account(user)

      assert {:ok, _deleted_account} = Accounts.delete_gmail_account(account)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_gmail_account!(account.id) end
    end
  end

  describe "token_expired?/1" do
    test "returns true when token is nil" do
      assert Accounts.token_expired?(nil) == true
    end

    test "returns true when token is expired" do
      expired_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert Accounts.token_expired?(expired_time) == true
    end

    test "returns true when token expires within 5 minutes" do
      soon_to_expire = DateTime.add(DateTime.utc_now(), 200, :second)
      assert Accounts.token_expired?(soon_to_expire) == true
    end

    test "returns false when token is valid and not expiring soon" do
      valid_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      assert Accounts.token_expired?(valid_time) == false
    end
  end

  # Helper functions

  defp create_user(attrs \\ %{}) do
    default_attrs = %{
      email: "test_#{:rand.uniform(100_000)}@example.com",
      google_id: "google_#{:rand.uniform(100_000)}",
      name: "Test User",
      picture: "https://example.com/pic.jpg"
    }

    Accounts.upsert_user_from_oauth(Map.merge(default_attrs, attrs))
  end

  defp create_gmail_account(user, attrs \\ %{}) do
    default_attrs = %{
      email: "gmail_#{:rand.uniform(100_000)}@gmail.com",
      access_token: "access_token_#{:rand.uniform(100_000)}",
      refresh_token: "refresh_token_#{:rand.uniform(100_000)}",
      token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    }

    Accounts.create_gmail_account(user, Map.merge(default_attrs, attrs))
  end
end

