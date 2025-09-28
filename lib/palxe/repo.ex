defmodule Palxe.Repo do
  use Ecto.Repo,
    otp_app: :palxe,
    adapter: Ecto.Adapters.Postgres
end
