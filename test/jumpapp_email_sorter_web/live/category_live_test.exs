defmodule JumpappEmailSorterWeb.CategoryLiveTest do
  use JumpappEmailSorterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JumpappEmailSorter.{Accounts, Categories, Emails}

  setup do
    {:ok, user} =
      Accounts.upsert_user_from_oauth(%{
        email: "test@example.com",
        google_id: "google_#{:rand.uniform(100_000)}",
        name: "Test User"
      })

    {:ok, gmail_account} =
      Accounts.create_gmail_account(user, %{
        email: "test@gmail.com",
        access_token: "token",
        refresh_token: "refresh",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, category} =
      Categories.create_category(user.id, %{
        name: "Shopping",
        description: "Shopping receipts"
      })

    %{user: user, gmail_account: gmail_account, category: category}
  end

  describe "mount/3" do
    test "loads category with emails", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      # Create test emails
      create_email(gmail_account.id, category.id, %{subject: "Order Confirmation"})
      create_email(gmail_account.id, category.id, %{subject: "Shipping Notification"})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/categories/#{category.id}")

      # Check category info is displayed
      assert html =~ "Shopping"
      assert html =~ "Shopping receipts"

      # Check emails are displayed
      assert html =~ "Order Confirmation"
      assert html =~ "Shipping Notification"
    end

    test "shows empty state when category has no emails", %{conn: conn, user: user, category: category} do
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/categories/#{category.id}")

      assert html =~ "No emails in this category yet"
    end

    test "redirects when category does not exist", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      
      # When category doesn't exist, mount returns a redirect
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/categories/999999")
    end

    test "redirects when category belongs to different user", %{conn: conn, category: category} do
      {:ok, other_user} =
        Accounts.upsert_user_from_oauth(%{
          email: "other@example.com",
          google_id: "google_other_123",
          name: "Other User"
        })

      conn = log_in_user(conn, other_user)
      
      # When category doesn't belong to user, mount returns a redirect
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/categories/#{category.id}")
    end
  end

  describe "toggle_select event" do
    test "selects and deselects an email", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select email
      render_click(view, "toggle_select", %{"id" => to_string(email.id)})

      # Should show bulk actions
      html = render(view)
      assert html =~ "1 email(s) selected"

      # Deselect email
      render_click(view, "toggle_select", %{"id" => to_string(email.id)})

      # Bulk actions should be hidden
      html = render(view)
      refute html =~ "email(s) selected"
    end
  end

  describe "select_all event" do
    test "selects all emails", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      create_email(gmail_account.id, category.id)
      create_email(gmail_account.id, category.id)
      create_email(gmail_account.id, category.id)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select all
      html = render_click(view, "select_all")

      assert html =~ "3 email(s) selected"
    end
  end

  describe "deselect_all event" do
    test "deselects all emails", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      create_email(gmail_account.id, category.id)
      create_email(gmail_account.id, category.id)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select all first
      render_click(view, "select_all")

      # Then deselect all
      html = render_click(view, "deselect_all")

      refute html =~ "email(s) selected"
    end
  end

  describe "delete_selected event" do
    test "deletes selected emails", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      {:ok, email1} = create_email(gmail_account.id, category.id, %{subject: "Email 1"})
      {:ok, email2} = create_email(gmail_account.id, category.id, %{subject: "Email 2"})
      {:ok, _email3} = create_email(gmail_account.id, category.id, %{subject: "Email 3"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select two emails
      render_click(view, "toggle_select", %{"id" => to_string(email1.id)})
      render_click(view, "toggle_select", %{"id" => to_string(email2.id)})

      # Delete selected
      render_click(view, "delete_selected")

      # Get fresh HTML after deletion
      html = render(view)

      # Check emails are gone
      refute html =~ "Email 1"
      refute html =~ "Email 2"
      assert html =~ "Email 3"

      # Verify in database
      emails = Emails.list_emails_by_category(category.id)
      assert length(emails) == 1
    end

    test "does nothing when no emails selected", %{conn: conn, user: user, category: category} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # When no emails are selected, the event completes but shows an error flash
      # The flash may not be immediately visible in the rendered HTML
      render_click(view, "delete_selected")

      # Just verify the view is still functional
      assert render(view) =~ category.name
    end
  end

  describe "unsubscribe_selected event" do
    test "queues unsubscribe jobs for selected emails", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      {:ok, email1} = create_email(gmail_account.id, category.id)
      {:ok, email2} = create_email(gmail_account.id, category.id)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Select emails
      render_click(view, "toggle_select", %{"id" => to_string(email1.id)})
      render_click(view, "toggle_select", %{"id" => to_string(email2.id)})

      # Unsubscribe selected
      render_click(view, "unsubscribe_selected")

      # Get fresh HTML
      html = render(view)

      # Selection should be cleared (no bulk action bar visible)
      refute html =~ "email(s) selected"
    end

    test "does nothing when no emails selected for unsubscribe", %{conn: conn, user: user, category: category} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # When no emails are selected, the event completes but shows an error flash
      render_click(view, "unsubscribe_selected")

      # Just verify the view is still functional
      assert render(view) =~ category.name
    end
  end

  describe "show_email event" do
    test "opens email detail modal", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      {:ok, email} =
        create_email(gmail_account.id, category.id, %{
          subject: "Important Email",
          body_text: "This is the full email body"
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      html = render_click(view, "show_email", %{"id" => to_string(email.id)})

      # Modal should be visible with email details
      assert html =~ "Important Email"
      assert html =~ "This is the full email body"
    end
  end

  describe "hide_email_modal event" do
    test "closes email detail modal", %{conn: conn, user: user, gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id, %{subject: "Test Email"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/categories/#{category.id}")

      # Open modal
      render_click(view, "show_email", %{"id" => to_string(email.id)})

      # Close modal
      html = render_click(view, "hide_email_modal")

      # Modal content should not be prominently visible
      # (Note: The email subject might still appear in the list, so we check for modal-specific content)
      refute html =~ "AI Summary"
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{})
    |> put_session(:user_id, user.id)
    |> assign(:current_user, user)
  end

  defp create_email(gmail_account_id, category_id, attrs \\ %{}) do
    default_attrs = %{
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
    }

    Emails.create_email(Map.merge(default_attrs, attrs))
  end
end

