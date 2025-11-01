defmodule JumpappEmailSorter.AIService do
  @moduledoc """
  AI service for email categorization and summarization using Anthropic Claude.
  """

  require Logger

  @anthropic_api_base "https://api.anthropic.com/v1"
  @model "claude-3-haiku-20240307"  # Using Haiku for cost efficiency

  @doc """
  Categorizes an email based on available categories.
  Returns the best matching category ID or nil if no good match.
  """
  def categorize_email(email_content, categories) do
    if categories == [] do
      {:ok, nil}
    else
      prompt = build_categorization_prompt(email_content, categories)
      
      case call_claude(prompt) do
        {:ok, response} ->
          parse_category_response(response, categories)

        {:error, error} ->
          Logger.error("AI categorization failed: #{inspect(error)}")
          {:ok, nil}  # Graceful degradation
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

    case call_claude(prompt) do
      {:ok, response} ->
        {:ok, String.trim(response)}

      {:error, error} ->
        Logger.error("AI summarization failed: #{inspect(error)}")
        {:ok, extract_preview(email_content)}  # Fallback to simple preview
    end
  end

  @doc """
  Analyzes an unsubscribe page and attempts to identify the unsubscribe action.
  """
  def analyze_unsubscribe_page(html_content) do
    prompt = """
    Analyze this unsubscribe page HTML and identify how to unsubscribe. Look for:
    1. Unsubscribe buttons or links
    2. Forms that need to be submitted
    3. Checkboxes that need to be toggled

    Respond in JSON format with:
    {
      "method": "button_click" | "form_submit" | "link_follow",
      "selector": "CSS selector or XPath",
      "form_data": {"field": "value"} (if form_submit)
    }

    HTML (truncated):
    #{truncate_content(html_content, 3000)}
    """

    case call_claude(prompt) do
      {:ok, response} ->
        parse_unsubscribe_response(response)

      {:error, error} ->
        Logger.error("AI unsubscribe analysis failed: #{inspect(error)}")
        {:error, :analysis_failed}
    end
  end

  # Private functions

  defp call_claude(prompt) do
    api_key = System.get_env("ANTHROPIC_API_KEY")

    if !api_key do
      Logger.error("ANTHROPIC_API_KEY not set")
      {:error, :no_api_key}
    else
      url = "#{@anthropic_api_base}/messages"

      body = %{
        model: @model,
        max_tokens: 1024,
        messages: [
          %{
            role: "user",
            content: prompt
          }
        ]
      }

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ]

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          content = get_in(response, ["content", Access.at(0), "text"])
          {:ok, content}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Anthropic API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, error} ->
          Logger.error("Anthropic API request failed: #{inspect(error)}")
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

  defp parse_unsubscribe_response(response) do
    # Try to parse JSON response
    case Jason.decode(response) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        # If not valid JSON, try to extract information from text
        {:error, :invalid_response}
    end
  end

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

