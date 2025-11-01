defmodule JumpappEmailSorter.GmailClient do
  @moduledoc """
  Gmail API client for interacting with Gmail.
  """

  require Logger

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1"

  @doc """
  Lists messages from Gmail inbox.
  """
  def list_messages(access_token, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)
    query = Keyword.get(opts, :query, "is:unread")

    url = "#{@gmail_api_base}/users/me/messages"

    params = [
      maxResults: max_results,
      q: query
    ]

    case Req.get(url,
           auth: {:bearer, access_token},
           params: params
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Gmail API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, error} ->
        Logger.error("Gmail API request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Gets a single message by ID.
  """
  def get_message(access_token, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}"

    case Req.get(url,
           auth: {:bearer, access_token},
           params: [format: "full"]
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_message(body)}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Gmail API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, error} ->
        Logger.error("Gmail API request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Archives a message (removes from inbox).
  """
  def archive_message(access_token, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}/modify"

    body = %{
      removeLabelIds: ["INBOX"]
    }

    case Req.post(url,
           auth: {:bearer, access_token},
           json: body
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Gmail API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, error} ->
        Logger.error("Gmail API request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Refreshes an access token using a refresh token.
  """
  def refresh_access_token(refresh_token) do
    url = "https://oauth2.googleapis.com/token"

    body = %{
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        expires_at = DateTime.add(DateTime.utc_now(), response["expires_in"], :second)

        {:ok,
         %{
           access_token: response["access_token"],
           expires_at: expires_at
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Token refresh error: #{status} - #{inspect(body)}")
        {:error, {:refresh_failed, status, body}}

      {:error, error} ->
        Logger.error("Token refresh request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  # Private helpers

  defp parse_message(message) do
    headers = extract_headers(message["payload"]["headers"])

    %{
      id: message["id"],
      thread_id: message["threadId"],
      subject: headers["subject"],
      from: parse_from(headers["from"]),
      date: headers["date"],
      list_unsubscribe: headers["list-unsubscribe"],
      body: extract_body(message["payload"])
    }
  end

  defp extract_headers(headers) do
    headers
    |> Enum.reduce(%{}, fn %{"name" => name, "value" => value}, acc ->
      Map.put(acc, String.downcase(name), value)
    end)
  end

  defp parse_from(from) when is_binary(from) do
    # Parse "Name <email@example.com>" format
    case Regex.run(~r/^(.*?)\s*<(.+?)>$/, from) do
      [_, name, email] ->
        %{name: String.trim(name, "\""), email: email}

      _ ->
        %{name: nil, email: from}
    end
  end

  defp parse_from(_), do: %{name: nil, email: nil}

  defp extract_body(payload) do
    cond do
      payload["body"]["data"] ->
        decode_body(payload["body"]["data"])

      payload["parts"] ->
        extract_body_from_parts(payload["parts"])

      true ->
        ""
    end
  end

  defp extract_body_from_parts(parts) do
    # Try to find text/plain first, then text/html
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
        decode_body(text_part["body"]["data"])

      html_part && html_part["body"]["data"] ->
        decode_body(html_part["body"]["data"])

      true ->
        # Try nested parts
        parts
        |> Enum.find_value("", fn part ->
          if part["parts"], do: extract_body_from_parts(part["parts"]), else: nil
        end)
    end
  end

  defp decode_body(encoded_data) do
    encoded_data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
  end
end
