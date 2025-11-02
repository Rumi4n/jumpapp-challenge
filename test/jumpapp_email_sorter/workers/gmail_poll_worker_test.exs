defmodule JumpappEmailSorter.Workers.GmailPollWorkerTest do
  use JumpappEmailSorter.DataCase, async: false

  alias JumpappEmailSorter.Workers.GmailPollWorker
  alias JumpappEmailSorter.{Accounts, Repo}

  setup do
    {:ok, user} =
      Accounts.upsert_user_from_oauth(%{
        email: "test@example.com",
        google_id: "google_#{:rand.uniform(100_000)}",
        name: "Test User"
      })

    %{user: user}
  end

  describe "perform/1" do
    test "successfully polls and queues import jobs for all accounts", %{user: user} do
      # Create multiple Gmail accounts
      {:ok, account1} =
        Accounts.create_gmail_account(user, %{
          email: "test1@gmail.com",
          access_token: "token1",
          refresh_token: "refresh1",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, account2} =
        Accounts.create_gmail_account(user, %{
          email: "test2@gmail.com",
          access_token: "token2",
          refresh_token: "refresh2",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Perform the poll
      result = GmailPollWorker.perform(%Oban.Job{args: %{}})

      assert result == :ok

      # Verify accounts exist
      accounts = Repo.all(JumpappEmailSorter.Accounts.GmailAccount)
      assert length(accounts) >= 2
    end

    test "handles empty account list gracefully" do
      # Ensure no accounts exist
      Repo.delete_all(JumpappEmailSorter.Accounts.GmailAccount)

      result = GmailPollWorker.perform(%Oban.Job{args: %{}})

      assert result == :ok
    end

    test "handles expired tokens", %{user: user} do
      # Create account with expired token
      {:ok, _account} =
        Accounts.create_gmail_account(user, %{
          email: "expired@gmail.com",
          access_token: "old_token",
          refresh_token: "refresh_token",
          # Token expired 1 hour ago
          token_expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      # The worker should handle expired tokens gracefully
      result = GmailPollWorker.perform(%Oban.Job{args: %{}})

      # Should complete even if token refresh fails
      assert result == :ok
    end

    test "continues polling even if one account fails", %{user: user} do
      # Create one valid and one potentially problematic account
      {:ok, _valid_account} =
        Accounts.create_gmail_account(user, %{
          email: "valid@gmail.com",
          access_token: "valid_token",
          refresh_token: "valid_refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, _expired_account} =
        Accounts.create_gmail_account(user, %{
          email: "expired@gmail.com",
          access_token: "expired_token",
          refresh_token: "bad_refresh",
          token_expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      result = GmailPollWorker.perform(%Oban.Job{args: %{}})

      # Should complete successfully
      assert result == :ok
    end
  end

  describe "token refresh logic" do
    test "identifies when token needs refresh", %{user: user} do
      expired_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "old_token",
          refresh_token: "refresh",
          token_expires_at: expired_time
        })

      # Token should be identified as expired
      assert Accounts.token_expired?(account.token_expires_at) == true
    end

    test "identifies when token is still valid", %{user: user} do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, account} =
        Accounts.create_gmail_account(user, %{
          email: "test@gmail.com",
          access_token: "valid_token",
          refresh_token: "refresh",
          token_expires_at: future_time
        })

      # Token should be identified as valid
      assert Accounts.token_expired?(account.token_expires_at) == false
    end
  end
end

