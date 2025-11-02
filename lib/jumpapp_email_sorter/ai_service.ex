defmodule JumpappEmailSorter.AIService do
  @moduledoc """
  AI service for email categorization and summarization using Google Gemini.
  """

  @behaviour JumpappEmailSorter.AIServiceBehaviour

  require Logger

  @gemini_api_base "https://generativelanguage.googleapis.com/v1beta"
  # Using Gemini 2.5 Flash - stable and fast
  @model "gemini-2.5-flash"

  @doc """
  Categorizes an email based on available categories.
  Returns the best matching category ID or nil if no good match.
  """
  def categorize_email(email_content, categories) do
    if categories == [] do
      {:ok, nil}
    else
      prompt = build_categorization_prompt(email_content, categories)

      case call_gemini(prompt) do
        {:ok, response} ->
          parse_category_response(response, categories)

        {:error, error} ->
          Logger.error("AI categorization failed: #{inspect(error)}")
          # Graceful degradation
          {:ok, nil}
      end
    end
  end

  @doc """
  Generates a summary of an email.
  """
  def summarize_email(email_content) do
    prompt = """
    Please provide a concise 1-2 sentence summary of this email. Focus on the main point or action required.

    Email:
    #{truncate_content(email_content, 2000)}
    """

    case call_gemini(prompt) do
      {:ok, response} ->
        {:ok, String.trim(response)}

      {:error, error} ->
        Logger.error("AI summarization failed: #{inspect(error)}")
        # Fallback to simple preview
        {:ok, extract_preview(email_content)}
    end
  end

  @doc """
  Analyzes an unsubscribe page and attempts to identify the unsubscribe action.
  """
  def analyze_unsubscribe_page(_url, html_content) do
    prompt = """
    Analyze this unsubscribe page HTML and identify how to unsubscribe. Look for:
    1. Unsubscribe buttons or links
    2. Forms that need to be submitted
    3. Checkboxes that need to be toggled

    You MUST respond with ONLY valid JSON (no markdown, no explanation). Use this exact format:
    {
      "method": "button_click",
      "selector": "CSS selector or XPath",
      "form_data": {}
    }

    OR for forms:
    {
      "method": "form_submit",
      "selector": "form CSS selector",
      "form_data": {"field_name": "value"}
    }

    OR if you cannot determine:
    {
      "method": "unknown",
      "reason": "explanation"
    }

    Important:
    - Return ONLY the JSON object, no markdown code blocks
    - The "method" field is required
    - For form_submit, try to identify form field names and values
    - Look for hidden input fields, CSRF tokens, etc.

    HTML (truncated):
    #{truncate_content(html_content, 3000)}
    """

    case call_gemini(prompt) do
      {:ok, response} ->
        parse_unsubscribe_response(response)

      {:error, error} ->
        Logger.error("AI unsubscribe analysis failed: #{inspect(error)}")
        {:error, :analysis_failed}
    end
  end

  # Private functions

  defp call_gemini(prompt) do
    api_key = System.get_env("GOOGLE_GEMINI_API_KEY")

    if !api_key do
      Logger.error("GOOGLE_GEMINI_API_KEY not set")
      {:error, :no_api_key}
    else
      url = "#{@gemini_api_base}/models/#{@model}:generateContent?key=#{api_key}"

      body = %{
        contents: [
          %{
            parts: [
              %{
                text: prompt
              }
            ]
          }
        ],
        generationConfig: %{
          temperature: 0.7,
          maxOutputTokens: 1024
        }
      }

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: response}} ->
          content =
            get_in(response, [
              "candidates",
              Access.at(0),
              "content",
              "parts",
              Access.at(0),
              "text"
            ])

          {:ok, content}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Google Gemini API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, error} ->
          Logger.error("Google Gemini API request failed: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  defp build_categorization_prompt(email_content, categories) do
    categories_text =
      categories
      |> Enum.map(fn cat ->
        "- ID: #{cat.id}, Name: #{cat.name}, Description: #{cat.description || "No description"}"
      end)
      |> Enum.join("\n")

    """
    You are an email categorization assistant. Given an email and a list of categories, determine which category best fits the email.

    Categories:
    #{categories_text}

    Email content:
    #{truncate_content(email_content, 1500)}

    Respond with ONLY the category ID number that best matches this email. If none of the categories are a good fit, respond with "NONE".
    """
  end

  defp parse_category_response(response, categories) do
    response = String.trim(response)

    cond do
      response == "NONE" ->
        {:ok, nil}

      true ->
        # Try to extract a number from the response
        case Integer.parse(response) do
          {category_id, _} ->
            if Enum.any?(categories, fn cat -> cat.id == category_id end) do
              {:ok, category_id}
            else
              {:ok, nil}
            end

          :error ->
            {:ok, nil}
        end
    end
  end

  defp parse_unsubscribe_response(response) when is_binary(response) do
    # Clean the response - AI often wraps JSON in markdown code blocks
    cleaned_response =
      response
      |> String.trim()
      # Remove markdown code blocks
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/^```\s*/m, "")
      |> String.replace(~r/```\s*$/m, "")
      |> String.trim()

    # Try to parse JSON response
    case Jason.decode(cleaned_response) do
      {:ok, data} when is_map(data) ->
        # Validate that it has the expected structure
        if Map.has_key?(data, "method") do
          {:ok, data}
        else
          Logger.warning("AI response missing 'method' field: #{inspect(data)}")
          {:error, :invalid_structure}
        end

      {:error, error} ->
        # If not valid JSON, try to extract JSON from text
        Logger.warning("Failed to parse AI response as JSON: #{inspect(error)}")
        Logger.debug("AI response was: #{cleaned_response}")
        {:error, :invalid_response}
    end
  end

  defp parse_unsubscribe_response(nil), do: {:ok, %{"has_form" => false, "fields" => []}}

  defp truncate_content(content, max_length) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "..."
    else
      content
    end
  end

  defp extract_preview(content) do
    content
    |> String.slice(0, 200)
    |> String.trim()
  end
end
