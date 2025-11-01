defmodule JumpappEmailSorter.Workers.EmailImportWorker do
  @moduledoc """
  Worker that imports emails from a specific Gmail account.
  """

  use Oban.Worker, queue: :email_import, max_attempts: 3

  require Logger

  alias JumpappEmailSorter.{Accounts, Categories, Emails, GmailClient, AIService, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gmail_account_id" => gmail_account_id}}) do
    Logger.info("Importing emails for account #{gmail_account_id}")

    gmail_account = Accounts.get_gmail_account!(gmail_account_id)
    user_id = gmail_account.user_id

    # Get user's categories
    categories = Categories.list_categories(user_id)

    # List unread messages
    case GmailClient.list_messages(gmail_account.access_token, query: "is:unread") do
      {:ok, %{"messages" => messages}} when is_list(messages) ->
        Logger.info("Found #{length(messages)} unread messages")

        Enum.each(messages, fn %{"id" => message_id} ->
          import_single_email(gmail_account, message_id, categories)
        end)

        :ok

      {:ok, %{}} ->
        Logger.info("No unread messages found")
        :ok

      {:error, :unauthorized} ->
        Logger.error("Unauthorized - token may be expired")
        {:error, :unauthorized}

      {:error, error} ->
        Logger.error("Failed to list messages: #{inspect(error)}")
        {:error, error}
    end
  end

  defp import_single_email(gmail_account, message_id, categories) do
    # Check if we already imported this email
    if Emails.get_email_by_gmail_id(gmail_account.id, message_id) do
      Logger.debug("Email #{message_id} already imported, skipping")
      :ok
    else
      case GmailClient.get_message(gmail_account.access_token, message_id) do
        {:ok, message} ->
          process_and_save_email(gmail_account, message, categories)

        {:error, error} ->
          Logger.error("Failed to get message #{message_id}: #{inspect(error)}")
          :error
      end
    end
  end

  defp process_and_save_email(gmail_account, message, categories) do
    # Prepare email content for AI
    email_content = """
    Subject: #{message.subject}
    From: #{message.from.name} <#{message.from.email}>
    Body: #{message.body}
    """

    # Categorize with AI
    {:ok, category_id} = AIService.categorize_email(email_content, categories)

    # Summarize with AI
    {:ok, summary} = AIService.summarize_email(email_content)

    # Extract unsubscribe link
    unsubscribe_link = extract_unsubscribe_link(message.body, message.list_unsubscribe)

    # Parse date
    received_at = parse_date(message.date)

    # Save to database
    email_attrs = %{
      gmail_account_id: gmail_account.id,
      category_id: category_id,
      gmail_message_id: message.id,
      thread_id: message.thread_id,
      subject: message.subject,
      from_email: message.from.email,
      from_name: message.from.name,
      received_at: received_at,
      summary: summary,
      body_preview: String.slice(message.body, 0, 500),
      body_text: message.body,
      list_unsubscribe_header: message.list_unsubscribe,
      unsubscribe_link: unsubscribe_link
    }

    case Emails.create_email(email_attrs) do
      {:ok, _email} ->
        # Archive the email in Gmail
        case GmailClient.archive_message(gmail_account.access_token, message.id) do
          :ok ->
            Logger.info("Successfully imported and archived email #{message.id}")
            :ok

          {:error, error} ->
            Logger.error("Failed to archive email #{message.id}: #{inspect(error)}")
            :ok  # Still consider import successful
        end

      {:error, changeset} ->
        Logger.error("Failed to save email #{message.id}: #{inspect(changeset.errors)}")
        :error
    end
  end

  defp extract_unsubscribe_link(body, list_unsubscribe_header) do
    # Try header first
    cond do
      list_unsubscribe_header && String.contains?(list_unsubscribe_header, "http") ->
        extract_url_from_header(list_unsubscribe_header)

      true ->
        # Try to find unsubscribe link in body
        extract_url_from_body(body)
    end
  end

  defp extract_url_from_header(header) do
    case Regex.run(~r/<(https?:\/\/[^>]+)>/, header) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp extract_url_from_body(body) do
    # Look for common unsubscribe patterns
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

  defp parse_date(date_string) when is_binary(date_string) do
    # Try to parse the date, fallback to current time if it fails
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_date(_), do: DateTime.utc_now()
end

