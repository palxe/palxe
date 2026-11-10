defmodule Palxe.Place do
  @moduledoc """
  The shared pixel canvas game (an r/place-style collaborative canvas).
  """
  alias Palxe.Place.{Canvas, Palette, Store}

  @doc "Subscribes the caller to `{:pixel, x, y, color}` messages."
  def subscribe, do: Phoenix.PubSub.subscribe(Palxe.PubSub, Canvas.default_topic())

  @doc "Returns `%{width, height, pixels}` where pixels is one byte per pixel."
  def get_canvas, do: Canvas.get()

  def palette, do: Palette.colors()

  def cooldown_ms, do: config(:cooldown_ms, 5_000)

  defdelegate place_pixel(player_id, x, y, color), to: Canvas, as: :place
  defdelegate cooldown_until(player_id), to: Canvas

  @doc "Latest placement at `{x, y}` as `%{player_id, color, inserted_at}`, or nil."
  def pixel_info(x, y) do
    case Canvas.pending_placement(x, y) do
      nil -> if config(:persist, true), do: Store.last_placement(x, y)
      placement -> placement
    end
  end

  @doc "Short public handle derived from an anonymous player id."
  def player_handle(player_id) when is_binary(player_id) do
    hash = :crypto.hash(:sha256, player_id) |> Base.encode16(case: :lower)
    "pixel-" <> binary_part(hash, 0, 6)
  end

  defp config(key, default),
    do: :palxe |> Application.get_env(Palxe.Place, []) |> Keyword.get(key, default)
end
