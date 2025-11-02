defmodule JumpappEmailSorter.Workers.UnsubscribeWorker do
  @moduledoc """
  Worker that attempts to unsubscribe from emails.
  """

  use Oban.Worker, queue: :unsubscribe, max_attempts: 2

  require Logger

  alias JumpappEmailSorter.{Emails, AIService}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    Logger.info("Processing unsubscribe for email #{email_id}")

    email = Emails.get_email!(email_id)

    if !email.unsubscribe_link do
      Logger.warning("No unsubscribe link found for email #{email_id}")
      {:error, :no_unsubscribe_link}
    else
      # Create unsubscribe attempt record
      {:ok, attempt} =
        Emails.create_unsubscribe_attempt(email_id, %{
          unsubscribe_url: email.unsubscribe_link,
          status: "processing",
          attempted_at: DateTime.utc_now()
        })

      # Try to unsubscribe
      result = attempt_unsubscribe(email.unsubscribe_link)

      # Update attempt with result
      case result do
        {:ok, method} ->
          Emails.update_unsubscribe_attempt(attempt, %{
            status: "success",
            method: method,
            completed_at: DateTime.utc_now()
          })

          Logger.info("Successfully unsubscribed from email #{email_id}")
          :ok

        {:error, reason} ->
          Emails.update_unsubscribe_attempt(attempt, %{
            status: "failed",
            error_message: inspect(reason),
            completed_at: DateTime.utc_now()
          })

          Logger.error("Failed to unsubscribe from email #{email_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp attempt_unsubscribe(url) do
    # First, try to fetch the page
    case Req.get(url, redirect: true) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type = get_content_type(headers)

        cond do
          # Handle JSON API responses (by content-type header)
          String.contains?(content_type, "json") ->
            check_json_response(body)

          # Try to detect JSON even without proper content-type
          is_binary(body) and String.starts_with?(String.trim(body), ["{", "["]) ->
            case check_json_response(body) do
              {:ok, method} ->
                {:ok, method}

              {:error, :invalid_json} ->
                # Not actually JSON, treat as HTML
                handle_html_response(body, url)
            end

          # Handle HTML/text responses
          true ->
            handle_html_response(body, url)
        end

      {:ok, %{status: status}} when status in [301, 302, 303] ->
        # Redirect might mean success
        {:ok, "redirect"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_html_response(body, url) do
    if one_click_unsubscribe?(body) do
      {:ok, "one_click"}
    else
      # Try to analyze the page with AI
      attempt_form_unsubscribe(url, body)
    end
  end

  defp get_content_type(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
    |> case do
      {_, value} when is_binary(value) -> String.downcase(value)
      {_, [value | _]} when is_binary(value) -> String.downcase(value)
      {_, value} when is_list(value) -> ""
      nil -> ""
    end
  end

  defp check_json_response(body) do
    case Jason.decode(body) do
      {:ok, json} when is_map(json) ->
        # Check for common success indicators in JSON
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
          # Even if we can't confirm, visiting the URL might have worked
          Logger.info("JSON response received but success unclear: #{inspect(json)}")
          {:ok, "api_json_uncertain"}
        end

      {:error, _} ->
        # Not valid JSON, might be plain text or HTML
        {:error, :invalid_json}
    end
  end

  defp one_click_unsubscribe?(body) when is_binary(body) do
    # Check for success indicators in HTML/text
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

  defp one_click_unsubscribe?(_), do: false

  defp attempt_form_unsubscribe(url, html_body) do
    case AIService.analyze_unsubscribe_page(html_body) do
      {:ok, %{"method" => "form_submit", "form_data" => form_data}} when is_map(form_data) ->
        # Try to submit the form
        Logger.info("Attempting form submission with data: #{inspect(form_data)}")

        case Req.post(url, form: form_data) do
          {:ok, %{status: status, body: response_body}} when status in 200..299 ->
            Logger.info("Form submitted successfully, status: #{status}")

            # Check if the response indicates success
            if one_click_unsubscribe?(response_body) do
              {:ok, "form_submit_confirmed"}
            else
              {:ok, "form_submit"}
            end

          {:ok, %{status: status}} ->
            Logger.warning("Form submission returned status: #{status}")
            {:error, :form_submit_failed}

          {:error, error} ->
            Logger.error("Form submission error: #{inspect(error)}")
            {:error, :form_submit_failed}
        end

      {:ok, %{"method" => "button_click"}} ->
        # Can't actually click buttons without a browser
        Logger.info("Page requires button click - cannot automate without browser")
        {:error, :requires_browser}

      {:ok, %{"method" => "unknown", "reason" => reason}} ->
        Logger.info("AI could not determine unsubscribe method: #{reason}")
        {:error, :method_unknown}

      {:ok, unexpected} ->
        Logger.warning("Unexpected AI response format: #{inspect(unexpected)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.error("AI analysis failed: #{inspect(reason)}")
        {:error, :analysis_failed}
    end
  end
end
