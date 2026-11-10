defmodule Palxe.Place.Store do
  @moduledoc "Database persistence for the canvas snapshot and placement log."
  import Ecto.Query

  alias Palxe.Repo
  alias Palxe.Place.{CanvasSnapshot, Placement}

  @snapshot_id 1

  @doc "Returns the stored pixels if a snapshot with matching dimensions exists."
  def load_pixels(width, height) do
    case Repo.get(CanvasSnapshot, @snapshot_id) do
      %CanvasSnapshot{width: ^width, height: ^height, pixels: pixels}
      when byte_size(pixels) == width * height ->
        {:ok, pixels}

      _ ->
        :error
    end
  end

  def save_pixels(width, height, pixels) do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      %CanvasSnapshot{
        id: @snapshot_id,
        width: width,
        height: height,
        pixels: pixels,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: {:replace, [:width, :height, :pixels, :updated_at]},
      conflict_target: :id
    )

    :ok
  end

  @doc "Inserts placements given as maps with :x, :y, :color, :player_id, :inserted_at."
  def insert_placements([]), do: :ok

  def insert_placements(placements) do
    placements
    |> Enum.chunk_every(5_000)
    |> Enum.each(&Repo.insert_all(Placement, &1))

    :ok
  end

  def last_placement(x, y) do
    Placement
    |> where([p], p.x == ^x and p.y == ^y)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end
end
