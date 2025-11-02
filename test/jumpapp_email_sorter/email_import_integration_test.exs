defmodule JumpappEmailSorter.EmailImportIntegrationTest do
  use JumpappEmailSorter.DataCase, async: false

  alias JumpappEmailSorter.{Accounts, Categories, Emails, AIService}
  alias JumpappEmailSorter.Workers.EmailImportWorker

  @moduletag :integration

  describe "Email Import and Categorization Flow" do
    setup do
      # Create a test user
      {:ok, user} =
        Accounts.upsert_user_from_oauth(%{
          email: "test@example.com",
          name: "Test User",
          google_id: "test_google_id_#{:rand.uniform(100_000)}"
        })

      # Create a test Gmail account
      {:ok, gmail_account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "test_access_token",
          refresh_token: "test_refresh_token",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Create test categories
      {:ok, category1} =
        Categories.create_category(user.id, %{
          name: "Shopping",
          description: "Online shopping receipts and shipping notifications"
        })

      {:ok, category2} =
        Categories.create_category(user.id, %{
          name: "Work",
          description: "Work-related emails and meetings"
        })

      {:ok, category3} =
        Categories.create_category(user.id, %{
          name: "Newsletters",
          description: "Marketing emails and newsletters"
        })

      %{
        user: user,
        gmail_account: gmail_account,
        categories: [category1, category2, category3]
      }
    end

    test "AI categorization returns valid category ID", %{categories: categories} do
      email_content = """
      Subject: Your Amazon Order Has Shipped

      Your order #123-4567890-1234567 has been shipped and will arrive by Friday.

      Track your package: https://amazon.com/track/...
      """

      {:ok, category_id} = AIService.categorize_email(email_content, categories)

      if category_id do
        assert is_integer(category_id)
        assert Enum.any?(categories, fn cat -> cat.id == category_id end)

        category = Enum.find(categories, fn cat -> cat.id == category_id end)
        IO.puts("\n✅ Email categorized as: #{category.name}")
      else
        IO.puts("\n⚠️  No category match found (returned nil)")
      end
    end

    test "AI summarization returns valid summary" do
      email_content = """
      Subject: Team Meeting Tomorrow

      Hi everyone,

      Just a reminder that we have our weekly team meeting tomorrow at 10 AM.
      Please come prepared with your status updates and any blockers you're facing.

      See you there!
      John
      """

      {:ok, summary} = AIService.summarize_email(email_content)

      assert is_binary(summary)
      assert String.length(summary) > 0
      assert String.length(summary) < String.length(email_content)

      IO.puts("\n✅ Generated summary: #{summary}")
    end

    test "create_email saves email to database", %{
      gmail_account: gmail_account,
      categories: categories
    } do
      category = List.first(categories)

      email_attrs = %{
        gmail_account_id: gmail_account.id,
        category_id: category.id,
        gmail_message_id: "test_message_#{:rand.uniform(100_000)}",
        thread_id: "test_thread_123",
        subject: "Test Email Subject",
        from_email: "sender@example.com",
        from_name: "Sender Name",
        received_at: DateTime.utc_now(),
        summary: "This is a test email summary",
        body_preview: "This is a preview of the email body...",
        body_text: "This is the full email body text content.",
        list_unsubscribe_header: "<https://example.com/unsubscribe>",
        unsubscribe_link: "https://example.com/unsubscribe"
      }

      {:ok, email} = Emails.create_email(email_attrs)

      assert email.id != nil
      assert email.gmail_account_id == gmail_account.id
      assert email.category_id == category.id
      assert email.subject == "Test Email Subject"
      assert email.from_email == "sender@example.com"
      assert email.summary == "This is a test email summary"

      IO.puts("\n✅ Email saved to database with ID: #{email.id}")
    end

    test "list_emails_by_category returns emails for a category", %{
      gmail_account: gmail_account,
      categories: categories
    } do
      category = List.first(categories)

      # Create multiple test emails
      for i <- 1..3 do
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: "test_message_#{i}_#{:rand.uniform(100_000)}",
          thread_id: "test_thread_#{i}",
          subject: "Test Email #{i}",
          from_email: "sender#{i}@example.com",
          from_name: "Sender #{i}",
          received_at: DateTime.utc_now(),
          summary: "Summary for email #{i}",
          body_preview: "Preview #{i}",
          body_text: "Body #{i}"
        })
      end

      emails = Emails.list_emails_by_category(category.id)

      assert length(emails) == 3
      assert Enum.all?(emails, fn email -> email.category_id == category.id end)

      IO.puts("\n✅ Retrieved #{length(emails)} emails for category: #{category.name}")

      Enum.each(emails, fn email ->
        IO.puts("   - #{email.subject} from #{email.from_email}")
      end)
    end

    test "list_emails_by_account returns emails for a Gmail account", %{
      gmail_account: gmail_account,
      categories: categories
    } do
      # Create emails in different categories
      Enum.each(categories, fn category ->
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: "test_message_#{category.id}_#{:rand.uniform(100_000)}",
          thread_id: "test_thread_#{category.id}",
          subject: "Email in #{category.name}",
          from_email: "sender@example.com",
          from_name: "Sender",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body"
        })
      end)

      emails = Emails.list_emails_by_account(gmail_account.id)

      assert length(emails) == length(categories)
      assert Enum.all?(emails, fn email -> email.gmail_account_id == gmail_account.id end)

      IO.puts("\n✅ Retrieved #{length(emails)} emails for Gmail account")

      Enum.each(emails, fn email ->
        category = Enum.find(categories, fn cat -> cat.id == email.category_id end)
        IO.puts("   - #{email.subject} [#{category.name}]")
      end)
    end

    test "get_email_by_gmail_id prevents duplicate imports", %{
      gmail_account: gmail_account,
      categories: categories
    } do
      category = List.first(categories)
      gmail_message_id = "unique_message_#{:rand.uniform(100_000)}"

      # Create first email
      {:ok, email1} =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: gmail_message_id,
          thread_id: "test_thread",
          subject: "Original Email",
          from_email: "sender@example.com",
          from_name: "Sender",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body"
        })

      # Try to create duplicate
      result =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          # Same Gmail ID
          gmail_message_id: gmail_message_id,
          thread_id: "test_thread",
          subject: "Duplicate Email",
          from_email: "sender@example.com",
          from_name: "Sender",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body"
        })

      # Should fail with unique constraint
      assert {:error, changeset} = result
      # The unique constraint is on [:gmail_account_id, :gmail_message_id]
      # so the error might be on either field
      assert changeset.errors[:gmail_message_id] != nil or changeset.errors[:gmail_account_id] != nil

      # Verify we can find the original
      found_email = Emails.get_email_by_gmail_id(gmail_account.id, gmail_message_id)
      assert found_email.id == email1.id
      assert found_email.subject == "Original Email"

      IO.puts("\n✅ Duplicate prevention working - unique constraint enforced")
    end

    test "full integration: categorize, summarize, and save email", %{
      gmail_account: gmail_account,
      categories: categories
    } do
      # Simulate a real email
      email_content = """
      Subject: Weekly Newsletter - Tech Updates

      Hi there,

      Here's your weekly roundup of the latest tech news:

      1. New AI models released
      2. Cloud computing trends
      3. Security best practices

      Stay informed!
      Tech News Team
      """

      # Step 1: Categorize
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      IO.puts("\n📧 Processing email...")

      if category_id do
        category = Enum.find(categories, fn cat -> cat.id == category_id end)
        IO.puts("   ✅ Categorized as: #{category.name}")
      else
        IO.puts("   ⚠️  No category match")
      end

      # Step 2: Summarize
      {:ok, summary} = AIService.summarize_email(email_content)
      IO.puts("   ✅ Summary: #{summary}")

      # Step 3: Save to database
      {:ok, email} =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category_id,
          gmail_message_id: "integration_test_#{:rand.uniform(100_000)}",
          thread_id: "thread_123",
          subject: "Weekly Newsletter - Tech Updates",
          from_email: "news@techcompany.com",
          from_name: "Tech News Team",
          received_at: DateTime.utc_now(),
          summary: summary,
          body_preview: String.slice(email_content, 0, 200),
          body_text: email_content
        })

      IO.puts("   ✅ Saved to database with ID: #{email.id}")

      # Step 4: Verify retrieval
      if category_id do
        emails_in_category = Emails.list_emails_by_category(category_id)
        assert Enum.any?(emails_in_category, fn e -> e.id == email.id end)
        IO.puts("   ✅ Email retrievable from category")
      end

      emails_in_account = Emails.list_emails_by_account(gmail_account.id)
      assert Enum.any?(emails_in_account, fn e -> e.id == email.id end)
      IO.puts("   ✅ Email retrievable from account")

      IO.puts("\n🎉 Full integration test passed!")
    end
  end
end
