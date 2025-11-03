defmodule JumpappEmailSorter.Workers.EmailImportWorkerMockedTest do
  use JumpappEmailSorter.DataCase, async: false

  import Mox

  alias JumpappEmailSorter.Workers.EmailImportWorker
  alias JumpappEmailSorter.{Accounts, Categories, Emails}
  alias JumpappEmailSorter.{GmailClientMock, AIServiceMock}

  # Set up Mox to verify mocks
  setup :verify_on_exit!
  setup :set_mox_global

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
        access_token: "valid_token",
        refresh_token: "refresh_token",
        token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    {:ok, category1} =
      Categories.create_category(user.id, %{
        name: "Shopping",
        description: "Shopping receipts and orders"
      })

    {:ok, category2} =
      Categories.create_category(user.id, %{
        name: "Work",
        description: "Work-related emails"
      })

    %{
      user: user,
      gmail_account: gmail_account,
      categories: [category1, category2],
      category1: category1,
      category2: category2
    }
  end

  describe "perform/1 - with mocked Gmail API" do
    test "successfully imports a single unread email", %{
      gmail_account: gmail_account,
      categories: categories,
      category1: category1
    } do
      # Mock Gmail API to return one unread message
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_123"}]}}
      end)

      # Mock getting the message details
      expect(GmailClientMock, :get_message, fn _token, "msg_123" ->
        {:ok,
         %{
           id: "msg_123",
           thread_id: "thread_456",
           subject: "Your Amazon Order Has Shipped",
           from: %{name: "Amazon", email: "ship-confirm@amazon.com"},
           body: "Your order #123-456 has been shipped and will arrive on Friday.",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: "<https://amazon.com/unsubscribe>"
         }}
      end)

      # Mock AI categorization
      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:ok, category1.id}
      end)

      # Mock AI summarization
      expect(AIServiceMock, :summarize_email, fn _content ->
        {:ok, "Amazon order shipped, arriving Friday"}
      end)

      # Mock Gmail archive
      expect(GmailClientMock, :archive_message, fn _token, "msg_123" ->
        :ok
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Verify email was saved to database
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1

      email = hd(emails)
      assert email.gmail_message_id == "msg_123"
      assert email.subject == "Your Amazon Order Has Shipped"
      assert email.category_id == category1.id
      assert email.summary == "Amazon order shipped, arriving Friday"
    end

    test "imports multiple unread emails", %{
      gmail_account: gmail_account,
      categories: _categories,
      category1: category1,
      category2: category2
    } do
      # Mock Gmail API to return multiple messages
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_1"}, %{"id" => "msg_2"}]}}
      end)

      # Mock getting first message
      expect(GmailClientMock, :get_message, fn _token, "msg_1" ->
        {:ok,
         %{
           id: "msg_1",
           thread_id: "thread_1",
           subject: "Shopping Receipt",
           from: %{name: "Store", email: "store@example.com"},
           body: "Thank you for your purchase",
           date: "2024-01-15T10:00:00Z",
           list_unsubscribe: nil
         }}
      end)

      # Mock getting second message
      expect(GmailClientMock, :get_message, fn _token, "msg_2" ->
        {:ok,
         %{
           id: "msg_2",
           thread_id: "thread_2",
           subject: "Team Meeting",
           from: %{name: "Boss", email: "boss@company.com"},
           body: "Meeting tomorrow at 10 AM",
           date: "2024-01-15T11:00:00Z",
           list_unsubscribe: nil
         }}
      end)

      # Mock AI categorization for both emails
      expect(AIServiceMock, :categorize_email, 2, fn content, _categories ->
        cond do
          String.contains?(content, "Shopping") -> {:ok, category1.id}
          String.contains?(content, "Meeting") -> {:ok, category2.id}
          true -> {:ok, nil}
        end
      end)

      # Mock AI summarization for both emails
      expect(AIServiceMock, :summarize_email, 2, fn content ->
        {:ok, String.slice(content, 0, 50)}
      end)

      # Mock Gmail archive for both emails
      expect(GmailClientMock, :archive_message, 2, fn _token, _msg_id ->
        :ok
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Verify both emails were saved
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 2
    end

    test "handles no unread messages", %{gmail_account: gmail_account} do
      # Mock Gmail API to return empty list
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{}}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Verify no emails were saved
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 0
    end

    test "handles Gmail API unauthorized error", %{gmail_account: gmail_account} do
      # Mock Gmail API to return unauthorized error
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:error, :unauthorized}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == {:error, :unauthorized}
    end

    test "handles Gmail API general error", %{gmail_account: gmail_account} do
      # Mock Gmail API to return error
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:error, :timeout}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == {:error, :timeout}
    end

    test "skips already imported emails", %{
      gmail_account: gmail_account,
      categories: _categories,
      category1: category1
    } do
      # Create an existing email
      {:ok, _existing_email} =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category1.id,
          gmail_message_id: "msg_existing",
          thread_id: "thread_1",
          subject: "Existing Email",
          from_email: "sender@example.com",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body"
        })

      # Mock Gmail API to return the existing message
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_existing"}]}}
      end)

      # Should NOT call get_message since email already exists
      # No expect() call for get_message

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Verify only one email exists (the original)
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1
    end

    test "does not archive uncategorized emails", %{
      gmail_account: gmail_account,
      categories: _categories
    } do
      # Mock Gmail API
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_123"}]}}
      end)

      expect(GmailClientMock, :get_message, fn _token, "msg_123" ->
        {:ok,
         %{
           id: "msg_123",
           thread_id: "thread_456",
           subject: "Uncategorized Email",
           from: %{name: "Sender", email: "sender@example.com"},
           body: "This email doesn't match any category",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: nil
         }}
      end)

      # Mock AI to return nil category (no match)
      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:ok, nil}
      end)

      expect(AIServiceMock, :summarize_email, fn _content ->
        {:ok, "Summary"}
      end)

      # Should NOT archive since category_id is nil
      # No expect() call for archive_message

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Verify email was saved but not categorized
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1
      assert hd(emails).category_id == nil
    end

    test "continues importing even if archive fails", %{
      gmail_account: gmail_account,
      categories: _categories,
      category1: category1
    } do
      # Mock Gmail API
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_123"}]}}
      end)

      expect(GmailClientMock, :get_message, fn _token, "msg_123" ->
        {:ok,
         %{
           id: "msg_123",
           thread_id: "thread_456",
           subject: "Test Email",
           from: %{name: "Sender", email: "sender@example.com"},
           body: "Test body",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: nil
         }}
      end)

      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:ok, category1.id}
      end)

      expect(AIServiceMock, :summarize_email, fn _content ->
        {:ok, "Summary"}
      end)

      # Mock archive to fail
      expect(GmailClientMock, :archive_message, fn _token, "msg_123" ->
        {:error, :unauthorized}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      # Should still return :ok even though archive failed
      assert result == :ok

      # Verify email was still saved
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1
    end

    test "handles error getting individual message", %{
      gmail_account: gmail_account,
      categories: _categories
    } do
      # Mock Gmail API to return messages
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_123"}, %{"id" => "msg_456"}]}}
      end)

      # First message fails to fetch
      expect(GmailClientMock, :get_message, fn _token, "msg_123" ->
        {:error, :not_found}
      end)

      # Second message succeeds
      expect(GmailClientMock, :get_message, fn _token, "msg_456" ->
        {:ok,
         %{
           id: "msg_456",
           thread_id: "thread_456",
           subject: "Success Email",
           from: %{name: "Sender", email: "sender@example.com"},
           body: "This one works",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: nil
         }}
      end)

      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:ok, nil}
      end)

      expect(AIServiceMock, :summarize_email, fn _content ->
        {:ok, "Summary"}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      assert result == :ok

      # Only the second email should be saved
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1
      assert hd(emails).gmail_message_id == "msg_456"
    end

    test "handles AI quota exceeded with fallback summary", %{
      gmail_account: gmail_account,
      categories: _categories
    } do
      # Mock Gmail API
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_123"}]}}
      end)

      expect(GmailClientMock, :get_message, fn _token, "msg_123" ->
        {:ok,
         %{
           id: "msg_123",
           thread_id: "thread_456",
           subject: "Important Newsletter from Company XYZ",
           from: %{name: "Company XYZ", email: "newsletter@company.com"},
           body: "This is a very important newsletter with lots of content...",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: "<https://company.com/unsubscribe>"
         }}
      end)

      # Mock AI to return quota exceeded error
      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:error, :quota_exceeded}
      end)

      expect(AIServiceMock, :summarize_email, fn _content ->
        {:error, :quota_exceeded}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      # Should still succeed with fallback
      assert result == :ok

      # Verify email was saved with fallback summary
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1

      email = hd(emails)
      assert email.gmail_message_id == "msg_123"
      assert email.category_id == nil
      # Should have fallback summary containing the subject
      assert String.contains?(email.summary, "Important Newsletter")
      # Should not archive since not categorized
    end

    test "handles AI general error with fallback summary", %{
      gmail_account: gmail_account,
      categories: _categories
    } do
      # Mock Gmail API
      expect(GmailClientMock, :list_messages, fn _token, _opts ->
        {:ok, %{"messages" => [%{"id" => "msg_789"}]}}
      end)

      expect(GmailClientMock, :get_message, fn _token, "msg_789" ->
        {:ok,
         %{
           id: "msg_789",
           thread_id: "thread_789",
           subject: "Short",
           from: %{name: "Sender", email: "sender@example.com"},
           body: "This is a short email body that should be included in the fallback summary.",
           date: "2024-01-15T10:30:00Z",
           list_unsubscribe: nil
         }}
      end)

      # Mock AI to return general error
      expect(AIServiceMock, :categorize_email, fn _content, _categories ->
        {:error, :timeout}
      end)

      expect(AIServiceMock, :summarize_email, fn _content ->
        {:error, :api_error}
      end)

      # Perform the import
      job_args = %{"gmail_account_id" => gmail_account.id}
      result = EmailImportWorker.perform(%Oban.Job{args: job_args})

      # Should still succeed with fallback
      assert result == :ok

      # Verify email was saved with fallback summary
      emails = Emails.list_emails_by_account(gmail_account.id)
      assert length(emails) == 1

      email = hd(emails)
      assert email.gmail_message_id == "msg_789"
      assert email.category_id == nil
      # Short subject should include body snippet
      assert String.contains?(email.summary, "Short")
      assert String.contains?(email.summary, "short email body")
    end
  end
end

