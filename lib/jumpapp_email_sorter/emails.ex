defmodule JumpappEmailSorter.Emails do
  @moduledoc """
  The Emails context.
  """

  import Ecto.Query, warn: false
  alias JumpappEmailSorter.Repo

  alias JumpappEmailSorter.Emails.{Email, UnsubscribeAttempt}
  alias JumpappEmailSorter.{Accounts, GmailClient}

  require Logger

  @doc """
  Returns the list of emails for a category.
  """
  def list_emails_by_category(category_id) do
    Email
    |> where([e], e.category_id == ^category_id)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of emails for a gmail account.
  """
  def list_emails_by_account(gmail_account_id) do
    Email
    |> where([e], e.gmail_account_id == ^gmail_account_id)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  @doc """
  Gets a single email.
  """
  def get_email!(id), do: Repo.get!(Email, id)

  @doc """
  Gets an email by gmail_message_id and gmail_account_id.
  """
  def get_email_by_gmail_id(gmail_account_id, gmail_message_id) do
    Repo.get_by(Email, gmail_account_id: gmail_account_id, gmail_message_id: gmail_message_id)
  end

  @doc """
  Creates an email.
  """
  def create_email(attrs \\ %{}) do
    %Email{}
    |> Email.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an email.
  """
  def update_email(%Email{} = email, attrs) do
    email
    |> Email.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an email.
  """
  def delete_email(%Email{} = email) do
    Repo.delete(email)
  end

  @doc """
  Deletes multiple emails by IDs.
  Also deletes them from Gmail.
  """
  def delete_emails(email_ids) when is_list(email_ids) do
    # Fetch emails with their Gmail account information
    emails =
      Email
      |> where([e], e.id in ^email_ids)
      |> preload(:gmail_account)
      |> Repo.all()

    # Delete from Gmail first
    Enum.each(emails, fn email ->
      delete_email_from_gmail(email)
    end)

    # Then delete from database
    Email
    |> where([e], e.id in ^email_ids)
    |> Repo.delete_all()
  end

  # Private helper to delete email from Gmail (moves to trash)
  defp delete_email_from_gmail(%Email{} = email) do
    gmail_account = email.gmail_account

    # Ensure we have a valid access token
    gmail_account =
      case Accounts.ensure_valid_token(gmail_account) do
        {:ok, updated_account} -> updated_account
        {:error, _} -> gmail_account
      end

    case GmailClient.trash_message(gmail_account.access_token, email.gmail_message_id) do
      :ok ->
        Logger.info(
          "✓ Successfully moved email #{email.gmail_message_id} to trash in Gmail account #{gmail_account.email}"
        )

        :ok

      {:error, :unauthorized} ->
        Logger.error(
          "✗ Unauthorized when trashing email #{email.gmail_message_id} from #{gmail_account.email}"
        )

        :error

      {:error, error} ->
        Logger.error(
          "✗ Failed to trash email #{email.gmail_message_id} in Gmail: #{inspect(error)}"
        )

        :error
    end
  end

  @doc """
  Creates an unsubscribe attempt.
  """
  def create_unsubscribe_attempt(email_id, attrs \\ %{}) do
    %UnsubscribeAttempt{email_id: email_id}
    |> UnsubscribeAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an unsubscribe attempt.
  """
  def update_unsubscribe_attempt(%UnsubscribeAttempt{} = attempt, attrs) do
    attempt
    |> UnsubscribeAttempt.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets the latest unsubscribe attempt for an email.
  """
  def get_latest_unsubscribe_attempt(email_id) do
    UnsubscribeAttempt
    |> where([u], u.email_id == ^email_id)
    |> order_by([u], desc: u.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
