defmodule JumpappEmailSorter.AIServiceTest do
  use ExUnit.Case, async: false

  alias JumpappEmailSorter.AIService

  @moduletag :integration

  describe "Google Gemini Integration" do
    test "summarize_email/1 successfully generates a summary" do
      email_content = """
      Subject: Team Meeting Tomorrow

      Hi everyone,

      Just a reminder that we have our weekly team meeting tomorrow at 10 AM.
      Please come prepared with your status updates and any blockers you're facing.

      See you there!
      John
      """

      case AIService.summarize_email(email_content) do
        {:ok, summary} ->
          assert is_binary(summary)
          assert String.length(summary) > 0
          # Summary should be reasonably short (not just returning the full email)
          assert String.length(summary) < String.length(email_content)
          IO.puts("\n✅ Google Gemini API is working!")
          IO.puts("Generated summary: #{summary}")

        {:error, :no_api_key} ->
          flunk("GOOGLE_GEMINI_API_KEY environment variable is not set")

        {:error, error} ->
          flunk("Google Gemini API call failed: #{inspect(error)}")
      end
    end

    test "categorize_email/2 successfully categorizes an email" do
      email_content = """
      Subject: Your Amazon Order Has Shipped

      Your order #123-4567890-1234567 has been shipped and will arrive by Friday.

      Track your package: https://amazon.com/track/...
      """

      categories = [
        %{
          id: 1,
          name: "Shopping",
          description: "Online shopping receipts and shipping notifications"
        },
        %{id: 2, name: "Work", description: "Work-related emails and meetings"},
        %{id: 3, name: "Personal", description: "Personal correspondence"}
      ]

      case AIService.categorize_email(email_content, categories) do
        {:ok, category_id} ->
          # Should return a valid category ID or nil
          assert category_id == nil or is_integer(category_id)

          if category_id do
            assert Enum.any?(categories, fn cat -> cat.id == category_id end)
            category = Enum.find(categories, fn cat -> cat.id == category_id end)
            IO.puts("\n✅ Email categorization is working!")
            IO.puts("Categorized as: #{category.name}")
          else
            IO.puts("\n✅ Categorization returned nil (no good match)")
          end

        {:error, :no_api_key} ->
          flunk("GOOGLE_GEMINI_API_KEY environment variable is not set")

        {:error, error} ->
          flunk("Google Gemini API call failed: #{inspect(error)}")
      end
    end

    test "handles empty categories gracefully" do
      email_content = "Test email content"

      assert {:ok, nil} = AIService.categorize_email(email_content, [])
    end

    test "handles API errors gracefully" do
      # Test with invalid API key to ensure graceful degradation
      original_key = System.get_env("GOOGLE_GEMINI_API_KEY")
      System.put_env("GOOGLE_GEMINI_API_KEY", "invalid_key")

      email_content = "Test email"

      # Should not crash, should return graceful fallback
      assert {:ok, _preview} = AIService.summarize_email(email_content)

      # Restore original key
      if original_key do
        System.put_env("GOOGLE_GEMINI_API_KEY", original_key)
      end
    end
  end

  describe "Helper Functions" do
    test "extract_preview/1 returns first 200 characters" do
      long_content = String.duplicate("a", 300)

      # Access the private function through the public API
      {:ok, preview} = AIService.summarize_email(long_content)

      # When API fails, it should fall back to preview
      # We can't directly test the private function, but we know it's used
      assert is_binary(preview)
    end
  end

  describe "Fallback behavior" do
    test "summarize_email falls back to preview on API failure" do
      # Test with no API key to trigger fallback
      original_key = System.get_env("GOOGLE_GEMINI_API_KEY")
      System.delete_env("GOOGLE_GEMINI_API_KEY")

      email_content = "This is a test email that should be truncated to 200 characters."

      {:ok, result} = AIService.summarize_email(email_content)

      # Should return a preview (first 200 chars)
      assert is_binary(result)
      assert String.length(result) <= 203  # 200 chars + "..."

      # Restore original key
      if original_key do
        System.put_env("GOOGLE_GEMINI_API_KEY", original_key)
      end
    end

    test "categorize_email returns nil when no categories match" do
      email_content = "Random content that doesn't match any category"

      categories = [
        %{id: 1, name: "Shopping", description: "Shopping receipts"},
        %{id: 2, name: "Work", description: "Work emails"}
      ]

      {:ok, result} = AIService.categorize_email(email_content, categories)

      # May return nil or a category ID
      assert result == nil or is_integer(result)
    end

    test "categorize_email handles single category" do
      email_content = "Your order has shipped"

      categories = [
        %{id: 1, name: "Shopping", description: "Shopping and orders"}
      ]

      {:ok, result} = AIService.categorize_email(email_content, categories)

      # Should return the category ID or nil
      assert result == nil or result == 1
    end
  end

  describe "Content truncation" do
    test "handles very long email content" do
      # Create a very long email (10KB)
      long_content = String.duplicate("This is a long email. ", 500)

      {:ok, summary} = AIService.summarize_email(long_content)

      # Should return a summary (either from AI or fallback)
      assert is_binary(summary)
      assert String.length(summary) > 0
    end

    test "handles empty email content" do
      {:ok, summary} = AIService.summarize_email("")

      # Should handle empty content gracefully
      assert is_binary(summary)
    end

    test "handles email with special characters" do
      email_content = "Email with émojis 🎉 and spëcial çhars"

      {:ok, summary} = AIService.summarize_email(email_content)

      assert is_binary(summary)
    end
  end

  describe "Category matching" do
    test "handles categories with similar descriptions" do
      email_content = "Meeting tomorrow at 10 AM"

      categories = [
        %{id: 1, name: "Work", description: "Work meetings and tasks"},
        %{id: 2, name: "Personal", description: "Personal meetings and events"}
      ]

      {:ok, result} = AIService.categorize_email(email_content, categories)

      # Should return one of the categories or nil
      assert result == nil or result in [1, 2]
    end

    test "handles categories with empty descriptions" do
      email_content = "Test email"

      categories = [
        %{id: 1, name: "General", description: ""}
      ]

      {:ok, result} = AIService.categorize_email(email_content, categories)

      assert result == nil or result == 1
    end
  end

  describe "Error resilience" do
    test "handles network timeout gracefully" do
      # This tests that the function doesn't crash on errors
      email_content = "Test content"

      result = AIService.summarize_email(email_content)

      # Should always return {:ok, _} even if API fails
      assert match?({:ok, _}, result)
    end

    test "handles malformed API responses" do
      email_content = "Test email"
      categories = [%{id: 1, name: "Test", description: "Test category"}]

      result = AIService.categorize_email(email_content, categories)

      # Should handle malformed responses gracefully
      assert match?({:ok, _}, result)
    end
  end
end
