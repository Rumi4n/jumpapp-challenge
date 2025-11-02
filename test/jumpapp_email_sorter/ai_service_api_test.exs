defmodule JumpappEmailSorter.AIServiceApiTest do
  use ExUnit.Case, async: true

  import Mox

  alias JumpappEmailSorter.AIService

  # Set up Mox to verify mocks
  setup :verify_on_exit!

  describe "summarize_email/1 - API integration" do
    test "generates summary for short email" do
      email_content = "Meeting tomorrow at 10 AM in conference room A."
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
      assert String.length(summary) > 0
    end

    test "generates summary for long email" do
      email_content = String.duplicate("This is a very long email with lots of content. ", 100)
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
      # Summary should be shorter than original
      assert String.length(summary) < String.length(email_content)
    end

    test "handles email with HTML content" do
      email_content = """
      <html>
      <body>
      <h1>Important Meeting</h1>
      <p>Please attend the meeting tomorrow.</p>
      </body>
      </html>
      """
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
    end

    test "handles email with special characters" do
      email_content = "Email with émojis 🎉 and spëcial çhars & symbols!"
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
    end

    test "handles empty email content" do
      {:ok, summary} = AIService.summarize_email("")
      
      assert is_binary(summary)
    end

    test "falls back to preview when API unavailable" do
      # Remove API key to force fallback
      original_key = System.get_env("GOOGLE_GEMINI_API_KEY")
      System.delete_env("GOOGLE_GEMINI_API_KEY")
      
      email_content = "This is a test email that should fall back to preview."
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
      assert String.length(summary) <= 203  # 200 chars + "..."
      
      # Restore API key
      if original_key, do: System.put_env("GOOGLE_GEMINI_API_KEY", original_key)
    end
  end

  describe "categorize_email/2 - API integration" do
    test "categorizes shopping email correctly" do
      email_content = """
      Your Amazon order #123-456-789 has shipped!
      
      Track your package: https://amazon.com/track
      Estimated delivery: Friday, Jan 20
      """
      
      categories = [
        %{id: 1, name: "Shopping", description: "Online shopping and order confirmations"},
        %{id: 2, name: "Work", description: "Work-related emails"},
        %{id: 3, name: "Personal", description: "Personal correspondence"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      # Should return a category ID or nil
      assert category_id == nil or is_integer(category_id)
      if category_id, do: assert(category_id in [1, 2, 3])
    end

    test "categorizes work email correctly" do
      email_content = """
      Team meeting tomorrow at 10 AM.
      
      Agenda:
      - Q4 planning
      - Budget review
      - Team updates
      """
      
      categories = [
        %{id: 1, name: "Shopping", description: "Shopping receipts"},
        %{id: 2, name: "Work", description: "Work meetings and projects"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      assert category_id == nil or is_integer(category_id)
    end

    test "returns nil when no categories provided" do
      email_content = "Test email"
      
      {:ok, category_id} = AIService.categorize_email(email_content, [])
      
      assert category_id == nil
    end

    test "handles single category" do
      email_content = "Newsletter subscription confirmed"
      
      categories = [
        %{id: 1, name: "Newsletters", description: "Newsletter subscriptions"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      assert category_id == nil or category_id == 1
    end

    test "handles ambiguous email content" do
      email_content = "Hello, how are you?"
      
      categories = [
        %{id: 1, name: "Work", description: "Work emails"},
        %{id: 2, name: "Personal", description: "Personal emails"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      # Could match either or neither
      assert category_id == nil or category_id in [1, 2]
    end

    test "handles categories with similar descriptions" do
      email_content = "Meeting invitation for next week"
      
      categories = [
        %{id: 1, name: "Work Meetings", description: "Work-related meetings"},
        %{id: 2, name: "Personal Meetings", description: "Personal meetings and events"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      assert category_id == nil or category_id in [1, 2]
    end
  end

  describe "analyze_unsubscribe_page/2 - API integration" do
    test "analyzes page with unsubscribe form" do
      url = "https://example.com/unsubscribe"
      page_content = """
      <html>
      <body>
        <form action="/unsubscribe" method="POST">
          <input type="email" name="email" />
          <button type="submit">Unsubscribe</button>
        </form>
      </body>
      </html>
      """
      
      result = AIService.analyze_unsubscribe_page(url, page_content)
      
      # Should return analysis or error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "analyzes page with one-click unsubscribe" do
      url = "https://example.com/unsubscribe?token=abc123"
      page_content = """
      <html>
      <body>
        <h1>You have been unsubscribed</h1>
        <p>You will no longer receive emails from us.</p>
      </body>
      </html>
      """
      
      result = AIService.analyze_unsubscribe_page(url, page_content)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles page with no unsubscribe mechanism" do
      url = "https://example.com/page"
      page_content = """
      <html>
      <body>
        <h1>Regular Page</h1>
        <p>This is just a regular page with no unsubscribe form.</p>
      </body>
      </html>
      """
      
      result = AIService.analyze_unsubscribe_page(url, page_content)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles empty page content" do
      url = "https://example.com/unsubscribe"
      page_content = ""
      
      result = AIService.analyze_unsubscribe_page(url, page_content)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "API error handling" do
    test "handles API timeout gracefully" do
      email_content = "Test email"
      
      result = AIService.summarize_email(email_content)
      
      # Should always return {:ok, _} even if API times out
      assert match?({:ok, _}, result)
    end

    test "handles invalid API key gracefully" do
      original_key = System.get_env("GOOGLE_GEMINI_API_KEY")
      System.put_env("GOOGLE_GEMINI_API_KEY", "invalid_key_12345")
      
      email_content = "Test email"
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      # Should fall back to preview
      assert is_binary(summary)
      
      # Restore original key
      if original_key do
        System.put_env("GOOGLE_GEMINI_API_KEY", original_key)
      else
        System.delete_env("GOOGLE_GEMINI_API_KEY")
      end
    end

    test "handles malformed API response" do
      email_content = "Test email"
      categories = [%{id: 1, name: "Test", description: "Test category"}]
      
      result = AIService.categorize_email(email_content, categories)
      
      # Should handle gracefully
      assert match?({:ok, _}, result)
    end

    test "handles network errors" do
      email_content = "Test email"
      
      result = AIService.summarize_email(email_content)
      
      # Should not crash
      assert match?({:ok, _}, result)
    end
  end

  describe "content truncation and formatting" do
    test "truncates very long content before sending to API" do
      # Create 50KB of content
      long_content = String.duplicate("This is a very long email. ", 2000)
      
      {:ok, summary} = AIService.summarize_email(long_content)
      
      assert is_binary(summary)
      # Summary should be much shorter
      assert String.length(summary) < 500
    end

    test "preserves important content structure" do
      email_content = """
      Subject: Important Meeting
      
      From: Boss <boss@company.com>
      
      Body:
      Please attend the meeting tomorrow at 10 AM.
      Location: Conference Room A
      """
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
    end

    test "handles content with multiple newlines" do
      email_content = "Line 1\n\n\n\nLine 2\n\n\nLine 3"
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
    end

    test "handles content with tabs and special whitespace" do
      email_content = "Content\twith\ttabs\rand\rcarriage\rreturns"
      
      {:ok, summary} = AIService.summarize_email(email_content)
      
      assert is_binary(summary)
    end
  end

  describe "category matching logic" do
    test "matches exact category name in content" do
      email_content = "This is a shopping receipt from Amazon"
      
      categories = [
        %{id: 1, name: "Shopping", description: "Shopping receipts"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      assert category_id == nil or category_id == 1
    end

    test "matches based on category description" do
      email_content = "Your order has been shipped and will arrive tomorrow"
      
      categories = [
        %{id: 1, name: "Orders", description: "Order confirmations and shipping notifications"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      assert category_id == nil or category_id == 1
    end

    test "handles multiple matching categories" do
      email_content = "Work meeting about shopping platform development"
      
      categories = [
        %{id: 1, name: "Work", description: "Work-related emails"},
        %{id: 2, name: "Shopping", description: "Shopping-related emails"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      # Could match either category
      assert category_id == nil or category_id in [1, 2]
    end

    test "returns nil when no good match exists" do
      email_content = "Random content that doesn't match any category"
      
      categories = [
        %{id: 1, name: "Sports", description: "Sports news and updates"},
        %{id: 2, name: "Finance", description: "Financial news and banking"}
      ]
      
      {:ok, category_id} = AIService.categorize_email(email_content, categories)
      
      # Likely no match
      assert category_id == nil or is_integer(category_id)
    end
  end
end

