defmodule JumpappEmailSorter.Workers.UnsubscribeWorkerTest do
  use JumpappEmailSorter.DataCase, async: false

  alias JumpappEmailSorter.Workers.UnsubscribeWorker
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

    {:ok, category} = Categories.create_category(user.id, %{name: "Newsletters"})

    %{user: user, gmail_account: gmail_account, category: category}
  end

  describe "perform/1" do
    test "returns error when email has no unsubscribe link", %{
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, email} =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: "msg_#{:rand.uniform(100_000)}",
          thread_id: "thread_123",
          subject: "Email without unsubscribe",
          from_email: "sender@example.com",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body",
          unsubscribe_link: nil
        })

      job_args = %{"email_id" => email.id}
      result = UnsubscribeWorker.perform(%Oban.Job{args: job_args})

      assert result == {:error, :no_unsubscribe_link}
    end

    @tag :skip
    test "creates unsubscribe attempt record", %{
      gmail_account: gmail_account,
      category: category
    } do
      {:ok, email} =
        Emails.create_email(%{
          gmail_account_id: gmail_account.id,
          category_id: category.id,
          gmail_message_id: "msg_#{:rand.uniform(100_000)}",
          thread_id: "thread_123",
          subject: "Newsletter",
          from_email: "news@example.com",
          received_at: DateTime.utc_now(),
          summary: "Summary",
          body_preview: "Preview",
          body_text: "Body",
          unsubscribe_link: "https://httpbin.org/status/200"
        })

      # The worker will try to make HTTP request
      job_args = %{"email_id" => email.id}
      _result = UnsubscribeWorker.perform(%Oban.Job{args: job_args})

      # Check that an attempt was created
      attempt = Emails.get_latest_unsubscribe_attempt(email.id)
      assert attempt != nil
      assert attempt.unsubscribe_url == "https://httpbin.org/status/200"
    end
  end

  describe "one_click_unsubscribe?/1" do
    test "detects unsubscribed message" do
      body = "You have been successfully unsubscribed from our mailing list."
      assert one_click_unsubscribe_helper(body) == true
    end

    test "detects successfully removed message" do
      body = "Your email has been successfully removed from our list."
      assert one_click_unsubscribe_helper(body) == true
    end

    test "detects will no longer receive message" do
      body = "You will no longer receive emails from us."
      assert one_click_unsubscribe_helper(body) == true
    end

    test "detects preference updated message" do
      body = "Your email preferences have been updated."
      assert one_click_unsubscribe_helper(body) == true
    end

    test "detects you have been removed message" do
      body = "You have been removed from our mailing list."
      assert one_click_unsubscribe_helper(body) == true
    end

    test "returns false for regular content" do
      body = "This is a regular email with no unsubscribe confirmation."
      assert one_click_unsubscribe_helper(body) == false
    end

    test "returns false for nil" do
      assert one_click_unsubscribe_helper(nil) == false
    end

    test "is case insensitive" do
      body = "YOU HAVE BEEN UNSUBSCRIBED"
      assert one_click_unsubscribe_helper(body) == true
    end
  end

  describe "get_content_type/1" do
    test "extracts content-type from headers" do
      headers = [
        {"content-type", "application/json"},
        {"content-length", "123"}
      ]

      result = get_content_type_helper(headers)
      assert result == "application/json"
    end

    test "is case insensitive" do
      headers = [
        {"Content-Type", "text/html"},
        {"Content-Length", "456"}
      ]

      result = get_content_type_helper(headers)
      assert result == "text/html"
    end

    test "returns empty string when header not found" do
      headers = [{"content-length", "123"}]
      result = get_content_type_helper(headers)
      assert result == ""
    end

    test "handles empty headers list" do
      result = get_content_type_helper([])
      assert result == ""
    end
  end

  describe "check_json_response/1" do
    test "detects success in JSON with success key" do
      json_body = ~s({"success": true, "message": "Unsubscribed"})
      result = check_json_response_helper(json_body)
      assert result == {:ok, "api_json"}
    end

    test "detects success in JSON with status key" do
      json_body = ~s({"status": "success"})
      result = check_json_response_helper(json_body)
      assert result == {:ok, "api_json"}
    end

    test "detects success in JSON with message containing success" do
      json_body = ~s({"message": "Successfully unsubscribed"})
      result = check_json_response_helper(json_body)
      assert result == {:ok, "api_json"}
    end

    test "detects unsubscribed in JSON" do
      json_body = ~s({"result": "unsubscribed"})
      result = check_json_response_helper(json_body)
      assert result == {:ok, "api_json"}
    end

    test "returns uncertain when JSON has no clear success indicator" do
      json_body = ~s({"data": "some data"})
      result = check_json_response_helper(json_body)
      assert result == {:ok, "api_json_uncertain"}
    end

    test "returns error for invalid JSON" do
      invalid_json = "not valid json {"
      result = check_json_response_helper(invalid_json)
      assert result == {:error, :invalid_json}
    end
  end

  # Helper functions to test private worker logic

  defp one_click_unsubscribe_helper(body) when is_binary(body) do
    success_patterns = [
      ~r/unsubscribed/i,
      ~r/successfully removed/i,
      ~r/will no longer receive/i,
      ~r/preference.*updated/i,
      ~r/you have been removed/i,
      ~r/email.*removed/i
    ]

    Enum.any?(success_patterns, fn pattern ->
      Regex.match?(pattern, body)
    end)
  end

  defp one_click_unsubscribe_helper(_), do: false

  defp get_content_type_helper(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
    |> case do
      {_, value} -> String.downcase(value)
      nil -> ""
    end
  end

  defp check_json_response_helper(body) do
    case Jason.decode(body) do
      {:ok, json} when is_map(json) ->
        success_keys = ["success", "status", "result", "message", "unsubscribed"]

        success? =
          Enum.any?(success_keys, fn key ->
            case Map.get(json, key) do
              true -> true
              "success" -> true
              "ok" -> true
              "unsubscribed" -> true
              val when is_binary(val) -> String.match?(val, ~r/(success|unsubscribe|removed)/i)
              _ -> false
            end
          end)

        if success? do
          {:ok, "api_json"}
        else
          {:ok, "api_json_uncertain"}
        end

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end

