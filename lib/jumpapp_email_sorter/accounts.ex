defmodule JumpappEmailSorter.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias JumpappEmailSorter.Repo

  alias JumpappEmailSorter.Accounts.{User, GmailAccount}

  @doc """
  Gets a single user by ID.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by Google ID.
  """
  def get_user_by_google_id(google_id) when is_binary(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Creates or updates a user from OAuth data.
  """
  def upsert_user_from_oauth(oauth_data) do
    case get_user_by_google_id(oauth_data.google_id) do
      nil ->
        %User{}
        |> User.changeset(oauth_data)
        |> Repo.insert()

      user ->
        user
        |> User.changeset(oauth_data)
        |> Repo.update()
    end
  end

  @doc """
  Updates user tokens.
  """
  def update_user_tokens(user, token_attrs) do
    user
    |> User.token_changeset(token_attrs)
    |> Repo.update()
  end

  @doc """
  Lists all gmail accounts for a user.
  """
  def list_gmail_accounts(user_id) do
    GmailAccount
    |> where([g], g.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Gets a single gmail account.
  """
  def get_gmail_account!(id), do: Repo.get!(GmailAccount, id)

  @doc """
  Gets a gmail account by user_id and email.
  """
  def get_gmail_account_by_email(user_id, email) do
    Repo.get_by(GmailAccount, user_id: user_id, email: email)
  end

  @doc """
  Creates a gmail account.
  """
  def create_gmail_account(user, attrs \\ %{}) do
    %GmailAccount{}
    |> GmailAccount.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates a gmail account.
  """
  def update_gmail_account(%GmailAccount{} = gmail_account, attrs) do
    gmail_account
    |> GmailAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates gmail account tokens.
  """
  def update_gmail_account_tokens(%GmailAccount{} = gmail_account, token_attrs) do
    gmail_account
    |> GmailAccount.token_changeset(token_attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a gmail account.
  """
  def delete_gmail_account(%GmailAccount{} = gmail_account) do
    Repo.delete(gmail_account)
  end

  @doc """
  Checks if a token is expired or about to expire (within 5 minutes).
  """
  def token_expired?(nil), do: true

  def token_expired?(expires_at) do
    DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), 300, :second)) == :lt
  end
end

