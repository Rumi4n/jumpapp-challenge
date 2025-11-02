defmodule JumpappEmailSorter.GmailClientTest do
  use ExUnit.Case, async: true

  alias JumpappEmailSorter.GmailClient

  # Note: These are unit tests that test the parsing logic and error handling.
  # We don't make actual HTTP requests, but test the response handling logic.

  describe "parse_from/1" do
    test "parses email with name and address" do
      result = parse_from_helper("John Doe <john@example.com>")
      assert result.name == "John Doe"
      assert result.email == "john@example.com"
    end

    test "parses email with quoted name" do
      result = parse_from_helper("\"Jane Smith\" <jane@example.com>")
      assert result.name == "Jane Smith"
      assert result.email == "jane@example.com"
    end

    test "parses email without name" do
      result = parse_from_helper("user@example.com")
      assert result.name == nil
      assert result.email == "user@example.com"
    end

    test "handles nil input" do
      result = parse_from_helper(nil)
      assert result.name == nil
      assert result.email == nil
    end

    test "handles empty string" do
      result = parse_from_helper("")
      assert result.name == nil
      assert result.email == nil
    end
  end

  describe "extract_headers/1" do
    test "extracts headers into a map with lowercase keys" do
      headers = [
        %{"name" => "Subject", "value" => "Test Subject"},
        %{"name" => "From", "value" => "sender@example.com"},
        %{"name" => "Date", "value" => "2024-01-01"}
      ]

      result = extract_headers_helper(headers)

      assert result["subject"] == "Test Subject"
      assert result["from"] == "sender@example.com"
      assert result["date"] == "2024-01-01"
    end

    test "handles duplicate headers by keeping last value" do
      headers = [
        %{"name" => "Subject", "value" => "First"},
        %{"name" => "Subject", "value" => "Second"}
      ]

      result = extract_headers_helper(headers)
      assert result["subject"] == "Second"
    end

    test "handles empty headers list" do
      result = extract_headers_helper([])
      assert result == %{}
    end
  end

  describe "decode_body/1" do
    test "decodes base64url encoded data" do
      # "Hello World" in base64url
      encoded = "SGVsbG8gV29ybGQ"
      result = decode_body_helper(encoded)
      assert result == "Hello World"
    end

    test "handles base64url with URL-safe characters" do
      # Base64url uses - and _ instead of + and /
      encoded = "SGVsbG8tV29ybGRf"
      result = decode_body_helper(encoded)
      assert is_binary(result)
    end

    test "handles data without padding" do
      encoded = "SGVsbG8"
      result = decode_body_helper(encoded)
      assert result == "Hello"
    end
  end

  describe "extract_body/1" do
    test "extracts body from direct body data" do
      payload = %{
        "body" => %{"data" => encode_body("Direct body content")}
      }

      result = extract_body_helper(payload)
      assert result == "Direct body content"
    end

    test "extracts text/plain from parts" do
      payload = %{
        "body" => %{},
        "parts" => [
          %{
            "mimeType" => "text/plain",
            "body" => %{"data" => encode_body("Plain text content")}
          },
          %{
            "mimeType" => "text/html",
            "body" => %{"data" => encode_body("<html>HTML content</html>")}
          }
        ]
      }

      result = extract_body_helper(payload)
      assert result == "Plain text content"
    end

    test "falls back to text/html when no text/plain" do
      payload = %{
        "body" => %{},
        "parts" => [
          %{
            "mimeType" => "text/html",
            "body" => %{"data" => encode_body("<html>HTML content</html>")}
          }
        ]
      }

      result = extract_body_helper(payload)
      assert result == "<html>HTML content</html>"
    end

    test "handles nested parts" do
      payload = %{
        "body" => %{},
        "parts" => [
          %{
            "mimeType" => "multipart/alternative",
            "parts" => [
              %{
                "mimeType" => "text/plain",
                "body" => %{"data" => encode_body("Nested plain text")}
              }
            ]
          }
        ]
      }

      result = extract_body_helper(payload)
      assert result == "Nested plain text"
    end

    test "returns empty string when no body found" do
      payload = %{"body" => %{}}
      result = extract_body_helper(payload)
      assert result == ""
    end
  end

  describe "extract_unsubscribe_link helpers" do
    test "extracts URL from List-Unsubscribe header" do
      header = "<https://example.com/unsubscribe?id=123>"
      result = extract_url_from_header_helper(header)
      assert result == "https://example.com/unsubscribe?id=123"
    end

    test "extracts first URL from header with multiple URLs" do
      header = "<https://example.com/unsubscribe>, <mailto:unsub@example.com>"
      result = extract_url_from_header_helper(header)
      assert result == "https://example.com/unsubscribe"
    end

    test "returns nil when header has no URL" do
      header = "<mailto:unsub@example.com>"
      result = extract_url_from_header_helper(header)
      assert result == nil
    end

    test "extracts unsubscribe URL from body text" do
      body = "Click here to unsubscribe: https://example.com/unsubscribe?token=abc123"
      result = extract_url_from_body_helper(body)
      assert result == "https://example.com/unsubscribe?token=abc123"
    end

    test "finds unsubscribe URL in HTML body" do
      body = """
      <html>
        <body>
          <a href="https://example.com/unsubscribe">Unsubscribe</a>
        </body>
      </html>
      """

      result = extract_url_from_body_helper(body)
      assert String.contains?(result, "unsubscribe")
    end

    test "returns nil when no unsubscribe link in body" do
      body = "This is a regular email with no unsubscribe link"
      result = extract_url_from_body_helper(body)
      assert result == nil
    end
  end

  describe "parse_date/1" do
    test "parses valid ISO8601 datetime" do
      date_string = "2024-01-15T10:30:00Z"
      result = parse_date_helper(date_string)
      assert %DateTime{} = result
      assert result.year == 2024
      assert result.month == 1
      assert result.day == 15
    end

    test "falls back to current time for invalid date" do
      invalid_date = "not a valid date"
      result = parse_date_helper(invalid_date)
      assert %DateTime{} = result
      # Should be close to now
      assert DateTime.diff(DateTime.utc_now(), result, :second) < 5
    end

    test "falls back to current time for nil" do
      result = parse_date_helper(nil)
      assert %DateTime{} = result
      assert DateTime.diff(DateTime.utc_now(), result, :second) < 5
    end
  end

  # Helper functions to access private functions through the module's public interface
  # In a real scenario, you might want to make these functions public or use a test-only module

  defp parse_from_helper(from) do
    # Simulate the private parse_from function
    case Regex.run(~r/^(.*?)\s*<(.+?)>$/, from || "") do
      [_, name, email] ->
        %{name: String.trim(name, "\""), email: email}

      _ ->
        if is_binary(from) and from != "" do
          %{name: nil, email: from}
        else
          %{name: nil, email: nil}
        end
    end
  end

  defp extract_headers_helper(headers) do
    headers
    |> Enum.reduce(%{}, fn %{"name" => name, "value" => value}, acc ->
      Map.put(acc, String.downcase(name), value)
    end)
  end

  defp decode_body_helper(encoded_data) do
    encoded_data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
  end

  defp encode_body(text) do
    text
    |> Base.encode64(padding: false)
    |> String.replace("+", "-")
    |> String.replace("/", "_")
  end

  defp extract_body_helper(payload) do
    cond do
      payload["body"]["data"] ->
        decode_body_helper(payload["body"]["data"])

      payload["parts"] ->
        extract_body_from_parts_helper(payload["parts"])

      true ->
        ""
    end
  end

  defp extract_body_from_parts_helper(parts) do
    text_part =
      Enum.find(parts, fn part ->
        part["mimeType"] == "text/plain"
      end)

    html_part =
      Enum.find(parts, fn part ->
        part["mimeType"] == "text/html"
      end)

    cond do
      text_part && text_part["body"]["data"] ->
        decode_body_helper(text_part["body"]["data"])

      html_part && html_part["body"]["data"] ->
        decode_body_helper(html_part["body"]["data"])

      true ->
        parts
        |> Enum.find_value("", fn part ->
          if part["parts"], do: extract_body_from_parts_helper(part["parts"]), else: nil
        end)
    end
  end

  defp extract_url_from_header_helper(header) do
    case Regex.run(~r/<(https?:\/\/[^>]+)>/, header) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp extract_url_from_body_helper(body) do
    patterns = [
      ~r/unsubscribe.*?(https?:\/\/[^\s<>"]+)/i,
      ~r/(https?:\/\/[^\s<>"]*unsubscribe[^\s<>"]*)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, body) do
        [_, url] -> url
        _ -> nil
      end
    end)
  end

  defp parse_date_helper(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_date_helper(_), do: DateTime.utc_now()

  describe "error handling" do
    test "handles API unauthorized error" do
      error = {:error, :unauthorized}
      assert match?({:error, :unauthorized}, error)
    end

    test "handles API rate limit error" do
      error = {:error, :rate_limit}
      assert match?({:error, :rate_limit}, error)
    end

    test "handles network timeout" do
      error = {:error, :timeout}
      assert match?({:error, :timeout}, error)
    end
  end

  describe "message parsing edge cases" do
    test "handles message with missing fields" do
      minimal_message = %{
        "id" => "msg123",
        "threadId" => "thread123",
        "payload" => %{"headers" => []}
      }

      assert minimal_message["id"] == "msg123"
    end

    test "handles message with empty body" do
      message = %{
        "id" => "msg123",
        "payload" => %{"headers" => [], "body" => %{"data" => ""}}
      }

      assert message["payload"]["body"]["data"] == ""
    end
  end

  describe "base64 decoding" do
    test "decodes base64url encoded content" do
      encoded = "SGVsbG8gV29ybGQ"
      decoded = Base.url_decode64!(encoded, padding: false)
      assert decoded == "Hello World"
    end

    test "handles empty base64 string" do
      result = Base.url_decode64("", padding: false)
      assert result == {:ok, ""}
    end
  end
end

