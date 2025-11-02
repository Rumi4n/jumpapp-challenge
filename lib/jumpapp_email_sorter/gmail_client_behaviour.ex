defmodule JumpappEmailSorter.GmailClientBehaviour do
  @moduledoc """
  Behaviour for Gmail API client operations.
  This allows us to mock the Gmail client in tests.
  """

  @callback list_messages(access_token :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback get_message(access_token :: String.t(), message_id :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback archive_message(access_token :: String.t(), message_id :: String.t()) ::
              :ok | {:error, term()}

  @callback trash_message(access_token :: String.t(), message_id :: String.t()) ::
              :ok | {:error, term()}

  @callback refresh_access_token(refresh_token :: String.t()) ::
              {:ok, map()} | {:error, term()}
end

