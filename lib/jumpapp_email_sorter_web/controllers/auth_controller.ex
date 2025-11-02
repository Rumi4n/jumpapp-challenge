defmodule JumpappEmailSorterWeb.AuthController do
  use JumpappEmailSorterWeb, :controller
  plug Ueberauth

  alias JumpappEmailSorter.Accounts

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with Google.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    gmail_account_params = %{
      email: auth.info.email,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      token_expires_at: DateTime.from_unix!(auth.credentials.expires_at)
    }

    # Check if user is already logged in (adding additional account)
    case get_session(conn, :user_id) do
      nil ->
        # Initial login - create/update user and set session
        handle_initial_login(conn, auth, gmail_account_params)

      user_id ->
        # User already logged in - just add the gmail account to existing user
        handle_add_account(conn, user_id, gmail_account_params)
    end
  end

  defp handle_initial_login(conn, auth, gmail_account_params) do
    user_params = %{
      email: auth.info.email,
      google_id: auth.uid,
      name: auth.info.name,
      picture: auth.info.image,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      token_expires_at: DateTime.from_unix!(auth.credentials.expires_at)
    }

    case Accounts.upsert_user_from_oauth(user_params) do
      {:ok, user} ->
        # Also create/update the gmail account
        case Accounts.upsert_gmail_account_from_oauth(user, gmail_account_params) do
          {:ok, _gmail_account} ->
            conn
            |> put_session(:user_id, user.id)
            |> put_flash(:info, "Successfully authenticated!")
            |> redirect(to: ~p"/dashboard")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to connect Gmail account.")
            |> redirect(to: ~p"/")
        end

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create or update user.")
        |> redirect(to: ~p"/")
    end
  end

  defp handle_add_account(conn, user_id, gmail_account_params) do
    user = Accounts.get_user!(user_id)

    case Accounts.upsert_gmail_account_from_oauth(user, gmail_account_params) do
      {:ok, _gmail_account} ->
        conn
        |> put_flash(:info, "Gmail account added successfully!")
        |> redirect(to: ~p"/dashboard")

      {:error, changeset} ->
        error_msg =
          if changeset.errors[:email] do
            "This Gmail account is already connected."
          else
            "Failed to add Gmail account."
          end

        conn
        |> put_flash(:error, error_msg)
        |> redirect(to: ~p"/dashboard")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Successfully signed out!")
    |> redirect(to: ~p"/")
  end
end
