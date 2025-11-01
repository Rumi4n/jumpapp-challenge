defmodule JumpappEmailSorter.Workers.GmailPollWorker do
  @moduledoc """
  Scheduled worker that polls Gmail for new emails across all connected accounts.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias JumpappEmailSorter.{Accounts, Repo}
  alias JumpappEmailSorter.Workers.EmailImportWorker

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Starting Gmail poll for all accounts")

    # Get all gmail accounts
    gmail_accounts = Repo.all(JumpappEmailSorter.Accounts.GmailAccount)

    Enum.each(gmail_accounts, fn account ->
      # Check if token needs refresh
      account = maybe_refresh_token(account)

      # Queue email import job for this account
      %{gmail_account_id: account.id}
      |> EmailImportWorker.new()
      |> Oban.insert()
    end)

    Logger.info("Queued email import for #{length(gmail_accounts)} accounts")

    :ok
  end

  defp maybe_refresh_token(account) do
    if Accounts.token_expired?(account.token_expires_at) do
      Logger.info("Refreshing token for account #{account.id}")

      case JumpappEmailSorter.GmailClient.refresh_access_token(account.refresh_token) do
        {:ok, %{access_token: new_token, expires_at: expires_at}} ->
          {:ok, account} =
            Accounts.update_gmail_account_tokens(account, %{
              access_token: new_token,
              token_expires_at: expires_at
            })

          account

        {:error, error} ->
          Logger.error("Failed to refresh token for account #{account.id}: #{inspect(error)}")
          account
      end
    else
      account
    end
  end
end

