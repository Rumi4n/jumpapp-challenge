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
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated!")
        |> redirect(to: ~p"/dashboard")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create or update user.")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Successfully signed out!")
    |> redirect(to: ~p"/")
  end
end

