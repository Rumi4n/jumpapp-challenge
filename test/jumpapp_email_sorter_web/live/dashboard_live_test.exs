defmodule JumpappEmailSorterWeb.DashboardLiveTest do
  use JumpappEmailSorterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JumpappEmailSorter.{Accounts, Categories}

  setup do
    {:ok, user} =
      Accounts.upsert_user_from_oauth(%{
        email: "test@example.com",
        google_id: "google_#{:rand.uniform(100_000)}",
        name: "Test User"
      })

    %{user: user}
  end

  describe "mount/3" do
    test "loads dashboard with categories and gmail accounts", %{conn: conn, user: user} do
      # Create some test data
      {:ok, _cat1} = Categories.create_category(user.id, %{name: "Work"})
      {:ok, _cat2} = Categories.create_category(user.id, %{name: "Personal"})

      {:ok, _gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/dashboard")

      # Check that categories are displayed
      assert html =~ "Work"
      assert html =~ "Personal"

      # Check that gmail account is displayed
      assert html =~ "test@gmail.com"

      # Check page title
      assert html =~ "Email Dashboard"
    end

    test "shows empty state when no categories exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No categories yet"
      assert html =~ "Create your first category"
    end

    test "shows empty state when no gmail accounts exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No Gmail accounts connected yet"
    end
  end

  describe "show_add_category event" do
    test "opens category modal", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Click to show modal
      html = render_click(view, "show_add_category")

      assert html =~ "Create New Category"
      assert html =~ "Category Name"
    end
  end

  describe "hide_category_modal event" do
    test "closes category modal", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open modal
      render_click(view, "show_add_category")

      # Close modal
      html = render_click(view, "hide_category_modal")

      refute html =~ "Create New Category"
    end
  end

  describe "save_category event" do
    test "creates a new category and closes modal", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open modal
      render_click(view, "show_add_category")

      # Submit form
      html =
        render_submit(view, "save_category", %{
          "category" => %{
            "name" => "Shopping",
            "description" => "Online shopping receipts"
          }
        })

      # Check that category was created
      assert html =~ "Shopping"
      assert html =~ "Online shopping receipts"
      assert html =~ "Category created successfully"

      # Modal should be closed
      refute html =~ "Create New Category"

      # Verify in database
      categories = Categories.list_categories(user.id)
      assert length(categories) == 1
      assert hd(categories).name == "Shopping"
    end

    test "shows error when category name is missing", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_click(view, "show_add_category")

      html =
        render_submit(view, "save_category", %{
          "category" => %{"name" => "", "description" => "Test"}
        })

      # Modal should still be open with error
      assert html =~ "Create New Category"
      assert html =~ "Failed to create category"

      # No category should be created
      categories = Categories.list_categories(user.id)
      assert length(categories) == 0
    end
  end

  describe "delete_category event" do
    test "deletes a category", %{conn: conn, user: user} do
      {:ok, category} =
        Categories.create_category(user.id, %{
          name: "To Delete",
          description: "Will be deleted"
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/dashboard")

      # Category should be visible
      assert html =~ "To Delete"

      # Delete category
      html = render_click(view, "delete_category", %{"id" => category.id})

      # Category should be gone
      refute html =~ "To Delete"
      assert html =~ "Category deleted successfully"

      # Verify in database
      categories = Categories.list_categories(user.id)
      assert length(categories) == 0
    end

    test "shows error when trying to delete non-existent category", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Try to delete non-existent category - should handle gracefully
      html = render_click(view, "delete_category", %{"id" => 999_999})

      # Should show error message and not crash
      assert html =~ "Category not found"
    end
  end

  describe "delete_gmail_account event" do
    test "deletes a gmail account", %{conn: conn, user: user} do
      {:ok, gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/dashboard")

      # Account should be visible
      assert html =~ "test@gmail.com"

      # Delete account
      html = render_click(view, "delete_gmail_account", %{"id" => gmail_account.id})

      # Account should be gone
      refute html =~ "test@gmail.com"
      assert html =~ "Gmail account removed successfully"

      # Verify in database
      gmail_accounts = Accounts.list_gmail_accounts(user.id)
      assert length(gmail_accounts) == 0
    end

    test "shows error when trying to delete non-existent account", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Try to delete non-existent account - should handle gracefully
      html = render_click(view, "delete_gmail_account", %{"id" => 999_999})

      # Should show error message and not crash
      assert html =~ "Account not found"
    end

    test "prevents deleting another user's gmail account", %{conn: conn, user: user} do
      # Create another user and their gmail account
      {:ok, other_user} =
        Accounts.upsert_user_from_oauth(%{
          email: "other@example.com",
          google_id: "google_#{:rand.uniform(100_000)}",
          name: "Other User"
        })

      {:ok, other_account} =
        Accounts.create_gmail_account(other_user, %{
          email: "other@gmail.com",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Try to delete other user's account
      html = render_click(view, "delete_gmail_account", %{"id" => other_account.id})

      # Should show permission error (check for HTML encoded version)
      assert html =~ "You don&#39;t have permission to delete this account" or
               html =~ "You don't have permission to delete this account"

      # Verify account still exists
      gmail_accounts = Accounts.list_gmail_accounts(other_user.id)
      assert length(gmail_accounts) == 1
    end
  end

  describe "email_imported pubsub message" do
    test "updates category counts when email is imported", %{conn: conn, user: user} do
      {:ok, category} = Categories.create_category(user.id, %{name: "Work"})

      {:ok, gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/dashboard")

      # Initially should show 0 emails
      assert html =~ "0 emails"

      # Create an email
      {:ok, email} =
        JumpappEmailSorter.Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: "msg_#{:rand.uniform(100_000)}",
          thread_id: "thread_123",
          subject: "Test Email",
          from_email: "sender@example.com",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body"
        })

      # Simulate the pubsub broadcast that the worker would send
      send(view.pid, {:email_imported, email})

      # Wait for the view to update
      html = render(view)

      # Should now show 1 email
      assert html =~ "1 email"
    end
  end

  describe "main account and logout" do
    test "displays Sign Out button for main account and Main Account badge", %{
      conn: conn,
      user: user
    } do
      # Create the main account (matching user's email)
      {:ok, _main_account} =
        Accounts.create_gmail_account(user, %{
          email: user.email,
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Check that main account has Sign Out button and badge
      assert html =~ "Sign Out"
      assert html =~ "Main Account"
      assert html =~ "/auth/logout"
    end

    test "displays Remove button for additional accounts only", %{conn: conn, user: user} do
      # Create main account
      {:ok, _main_account} =
        Accounts.create_gmail_account(user, %{
          email: user.email,
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Create additional account
      {:ok, _additional_account} =
        Accounts.create_gmail_account(user, %{
          email: "additional@gmail.com",
          access_token: "token2",
          refresh_token: "refresh2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Main account should have Sign Out
      assert html =~ "Sign Out"
      # Additional account should have Remove
      assert html =~ "Remove"
      # Should show both accounts
      assert html =~ user.email
      assert html =~ "additional@gmail.com"
    end

    test "prevents deletion of main account", %{conn: conn, user: user} do
      {:ok, main_account} =
        Accounts.create_gmail_account(user, %{
          email: user.email,
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Try to delete main account
      html = render_click(view, "delete_gmail_account", %{"id" => main_account.id})

      # Should show error message
      assert html =~ "Cannot remove main account" or html =~ "Use Sign Out instead"

      # Verify account still exists
      gmail_accounts = Accounts.list_gmail_accounts(user.id)
      assert length(gmail_accounts) == 1
    end

    test "main account is always displayed first in the list", %{conn: conn, user: user} do
      # Create additional account first (to test sorting, not insertion order)
      {:ok, _additional1} =
        Accounts.create_gmail_account(user, %{
          email: "additional1@gmail.com",
          access_token: "token1",
          refresh_token: "refresh1",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Create main account second
      {:ok, _main_account} =
        Accounts.create_gmail_account(user, %{
          email: user.email,
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Create another additional account last
      {:ok, _additional2} =
        Accounts.create_gmail_account(user, %{
          email: "additional2@gmail.com",
          access_token: "token2",
          refresh_token: "refresh2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Extract the order of emails in the HTML
      # Main account should appear before additional accounts
      main_pos = :binary.match(html, user.email) |> elem(0)
      additional1_pos = :binary.match(html, "additional1@gmail.com") |> elem(0)
      additional2_pos = :binary.match(html, "additional2@gmail.com") |> elem(0)

      # Main account should be first
      assert main_pos < additional1_pos
      assert main_pos < additional2_pos
    end
  end

  # Helper function

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{})
    |> put_session(:user_id, user.id)
    |> assign(:current_user, user)
  end
end

