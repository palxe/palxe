defmodule Palxe.Place.CanvasSnapshot do
  @moduledoc "Persisted copy of the whole canvas (one byte per pixel, palette index)."
  use Ecto.Schema

  schema "canvases" do
    field :width, :integer
    field :height, :integer
    field :pixels, :binary

    timestamps(type: :utc_datetime)
  end
end
