defmodule Palxe.Place.Placement do
  @moduledoc "Append-only log entry of a single pixel placement."
  use Ecto.Schema

  schema "pixel_placements" do
    field :x, :integer
    field :y, :integer
    field :color, :integer
    field :player_id, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
