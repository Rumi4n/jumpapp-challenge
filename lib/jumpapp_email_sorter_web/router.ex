defmodule JumpappEmailSorterWeb.Router do
  use JumpappEmailSorterWeb, :router

  import JumpappEmailSorterWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JumpappEmailSorterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_authenticated_user do
    plug :require_authenticated_user
  end

  scope "/", JumpappEmailSorterWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/auth", JumpappEmailSorterWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :delete
  end

  scope "/", JumpappEmailSorterWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/dashboard", DashboardLive
    live "/categories/:id", CategoryLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", JumpappEmailSorterWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jumpapp_email_sorter, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JumpappEmailSorterWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
