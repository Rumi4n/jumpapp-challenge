defmodule JumpappEmailSorter.BrowserAutomation.FormInteractor do
  @moduledoc """
  Handles form interactions for the AI agent - filling fields, clicking buttons, etc.
  """

  require Logger
  import Wallaby.Browser
  alias Wallaby.Query

  @doc """
  Fills a form field with a value using various strategies.
  """
  def fill_field(session, selector, value) do
    try do
      Logger.debug("Filling field #{selector} with value: #{value}")

      session =
        session
        |> fill_in(Query.css(selector), with: value)

      {:ok, session}
    rescue
      error ->
        Logger.warning("Failed to fill field #{selector}: #{inspect(error)}")
        # Try alternative strategies
        try_alternative_fill_strategies(session, selector, value)
    end
  end

  defp try_alternative_fill_strategies(session, selector, value) do
    strategies = [
      fn s -> fill_by_name(s, selector, value) end,
      fn s -> fill_by_id(s, selector, value) end,
      fn s -> fill_by_placeholder(s, selector, value) end
    ]

    Enum.reduce_while(strategies, {:error, :fill_failed}, fn strategy, _acc ->
      case try_strategy(strategy, session) do
        {:ok, session} -> {:halt, {:ok, session}}
        {:error, _} -> {:cont, {:error, :fill_failed}}
      end
    end)
  end

  defp try_strategy(strategy, session) do
    try do
      strategy.(session)
    rescue
      _ -> {:error, :strategy_failed}
    end
  end

  defp fill_by_name(session, name, value) do
    session = fill_in(session, Query.css("[name='#{name}']"), with: value)
    {:ok, session}
  end

  defp fill_by_id(session, id, value) do
    clean_id = String.replace(id, "#", "")
    session = fill_in(session, Query.css("##{clean_id}"), with: value)
    {:ok, session}
  end

  defp fill_by_placeholder(session, placeholder, value) do
    session = fill_in(session, Query.css("[placeholder='#{placeholder}']"), with: value)
    {:ok, session}
  end

  @doc """
  Selects an option from a dropdown.
  """
  def select_option(session, selector, option_value) do
    try do
      Logger.debug("Selecting option #{option_value} in #{selector}")

      # Use JavaScript to select the option
      execute_script(session, """
        var select = document.querySelector('#{selector}');
        if (select) {
          select.value = '#{option_value}';
          select.dispatchEvent(new Event('change', { bubbles: true }));
        }
      """)

      {:ok, session}
    rescue
      error ->
        Logger.warning("Failed to select option in #{selector}: #{inspect(error)}")
        {:error, :select_failed}
    end
  end

  @doc """
  Checks or unchecks a checkbox.
  """
  def toggle_checkbox(session, selector, checked \\ true) do
    try do
      Logger.debug("Setting checkbox #{selector} to #{checked}")

      # Use JavaScript to toggle checkbox
      execute_script(session, """
        var checkbox = document.querySelector('#{selector}');
        if (checkbox) {
          checkbox.checked = #{checked};
          checkbox.dispatchEvent(new Event('change', { bubbles: true }));
        }
      """)

      {:ok, session}
    rescue
      error ->
        Logger.warning("Failed to toggle checkbox #{selector}: #{inspect(error)}")
        {:error, :checkbox_failed}
    end
  end

  @doc """
  Clicks a button or link.
  """
  def click_element(session, selector) do
    try do
      Logger.debug("Clicking element: #{selector}")

      session =
        session
        |> click(Query.css(selector))

      # Wait a bit for any page changes
      Process.sleep(1000)

      {:ok, session}
    rescue
      error ->
        Logger.warning("Failed to click #{selector}: #{inspect(error)}")
        try_alternative_click_strategies(session, selector)
    end
  end

  defp try_alternative_click_strategies(session, selector) do
    # Try clicking by text if selector doesn't work
    try do
      session =
        session
        |> click(Query.link(selector))

      {:ok, session}
    rescue
      _ ->
        # Try JavaScript click as last resort
        try_javascript_click(session, selector)
    end
  end

  defp try_javascript_click(session, selector) do
    try do
      execute_script(session, """
        document.querySelector('#{selector}').click();
      """)

      Process.sleep(1000)
      {:ok, session}
    rescue
      error ->
        Logger.error("All click strategies failed for #{selector}: #{inspect(error)}")
        {:error, :click_failed}
    end
  end

  @doc """
  Submits a form.
  """
  def submit_form(session, form_selector \\ "form") do
    try do
      Logger.debug("Submitting form: #{form_selector}")

      # Try to find and click submit button first
      case click_submit_button(session, form_selector) do
        {:ok, session} ->
          {:ok, session}

        {:error, _} ->
          # Fall back to JavaScript form submission
          execute_script(session, """
            document.querySelector('#{form_selector}').submit();
          """)

          Process.sleep(2000)
          {:ok, session}
      end
    rescue
      error ->
        Logger.error("Failed to submit form: #{inspect(error)}")
        {:error, :submit_failed}
    end
  end

  defp click_submit_button(session, form_selector) do
    submit_selectors = [
      "#{form_selector} button[type='submit']",
      "#{form_selector} input[type='submit']",
      "#{form_selector} button:not([type='button'])"
    ]

    Enum.reduce_while(submit_selectors, {:error, :no_submit_button}, fn selector, _acc ->
      try do
        session = click(session, Query.css(selector))
        Process.sleep(1000)
        {:halt, {:ok, session}}
      rescue
        _ -> {:cont, {:error, :no_submit_button}}
      end
    end)
  end

  @doc """
  Fills multiple form fields based on a map of selector => value.
  """
  def fill_form(session, field_map) when is_map(field_map) do
    Enum.reduce_while(field_map, {:ok, session}, fn {selector, value}, {:ok, sess} ->
      case fill_field(sess, selector, value) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Executes a series of form actions based on AI instructions.
  """
  def execute_instructions(session, instructions) when is_map(instructions) do
    with {:ok, session} <- fill_form_fields(session, instructions["fields"] || []),
         {:ok, session} <- select_dropdowns(session, instructions["selects"] || []),
         {:ok, session} <- toggle_checkboxes(session, instructions["checkboxes"] || []) do
      {:ok, session}
    end
  end

  defp fill_form_fields(session, fields) when is_list(fields) do
    Enum.reduce_while(fields, {:ok, session}, fn field, {:ok, sess} ->
      selector = field["selector"]
      value = field["value"]

      case fill_field(sess, selector, value) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp select_dropdowns(session, selects) when is_list(selects) do
    Enum.reduce_while(selects, {:ok, session}, fn select, {:ok, sess} ->
      selector = select["selector"]
      value = select["value"]

      case select_option(sess, selector, value) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp toggle_checkboxes(session, checkboxes) when is_list(checkboxes) do
    Enum.reduce_while(checkboxes, {:ok, session}, fn checkbox, {:ok, sess} ->
      selector = checkbox["selector"]
      checked = checkbox["checked"]

      case toggle_checkbox(sess, selector, checked) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end

