defmodule JumpappEmailSorter.Repo do
  use Ecto.Repo,
    otp_app: :jumpapp_email_sorter,
    adapter: Ecto.Adapters.Postgres
end
