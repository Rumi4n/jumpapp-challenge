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
      {:ok, attempt} = Emails.create_unsubscribe_attempt(email_id, %{
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
      {:ok, %{status: 200, body: body}} ->
        # Check if it's a one-click unsubscribe (just visiting the URL works)
        if one_click_unsubscribe?(body) do
          {:ok, "one_click"}
        else
          # Try to analyze the page with AI
          attempt_form_unsubscribe(url, body)
        end

      {:ok, %{status: status}} when status in [301, 302, 303] ->
        # Redirect might mean success
        {:ok, "redirect"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp one_click_unsubscribe?(body) do
    # Check for success indicators
    success_patterns = [
      ~r/unsubscribed/i,
      ~r/successfully removed/i,
      ~r/will no longer receive/i,
      ~r/preference.*updated/i
    ]

    Enum.any?(success_patterns, fn pattern ->
      Regex.match?(pattern, body)
    end)
  end

  defp attempt_form_unsubscribe(url, html_body) do
    case AIService.analyze_unsubscribe_page(html_body) do
      {:ok, %{"method" => "form_submit", "form_data" => form_data}} ->
        # Try to submit the form
        case Req.post(url, form: form_data) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, "form_submit"}

          _ ->
            {:error, :form_submit_failed}
        end

      {:ok, %{"method" => "button_click"}} ->
        # Can't actually click buttons without a browser
        {:error, :requires_browser}

      {:error, _} ->
        {:error, :analysis_failed}
    end
  end
end

