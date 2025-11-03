defmodule JumpappEmailSorter.Workers.UnsubscribeWorker do
  @moduledoc """
  Worker that attempts to unsubscribe from emails.
  """

  use Oban.Worker, queue: :unsubscribe, max_attempts: 2

  require Logger

  alias JumpappEmailSorter.{Emails, AIService, FormAnalyzer}

  alias JumpappEmailSorter.BrowserAutomation.{
    SessionManager,
    PageNavigator,
    FormInteractor
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    Logger.info("Processing unsubscribe for email #{email_id}")

    email = Emails.get_email!(email_id)

    if !email.unsubscribe_link do
      Logger.warning("No unsubscribe link found for email #{email_id}")
      {:error, :no_unsubscribe_link}
    else
      # Create unsubscribe attempt record
      {:ok, attempt} =
        Emails.create_unsubscribe_attempt(email_id, %{
          unsubscribe_url: email.unsubscribe_link,
          status: "processing",
          attempted_at: DateTime.utc_now()
        })

      # Try to unsubscribe
      result = attempt_unsubscribe(email.unsubscribe_link)

      # Update attempt with result
      case result do
        {:ok, method} ->
          Emails.update_unsubscribe_attempt(attempt, %{
            status: "success",
            method: method,
            completed_at: DateTime.utc_now()
          })

          Logger.info("Successfully unsubscribed from email #{email_id}")
          :ok

        {:error, reason} ->
          Emails.update_unsubscribe_attempt(attempt, %{
            status: "failed",
            error_message: inspect(reason),
            completed_at: DateTime.utc_now()
          })

          Logger.error("Failed to unsubscribe from email #{email_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp attempt_unsubscribe(url) do
    # First, try to fetch the page
    case Req.get(url, redirect: true) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type = get_content_type(headers)

        cond do
          # Handle JSON API responses (by content-type header)
          String.contains?(content_type, "json") ->
            check_json_response(body)

          # Try to detect JSON even without proper content-type
          is_binary(body) and String.starts_with?(String.trim(body), ["{", "["]) ->
            case check_json_response(body) do
              {:ok, method} ->
                {:ok, method}

              {:error, :invalid_json} ->
                # Not actually JSON, treat as HTML
                handle_html_response(body, url)
            end

          # Handle HTML/text responses
          true ->
            handle_html_response(body, url)
        end

      {:ok, %{status: status}} when status in [301, 302, 303] ->
        # Redirect might mean success
        {:ok, "redirect"}

      {:ok, %{status: status}} when status >= 500 ->
        # Server error - cannot complete unsubscribe
        Logger.warning("Server error (#{status}) when accessing unsubscribe URL: #{url}")
        {:error, :server_error}

      {:ok, %{status: status}} when status >= 400 ->
        # Client error
        Logger.warning("Client error (#{status}) when accessing unsubscribe URL: #{url}")
        {:error, :client_error}

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_html_response(body, url) do
    if one_click_unsubscribe?(body) do
      {:ok, "one_click"}
    else
      # Try browser automation with AI agent (NEW!)
      case attempt_browser_automation(url, body) do
        {:ok, method} ->
          {:ok, method}

        {:error, _reason} ->
          # Fall back to simple form POST attempt
          attempt_form_unsubscribe(url, body)
      end
    end
  end

  defp get_content_type(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
    |> case do
      {_, value} when is_binary(value) -> String.downcase(value)
      {_, [value | _]} when is_binary(value) -> String.downcase(value)
      {_, value} when is_list(value) -> ""
      nil -> ""
    end
  end

  defp check_json_response(body) do
    case Jason.decode(body) do
      {:ok, json} when is_map(json) ->
        # Check for common success indicators in JSON
        success_keys = ["success", "status", "result", "message", "unsubscribed"]

        success? =
          Enum.any?(success_keys, fn key ->
            case Map.get(json, key) do
              true -> true
              "success" -> true
              "ok" -> true
              "unsubscribed" -> true
              val when is_binary(val) -> String.match?(val, ~r/(success|unsubscribe|removed)/i)
              _ -> false
            end
          end)

        if success? do
          {:ok, "api_json"}
        else
          # Even if we can't confirm, visiting the URL might have worked
          Logger.info("JSON response received but success unclear: #{inspect(json)}")
          {:ok, "api_json_uncertain"}
        end

      {:error, _} ->
        # Not valid JSON, might be plain text or HTML
        {:error, :invalid_json}
    end
  end

  defp one_click_unsubscribe?(body) when is_binary(body) do
    # Check for success indicators in HTML/text
    success_patterns = [
      ~r/unsubscribed/i,
      ~r/successfully removed/i,
      ~r/will no longer receive/i,
      ~r/preference.*updated/i,
      ~r/you have been removed/i,
      ~r/email.*removed/i
    ]

    Enum.any?(success_patterns, fn pattern ->
      Regex.match?(pattern, body)
    end)
  end

  defp one_click_unsubscribe?(_), do: false

  defp attempt_form_unsubscribe(url, html_body) do
    case AIService.analyze_unsubscribe_page(url, html_body) do
      {:ok, %{"method" => "form_submit", "form_data" => form_data}} when is_map(form_data) ->
        # Try to submit the form
        Logger.info("Attempting form submission with data: #{inspect(form_data)}")

        case Req.post(url, form: form_data) do
          {:ok, %{status: status, body: response_body}} when status in 200..299 ->
            Logger.info("Form submitted successfully, status: #{status}")

            # Check if the response indicates success
            if one_click_unsubscribe?(response_body) do
              {:ok, "form_submit_confirmed"}
            else
              {:ok, "form_submit"}
            end

          {:ok, %{status: status}} ->
            Logger.warning("Form submission returned status: #{status}")
            {:error, :form_submit_failed}

          {:error, error} ->
            Logger.error("Form submission error: #{inspect(error)}")
            {:error, :form_submit_failed}
        end

      {:ok, %{"method" => "button_click"}} ->
        # Can't actually click buttons without a browser
        Logger.info("Page requires button click - cannot automate without browser")
        {:error, :requires_browser}

      {:ok, %{"method" => "unknown", "reason" => reason}} ->
        Logger.info("AI could not determine unsubscribe method: #{reason}")
        {:error, :method_unknown}

      {:ok, unexpected} ->
        Logger.warning("Unexpected AI response format: #{inspect(unexpected)}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.error("AI analysis failed: #{inspect(reason)}")
        {:error, :analysis_failed}
    end
  end

  # NEW: Attempts to unsubscribe using browser automation and AI agent.
  # This is the true AI agent implementation that can interact with forms.
  defp attempt_browser_automation(url, html_body) do
    Logger.info("Attempting browser automation for: #{url}")

    # Parse the HTML to extract form structure
    case FormAnalyzer.analyze_page(html_body) do
      {:ok, analysis} ->
        # Use AI to determine how to interact with the page
        case AIService.analyze_form_structure(analysis) do
          {:ok, instructions} ->
            execute_browser_automation(url, instructions)

          {:error, reason} ->
            Logger.warning("AI form analysis failed: #{inspect(reason)}")
            {:error, :ai_analysis_failed}
        end

      {:error, reason} ->
        Logger.warning("Form parsing failed: #{inspect(reason)}")
        {:error, :form_parse_failed}
    end
  end

  defp execute_browser_automation(url, instructions) do
    Logger.info(
      "Executing browser automation with strategy: #{instructions["strategy"]}, confidence: #{instructions["confidence"]}"
    )

    # Use SessionManager to handle browser lifecycle
    case SessionManager.with_session(fn session ->
           perform_browser_actions(session, url, instructions)
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_browser_actions(session, url, instructions) do
    with {:ok, session} <- PageNavigator.navigate_to(session, url),
         {:ok, session} <- execute_strategy(session, instructions),
         {:ok, success?} <- PageNavigator.check_for_success_message(session) do
      if success? do
        Logger.info("Browser automation successful - success message detected")
        {:ok, "browser_automation_confirmed"}
      else
        Logger.info("Browser automation completed - success uncertain")
        {:ok, "browser_automation"}
      end
    else
      {:error, reason} ->
        Logger.error("Browser automation failed: #{inspect(reason)}")

        # Try to take screenshot for debugging
        SessionManager.take_screenshot(session, "unsubscribe_failed")

        {:error, reason}
    end
  end

  defp execute_strategy(session, %{"strategy" => "form_submit"} = instructions) do
    Logger.info("Executing form_submit strategy")

    with {:ok, session} <- fill_form_fields(session, instructions),
         {:ok, session} <- submit_form(session, instructions) do
      # Wait for page to process
      Process.sleep(2000)
      {:ok, session}
    end
  end

  defp execute_strategy(session, %{"strategy" => "button_click"} = instructions) do
    Logger.info("Executing button_click strategy")

    selector = instructions["submit_selector"] || "button"

    case FormInteractor.click_element(session, selector) do
      {:ok, session} ->
        Process.sleep(2000)
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_strategy(session, %{"strategy" => "link_click"} = instructions) do
    Logger.info("Executing link_click strategy")

    selector = instructions["link_selector"] || "a"

    case FormInteractor.click_element(session, selector) do
      {:ok, session} ->
        Process.sleep(2000)
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_strategy(_session, %{"strategy" => "unknown"}) do
    Logger.warning("Unknown strategy - cannot proceed")
    {:error, :unknown_strategy}
  end

  defp execute_strategy(session, _instructions) do
    Logger.warning("No valid strategy found in instructions")
    {:ok, session}
  end

  defp fill_form_fields(session, instructions) do
    fields = instructions["fields"] || []
    selects = instructions["selects"] || []
    checkboxes = instructions["checkboxes"] || []

    with {:ok, session} <- fill_text_fields(session, fields),
         {:ok, session} <- fill_select_fields(session, selects),
         {:ok, session} <- fill_checkbox_fields(session, checkboxes) do
      {:ok, session}
    end
  end

  defp fill_text_fields(session, fields) when is_list(fields) do
    Enum.reduce_while(fields, {:ok, session}, fn field, {:ok, sess} ->
      selector = field["selector"]
      value = field["value"]

      Logger.debug("Filling field #{selector} with: #{value}")

      case FormInteractor.fill_field(sess, selector, value) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fill_select_fields(session, selects) when is_list(selects) do
    Enum.reduce_while(selects, {:ok, session}, fn select, {:ok, sess} ->
      selector = select["selector"]
      value = select["value"]

      Logger.debug("Selecting option #{value} in #{selector}")

      case FormInteractor.select_option(sess, selector, value) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, _reason} -> {:cont, {:ok, sess}}
      end
    end)
  end

  defp fill_checkbox_fields(session, checkboxes) when is_list(checkboxes) do
    Enum.reduce_while(checkboxes, {:ok, session}, fn checkbox, {:ok, sess} ->
      selector = checkbox["selector"]
      checked = checkbox["checked"]

      Logger.debug("Setting checkbox #{selector} to #{checked}")

      case FormInteractor.toggle_checkbox(sess, selector, checked) do
        {:ok, new_session} -> {:cont, {:ok, new_session}}
        {:error, _reason} -> {:cont, {:ok, sess}}
      end
    end)
  end

  defp submit_form(session, instructions) do
    submit_selector = instructions["submit_selector"] || "button[type='submit']"

    Logger.info("Submitting form using selector: #{submit_selector}")

    case FormInteractor.click_element(session, submit_selector) do
      {:ok, session} ->
        {:ok, session}

      {:error, _reason} ->
        # Try alternative: submit the form directly
        Logger.info("Click failed, trying form.submit()")
        FormInteractor.submit_form(session)
    end
  end
end
