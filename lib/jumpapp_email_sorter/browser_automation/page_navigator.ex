defmodule JumpappEmailSorter.BrowserAutomation.PageNavigator do
  @moduledoc """
  Handles navigation and page interactions for the AI agent.
  """

  require Logger
  import Wallaby.Browser
  alias Wallaby.Query

  @default_timeout 30_000

  @doc """
  Navigates to a URL and waits for the page to load.
  """
  def navigate_to(session, url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      session = visit(session, url)
      Logger.info("Navigated to: #{url}")

      # Wait for page to be ready
      wait_for_page_load(session, timeout)

      {:ok, session}
    rescue
      error ->
        Logger.error("Navigation failed for #{url}: #{inspect(error)}")
        {:error, :navigation_failed}
    end
  end

  @doc """
  Gets the current page HTML source.
  """
  def get_page_source(session) do
    try do
      html = page_source(session)
      {:ok, html}
    rescue
      error ->
        Logger.error("Failed to get page source: #{inspect(error)}")
        {:error, :page_source_failed}
    end
  end

  @doc """
  Gets the current page URL.
  """
  def get_current_url(session) do
    try do
      url = current_url(session)
      {:ok, url}
    rescue
      error ->
        Logger.error("Failed to get current URL: #{inspect(error)}")
        {:error, :url_failed}
    end
  end

  @doc """
  Waits for the page to be fully loaded.
  """
  def wait_for_page_load(session, timeout \\ @default_timeout) do
    try do
      # Wait for document.readyState to be complete
      execute_script(session, """
        return new Promise((resolve) => {
          if (document.readyState === 'complete') {
            resolve(true);
          } else {
            window.addEventListener('load', () => resolve(true));
          }
        });
      """)

      # Small additional wait for any dynamic content
      Process.sleep(500)

      {:ok, session}
    rescue
      error ->
        Logger.warning("Page load wait failed: #{inspect(error)}")
        {:ok, session}
    catch
      :exit, _ ->
        Logger.warning("Page load timeout after #{timeout}ms")
        {:ok, session}
    end
  end

  @doc """
  Checks if an element exists on the page.
  """
  def element_exists?(session, selector) do
    try do
      has_css?(session, selector)
    rescue
      _ -> false
    end
  end

  @doc """
  Waits for an element to appear on the page.
  """
  def wait_for_element(session, selector, timeout \\ 5000) do
    try do
      session
      |> find(Query.css(selector, count: 1, timeout: timeout))

      {:ok, session}
    rescue
      error ->
        Logger.warning("Element not found: #{selector} - #{inspect(error)}")
        {:error, :element_not_found}
    end
  end

  @doc """
  Gets visible text from the page.
  """
  def get_page_text(session) do
    try do
      text = text(session, Query.css("body"))
      {:ok, text}
    rescue
      error ->
        Logger.error("Failed to get page text: #{inspect(error)}")
        {:error, :text_failed}
    end
  end

  @doc """
  Checks if the page contains success indicators for unsubscribe.
  """
  def check_for_success_message(session) do
    success_patterns = [
      ~r/unsubscribed/i,
      ~r/successfully removed/i,
      ~r/will no longer receive/i,
      ~r/preference.*updated/i,
      ~r/you have been removed/i,
      ~r/email.*removed/i
    ]

    case get_page_text(session) do
      {:ok, text} ->
        success? =
          Enum.any?(success_patterns, fn pattern ->
            Regex.match?(pattern, text)
          end)

        if success? do
          Logger.info("Success message detected on page")
          {:ok, true}
        else
          {:ok, false}
        end

      {:error, _} ->
        {:ok, false}
    end
  end
end

