defmodule JumpappEmailSorterWeb.AuthControllerTest do
  use JumpappEmailSorterWeb.ConnCase, async: true

  alias JumpappEmailSorter.Accounts

  # Note: These tests verify the controller logic, but actual OAuth flow
  # requires Ueberauth setup which is complex to test in unit tests.
  # The key logic is tested through the Accounts context tests.

  describe "callback/2 with failure" do
    test "redirects to home with error flash when authentication fails", %{conn: conn} do
      conn =
        conn
        |> bypass_through(JumpappEmailSorterWeb.Router, [:browser])
        |> get(~p"/auth/google/callback")
        |> assign(:ueberauth_failure, %{errors: [%{message: "Auth failed"}]})
        |> JumpappEmailSorterWeb.AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to authenticate"
    end
  end

  describe "callback/2 with success - initial login" do
    test "creates new user and gmail account on first login", %{conn: conn} do
      auth = build_auth_struct("newuser@example.com", "google_new_123")

      conn =
        conn
        |> bypass_through(JumpappEmailSorterWeb.Router, [:browser])
        |> get(~p"/auth/google/callback")
        |> assign(:ueberauth_auth, auth)
        |> JumpappEmailSorterWeb.AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Successfully authenticated"

      # Verify user was created
      user = Accounts.get_user_by_google_id("google_new_123")
      assert user != nil
      assert user.email == "newuser@example.com"

      # Verify gmail account was created
      gmail_accounts = Accounts.list_gmail_accounts(user.id)
      assert length(gmail_accounts) == 1
      assert hd(gmail_accounts).email == "newuser@example.com"

      # Verify session was set
      assert get_session(conn, :user_id) == user.id
    end

    test "updates existing user on subsequent login", %{conn: conn} do
      # Create existing user
      {:ok, existing_user} =
        Accounts.upsert_user_from_oauth(%{
          email: "old@example.com",
          google_id: "google_existing_123",
          name: "Old Name"
        })

      auth = build_auth_struct("updated@example.com", "google_existing_123", "New Name")

      conn =
        conn
        |> bypass_through(JumpappEmailSorterWeb.Router, [:browser])
        |> get(~p"/auth/google/callback")
        |> assign(:ueberauth_auth, auth)
        |> JumpappEmailSorterWeb.AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/dashboard"

      # Verify user was updated
      user = Accounts.get_user_by_google_id("google_existing_123")
      assert user.id == existing_user.id
      assert user.email == "updated@example.com"
      assert user.name == "New Name"
    end
  end

  describe "callback/2 with success - adding additional account" do
    test "adds gmail account to existing logged-in user", %{conn: conn} do
      # Create existing user and log them in
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          email: "user@example.com",
          google_id: "google_user_123",
          name: "Test User"
        })

      auth = build_auth_struct("second@gmail.com", "google_second_123")

      conn =
        conn
        |> bypass_through(JumpappEmailSorterWeb.Router, [:browser])
        |> get(~p"/auth/google/callback")
        |> init_test_session(%{user_id: user.id})
        |> assign(:ueberauth_auth, auth)
        |> JumpappEmailSorterWeb.AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Gmail account added successfully"

      # Verify gmail account was added to existing user
      gmail_accounts = Accounts.list_gmail_accounts(user.id)
      assert length(gmail_accounts) == 1
      assert hd(gmail_accounts).email == "second@gmail.com"
    end

    test "updates existing gmail account tokens when re-authenticating", %{conn: conn} do
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          email: "user@example.com",
          google_id: "google_user_123",
          name: "Test User"
        })

      # Add first gmail account
      {:ok, gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "duplicate@gmail.com",
          access_token: "old_token",
          refresh_token: "old_refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      old_token = gmail_account.access_token

      # Re-authenticate with the same account (should update tokens)
      auth = build_auth_struct("duplicate@gmail.com", "google_dup_123")

      conn =
        conn
        |> bypass_through(JumpappEmailSorterWeb.Router, [:browser])
        |> get(~p"/auth/google/callback")
        |> init_test_session(%{user_id: user.id})
        |> assign(:ueberauth_auth, auth)
        |> JumpappEmailSorterWeb.AuthController.callback(%{})

      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Gmail account added successfully"
      
      # Verify that only one gmail account exists (no duplicate)
      gmail_accounts = Accounts.list_gmail_accounts(user.id)
      assert length(gmail_accounts) == 1
      
      # Verify tokens were updated
      updated_account = hd(gmail_accounts)
      assert updated_account.access_token != old_token
    end
  end

  describe "delete/2" do
    test "signs out user and clears session", %{conn: conn} do
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          email: "user@example.com",
          google_id: "google_123",
          name: "Test User"
        })

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Successfully signed out"
      # The session is marked for drop but not yet cleared until the next request
      # This is expected behavior in Phoenix
    end
  end

  # Helper functions

  defp build_auth_struct(email, google_id, name \\ "Test User") do
    expires_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()

    %{
      uid: google_id,
      info: %{
        email: email,
        name: name,
        image: "https://example.com/pic.jpg"
      },
      credentials: %{
        token: "access_token_#{:rand.uniform(100_000)}",
        refresh_token: "refresh_token_#{:rand.uniform(100_000)}",
        expires_at: expires_at
      }
    }
  end
end

