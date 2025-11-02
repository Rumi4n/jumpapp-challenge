defmodule JumpappEmailSorter.AIServiceBehaviour do
  @moduledoc """
  Behaviour for AI service operations.
  This allows us to mock the AI service in tests.
  """

  @callback summarize_email(email_content :: String.t()) ::
              {:ok, String.t()}

  @callback categorize_email(email_content :: String.t(), categories :: list(map())) ::
              {:ok, integer() | nil}

  @callback analyze_unsubscribe_page(url :: String.t(), page_content :: String.t()) ::
              {:ok, map()} | {:error, term()}
end

