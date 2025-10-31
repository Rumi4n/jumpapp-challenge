defmodule JumpappEmailSorterWeb.UserAuth do
  @moduledoc """
  Authentication plugs and helpers.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias JumpappEmailSorter.Accounts

  @doc """
  Fetches the current user from the session.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user!(user_id)
    assign(conn, :current_user, user)
  end

  @doc """
  Requires that a user is authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must sign in to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end

  @doc """
  Used for LiveView mounting.
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must sign in to access this page.")
        |> Phoenix.LiveView.redirect(to: "/")

      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_id = session["user_id"] do
        Accounts.get_user!(user_id)
      end
    end)
  end
end

