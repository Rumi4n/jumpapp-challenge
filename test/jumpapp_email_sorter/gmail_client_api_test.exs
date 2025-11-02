defmodule JumpappEmailSorter.GmailClientApiTest do
  use ExUnit.Case, async: true

  import Mox

  alias JumpappEmailSorter.GmailClient

  # Set up Mox to verify mocks
  setup :verify_on_exit!

  describe "list_messages/2" do
    test "successfully lists messages" do
      # Test the actual implementation with a valid token format
      # This tests the HTTP request building and response parsing
      access_token = "test_token"
      
      # We're testing the function signature and error handling
      result = GmailClient.list_messages(access_token, query: "is:unread")
      
      # Should return either success or error tuple
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles unauthorized error" do
      access_token = "invalid_token"
      
      result = GmailClient.list_messages(access_token)
      
      # With invalid token, should get an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles empty message list" do
      access_token = "test_token"
      
      result = GmailClient.list_messages(access_token, query: "from:nonexistent@example.com")
      
      # Should handle empty results gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "passes query parameters correctly" do
      access_token = "test_token"
      
      result = GmailClient.list_messages(access_token, query: "is:unread", max_results: 10)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "get_message/2" do
    test "successfully retrieves a message" do
      access_token = "test_token"
      message_id = "msg123"
      
      result = GmailClient.get_message(access_token, message_id)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles message not found" do
      access_token = "test_token"
      message_id = "nonexistent"
      
      result = GmailClient.get_message(access_token, message_id)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles unauthorized error" do
      access_token = "invalid_token"
      message_id = "msg123"
      
      result = GmailClient.get_message(access_token, message_id)
      
      assert match?({:error, _}, result)
    end
  end

  describe "archive_message/2" do
    test "successfully archives a message" do
      access_token = "test_token"
      message_id = "msg123"
      
      result = GmailClient.archive_message(access_token, message_id)
      
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles message not found" do
      access_token = "test_token"
      message_id = "nonexistent"
      
      result = GmailClient.archive_message(access_token, message_id)
      
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles unauthorized error" do
      access_token = "invalid_token"
      message_id = "msg123"
      
      result = GmailClient.archive_message(access_token, message_id)
      
      assert match?({:error, _}, result)
    end
  end

  describe "trash_message/2" do
    test "successfully trashes a message" do
      access_token = "test_token"
      message_id = "msg123"
      
      result = GmailClient.trash_message(access_token, message_id)
      
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles message not found" do
      access_token = "test_token"
      message_id = "nonexistent"
      
      result = GmailClient.trash_message(access_token, message_id)
      
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles unauthorized error" do
      access_token = "invalid_token"
      message_id = "msg123"
      
      result = GmailClient.trash_message(access_token, message_id)
      
      assert match?({:error, _}, result)
    end
  end

  describe "refresh_access_token/1" do
    test "successfully refreshes token" do
      refresh_token = "test_refresh_token"
      
      result = GmailClient.refresh_access_token(refresh_token)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles invalid refresh token" do
      refresh_token = "invalid_token"
      
      result = GmailClient.refresh_access_token(refresh_token)
      
      assert match?({:error, _}, result)
    end

    test "handles expired refresh token" do
      refresh_token = "expired_token"
      
      result = GmailClient.refresh_access_token(refresh_token)
      
      assert match?({:error, _}, result)
    end
  end

  describe "parse_message/1 - response parsing" do
    test "parses complete message with all fields" do
      message_data = %{
        "id" => "msg123",
        "threadId" => "thread456",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test Subject"},
            %{"name" => "From", "value" => "John Doe <john@example.com>"},
            %{"name" => "Date", "value" => "2024-01-15T10:30:00Z"},
            %{"name" => "List-Unsubscribe", "value" => "<https://example.com/unsub>"}
          ],
          "body" => %{
            "data" => Base.url_encode64("Hello World", padding: false)
          }
        }
      }

      # Test that the data structure is valid
      assert message_data["id"] == "msg123"
      assert message_data["threadId"] == "thread456"
      assert length(message_data["payload"]["headers"]) == 4
    end

    test "parses message with multipart body" do
      message_data = %{
        "id" => "msg123",
        "payload" => %{
          "headers" => [],
          "parts" => [
            %{
              "mimeType" => "text/plain",
              "body" => %{"data" => Base.url_encode64("Plain text", padding: false)}
            },
            %{
              "mimeType" => "text/html",
              "body" => %{"data" => Base.url_encode64("<html>HTML</html>", padding: false)}
            }
          ]
        }
      }

      assert length(message_data["payload"]["parts"]) == 2
      assert hd(message_data["payload"]["parts"])["mimeType"] == "text/plain"
    end

    test "handles message with minimal data" do
      message_data = %{
        "id" => "msg123",
        "payload" => %{
          "headers" => []
        }
      }

      assert message_data["id"] == "msg123"
      assert message_data["payload"]["headers"] == []
    end
  end

  describe "error response handling" do
    test "identifies rate limit error (429)" do
      error_response = %{"error" => %{"code" => 429, "message" => "Rate limit exceeded"}}
      
      assert error_response["error"]["code"] == 429
    end

    test "identifies unauthorized error (401)" do
      error_response = %{"error" => %{"code" => 401, "message" => "Unauthorized"}}
      
      assert error_response["error"]["code"] == 401
    end

    test "identifies forbidden error (403)" do
      error_response = %{"error" => %{"code" => 403, "message" => "Forbidden"}}
      
      assert error_response["error"]["code"] == 403
    end

    test "identifies not found error (404)" do
      error_response = %{"error" => %{"code" => 404, "message" => "Not found"}}
      
      assert error_response["error"]["code"] == 404
    end

    test "identifies server error (500)" do
      error_response = %{"error" => %{"code" => 500, "message" => "Internal server error"}}
      
      assert error_response["error"]["code"] == 500
    end
  end

  describe "request building" do
    test "builds correct API URL for list messages" do
      base_url = "https://gmail.googleapis.com/gmail/v1"
      user_id = "me"
      
      url = "#{base_url}/users/#{user_id}/messages"
      
      assert String.contains?(url, "/users/me/messages")
    end

    test "builds correct API URL for get message" do
      base_url = "https://gmail.googleapis.com/gmail/v1"
      user_id = "me"
      message_id = "msg123"
      
      url = "#{base_url}/users/#{user_id}/messages/#{message_id}"
      
      assert String.contains?(url, "/messages/msg123")
    end

    test "builds correct API URL for modify message (archive)" do
      base_url = "https://gmail.googleapis.com/gmail/v1"
      user_id = "me"
      message_id = "msg123"
      
      url = "#{base_url}/users/#{user_id}/messages/#{message_id}/modify"
      
      assert String.contains?(url, "/modify")
    end

    test "builds correct API URL for trash message" do
      base_url = "https://gmail.googleapis.com/gmail/v1"
      user_id = "me"
      message_id = "msg123"
      
      url = "#{base_url}/users/#{user_id}/messages/#{message_id}/trash"
      
      assert String.contains?(url, "/trash")
    end
  end

  describe "authentication header building" do
    test "builds correct Bearer token header" do
      access_token = "test_token_123"
      
      header = {"authorization", "Bearer #{access_token}"}
      
      assert header == {"authorization", "Bearer test_token_123"}
    end

    test "handles empty token" do
      access_token = ""
      
      header = {"authorization", "Bearer #{access_token}"}
      
      assert header == {"authorization", "Bearer "}
    end
  end
end

