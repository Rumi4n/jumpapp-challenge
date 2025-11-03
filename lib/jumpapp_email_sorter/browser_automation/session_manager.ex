defmodule JumpappEmailSorter.BrowserAutomation.SessionManager do
  @moduledoc """
  Manages browser session lifecycle for the AI agent.
  Handles starting, stopping, and cleaning up browser sessions.
  """

  require Logger

  @doc """
  Starts a new browser session with configured options.
  Returns {:ok, session} or {:error, reason}.
  """
  def start_session do
    try do
      {:ok, session} = Wallaby.start_session()
      Logger.info("Browser session started: #{inspect(session.id)}")
      {:ok, session}
    rescue
      error ->
        Logger.error("Failed to start browser session: #{inspect(error)}")
        {:error, :session_start_failed}
    end
  end

  @doc """
  Ends a browser session and cleans up resources.
  """
  def end_session(session) do
    try do
      Wallaby.end_session(session)
      Logger.info("Browser session ended: #{inspect(session.id)}")
      :ok
    rescue
      error ->
        Logger.warning("Error ending browser session: #{inspect(error)}")
        :ok
    end
  end

  @doc """
  Executes a function with a browser session, ensuring cleanup.
  """
  def with_session(fun) when is_function(fun, 1) do
    case start_session() do
      {:ok, session} ->
        try do
          result = fun.(session)
          {:ok, result}
        rescue
          error ->
            Logger.error("Error in browser session: #{inspect(error)}")
            {:error, error}
        after
          end_session(session)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Takes a screenshot of the current page for debugging.
  Returns the screenshot path or nil if failed.
  """
  def take_screenshot(session, name \\ "debug") do
    try do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      filename = "#{name}_#{timestamp}.png"
      path = Path.join(["screenshots", filename])

      # Ensure screenshots directory exists
      File.mkdir_p!("screenshots")

      Wallaby.Browser.take_screenshot(session, name: filename)
      Logger.info("Screenshot saved: #{path}")
      {:ok, path}
    rescue
      error ->
        Logger.warning("Failed to take screenshot: #{inspect(error)}")
        {:error, :screenshot_failed}
    end
  end
end

