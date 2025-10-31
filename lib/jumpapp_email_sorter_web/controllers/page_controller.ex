defmodule JumpappEmailSorterWeb.PageController do
  use JumpappEmailSorterWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
