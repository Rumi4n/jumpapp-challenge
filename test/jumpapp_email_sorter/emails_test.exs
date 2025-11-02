defmodule JumpappEmailSorter.EmailsTest do
  use JumpappEmailSorter.DataCase, async: true

  alias JumpappEmailSorter.{Emails, Accounts, Categories}

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

    {:ok, category} = Categories.create_category(user.id, %{name: "Test Category"})

    %{user: user, gmail_account: gmail_account, category: category}
  end

  describe "list_emails_by_category/1" do
    test "returns all emails for a category ordered by received_at desc", %{
      gmail_account: gmail_account,
      category: category
    } do
      now = DateTime.utc_now()
      {:ok, email1} = create_email(gmail_account.id, category.id, received_at: now)

      {:ok, email2} =
        create_email(gmail_account.id, category.id,
          received_at: DateTime.add(now, -3600, :second)
        )

      {:ok, email3} =
        create_email(gmail_account.id, category.id,
          received_at: DateTime.add(now, 3600, :second)
        )

      emails = Emails.list_emails_by_category(category.id)

      assert length(emails) == 3
      # Most recent first
      assert Enum.at(emails, 0).id == email3.id
      assert Enum.at(emails, 1).id == email1.id
      assert Enum.at(emails, 2).id == email2.id
    end

    test "returns empty list when category has no emails", %{category: category} do
      assert Emails.list_emails_by_category(category.id) == []
    end

    test "does not return emails from other categories", %{
      user: user,
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, other_category} = Categories.create_category(user.id, %{name: "Other"})

      {:ok, _email1} = create_email(gmail_account.id, category.id)
      {:ok, _email2} = create_email(gmail_account.id, other_category.id)

      emails = Emails.list_emails_by_category(category.id)
      assert length(emails) == 1
    end
  end

  describe "list_emails_by_account/1" do
    test "returns all emails for a gmail account", %{
      user: user,
      gmail_account: gmail_account
    } do
      {:ok, cat1} = Categories.create_category(user.id, %{name: "Cat1"})
      {:ok, cat2} = Categories.create_category(user.id, %{name: "Cat2"})

      {:ok, _email1} = create_email(gmail_account.id, cat1.id)
      {:ok, _email2} = create_email(gmail_account.id, cat2.id)
      {:ok, _email3} = create_email(gmail_account.id, cat1.id)

      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 3
    end

    test "returns empty list when account has no emails", %{gmail_account: gmail_account} do
      assert Emails.list_emails_by_account(gmail_account.id) == []
    end

    test "does not return emails from other accounts", %{
      user: user,
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, other_account} =
        Accounts.create_gmail_account(user, %{
          email: "other@gmail.com",
          access_token: "token2",
          refresh_token: "refresh2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, _email1} = create_email(gmail_account.id, category.id)
      {:ok, _email2} = create_email(other_account.id, category.id)

      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1
    end
  end

  describe "get_email!/1" do
    test "returns the email with given id", %{gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id)
      found_email = Emails.get_email!(email.id)
      assert found_email.id == email.id
    end

    test "raises when email does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Emails.get_email!(999_999)
      end
    end
  end

  describe "get_email_by_gmail_id/2" do
    test "returns email when gmail_account_id and gmail_message_id match", %{
      gmail_account: gmail_account,
      category: category
    } do
      gmail_message_id = "unique_msg_#{:rand.uniform(100_000)}"
      {:ok, email} = create_email(gmail_account.id, category.id, gmail_message_id: gmail_message_id)

      found_email = Emails.get_email_by_gmail_id(gmail_account.id, gmail_message_id)
      assert found_email.id == email.id
    end

    test "returns nil when email does not exist", %{gmail_account: gmail_account} do
      assert Emails.get_email_by_gmail_id(gmail_account.id, "nonexistent") == nil
    end

    test "returns nil when gmail_message_id exists but for different account", %{
      user: user,
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, other_account} =
        Accounts.create_gmail_account(user, %{
          email: "other@gmail.com",
          access_token: "token2",
          refresh_token: "refresh2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      gmail_message_id = "unique_msg_#{:rand.uniform(100_000)}"
      {:ok, _email} = create_email(gmail_account.id, category.id, gmail_message_id: gmail_message_id)

      assert Emails.get_email_by_gmail_id(other_account.id, gmail_message_id) == nil
    end
  end

  describe "create_email/1" do
    test "creates an email with valid attributes", %{
      gmail_account: gmail_account,
      category: category
    } do
      attrs = %{
        gmail_account_id: gmail_account.id,
        category_id: category.id,
        gmail_message_id: "msg_123",
        thread_id: "thread_123",
        subject: "Test Subject",
        from_email: "sender@example.com",
        from_name: "Sender Name",
        received_at: DateTime.utc_now(),
        summary: "Test summary",
        body_preview: "Preview text",
        body_text: "Full body text"
      }

      assert {:ok, email} = Emails.create_email(attrs)
      assert email.subject == "Test Subject"
      assert email.from_email == "sender@example.com"
      assert email.gmail_account_id == gmail_account.id
    end

    test "creates email with optional unsubscribe fields", %{
      gmail_account: gmail_account,
      category: category
    } do
      attrs = %{
        gmail_account_id: gmail_account.id,
        category_id: category.id,
        gmail_message_id: "msg_124",
        thread_id: "thread_124",
        subject: "Newsletter",
        from_email: "news@example.com",
        received_at: DateTime.utc_now(),
        summary: "Summary",
        body_preview: "Preview",
        body_text: "Body",
        unsubscribe_link: "https://example.com/unsubscribe",
        list_unsubscribe_header: "<https://example.com/unsubscribe>"
      }

      assert {:ok, email} = Emails.create_email(attrs)
      assert email.unsubscribe_link == "https://example.com/unsubscribe"
      assert email.list_unsubscribe_header == "<https://example.com/unsubscribe>"
    end

    test "returns error when required fields are missing" do
      assert {:error, changeset} = Emails.create_email(%{})
      assert changeset.errors[:gmail_account_id] != nil
      assert changeset.errors[:gmail_message_id] != nil
    end

    test "enforces unique constraint on gmail_message_id per account", %{
      gmail_account: gmail_account,
      category: category
    } do
      gmail_message_id = "duplicate_msg_#{:rand.uniform(100_000)}"

      attrs = %{
        gmail_account_id: gmail_account.id,
        category_id: category.id,
        gmail_message_id: gmail_message_id,
        thread_id: "thread",
        subject: "First",
        from_email: "sender@example.com",
        received_at: DateTime.utc_now(),
        summary: "Summary",
        body_preview: "Preview",
        body_text: "Body"
      }

      assert {:ok, _email1} = Emails.create_email(attrs)

      # Try to create duplicate
      attrs2 = Map.put(attrs, :subject, "Duplicate")
      assert {:error, changeset} = Emails.create_email(attrs2)
      # The unique constraint is on [:gmail_account_id, :gmail_message_id]
      assert changeset.errors[:gmail_message_id] != nil or changeset.errors[:gmail_account_id] != nil
    end
  end

  describe "update_email/2" do
    test "updates email with valid attributes", %{
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, email} = create_email(gmail_account.id, category.id)

      assert {:ok, updated_email} =
               Emails.update_email(email, %{subject: "Updated Subject", summary: "New summary"})

      assert updated_email.subject == "Updated Subject"
      assert updated_email.summary == "New summary"
    end
  end

  describe "delete_email/1" do
    test "deletes the email", %{gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id)

      assert {:ok, _deleted_email} = Emails.delete_email(email)
      assert_raise Ecto.NoResultsError, fn -> Emails.get_email!(email.id) end
    end
  end

  describe "create_unsubscribe_attempt/2" do
    test "creates an unsubscribe attempt for an email", %{
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, email} = create_email(gmail_account.id, category.id)

      attrs = %{
        unsubscribe_url: "https://example.com/unsubscribe",
        status: "processing",
        attempted_at: DateTime.utc_now()
      }

      assert {:ok, attempt} = Emails.create_unsubscribe_attempt(email.id, attrs)
      assert attempt.email_id == email.id
      assert attempt.unsubscribe_url == "https://example.com/unsubscribe"
      assert attempt.status == "processing"
    end
  end

  describe "update_unsubscribe_attempt/2" do
    test "updates an unsubscribe attempt", %{gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id)

      {:ok, attempt} =
        Emails.create_unsubscribe_attempt(email.id, %{
          unsubscribe_url: "https://example.com/unsubscribe",
          status: "processing"
        })

      assert {:ok, updated_attempt} =
               Emails.update_unsubscribe_attempt(attempt, %{
                 status: "success",
                 method: "one_click",
                 completed_at: DateTime.utc_now()
               })

      assert updated_attempt.status == "success"
      assert updated_attempt.method == "one_click"
      assert updated_attempt.completed_at != nil
    end
  end

  describe "get_latest_unsubscribe_attempt/1" do
    test "returns the most recent unsubscribe attempt for an email", %{
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, email} = create_email(gmail_account.id, category.id)

      # Create multiple attempts
      {:ok, _attempt1} =
        Emails.create_unsubscribe_attempt(email.id, %{
          unsubscribe_url: "https://example.com/unsubscribe",
          status: "failed"
        })

      # Sleep to ensure different timestamps (need enough time for microsecond precision)
      Process.sleep(1000)

      {:ok, attempt2} =
        Emails.create_unsubscribe_attempt(email.id, %{
          unsubscribe_url: "https://example.com/unsubscribe",
          status: "success"
        })

      latest = Emails.get_latest_unsubscribe_attempt(email.id)
      assert latest.id == attempt2.id
      assert latest.status == "success"
    end

    test "returns nil when no attempts exist", %{gmail_account: gmail_account, category: category} do
      {:ok, email} = create_email(gmail_account.id, category.id)
      assert Emails.get_latest_unsubscribe_attempt(email.id) == nil
    end
  end

  # Helper functions

  defp create_email(gmail_account_id, category_id, opts \\ []) do
    default_attrs = %{
      gmail_account_id: gmail_account_id,
      category_id: category_id,
      gmail_message_id: Keyword.get(opts, :gmail_message_id, "msg_#{:rand.uniform(100_000)}"),
      thread_id: "thread_#{:rand.uniform(100_000)}",
      subject: "Test Email",
      from_email: "sender@example.com",
      from_name: "Sender",
      received_at: Keyword.get(opts, :received_at, DateTime.utc_now()),
      summary: "Test summary",
      body_preview: "Preview",
      body_text: "Body"
    }

    Emails.create_email(default_attrs)
  end
end

