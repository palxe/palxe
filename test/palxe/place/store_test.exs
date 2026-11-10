defmodule Palxe.Place.StoreTest do
  use Palxe.DataCase, async: false

  alias Palxe.Place.{Canvas, Store}

  test "saves and loads the canvas snapshot" do
    assert Store.load_pixels(2, 2) == :error

    :ok = Store.save_pixels(2, 2, <<1, 2, 3, 4>>)
    assert Store.load_pixels(2, 2) == {:ok, <<1, 2, 3, 4>>}

    :ok = Store.save_pixels(2, 2, <<4, 3, 2, 1>>)
    assert Store.load_pixels(2, 2) == {:ok, <<4, 3, 2, 1>>}

    # mismatched dimensions are ignored
    assert Store.load_pixels(3, 3) == :error
  end

  test "records placements and finds the latest one" do
    t0 = ~U[2026-01-01 00:00:00.000000Z]

    :ok =
      Store.insert_placements([
        %{x: 1, y: 1, color: 2, player_id: "a", inserted_at: t0},
        %{x: 1, y: 1, color: 9, player_id: "b", inserted_at: DateTime.add(t0, 5)}
      ])

    assert %{player_id: "b", color: 9} = Store.last_placement(1, 1)
    assert Store.last_placement(0, 0) == nil
  end

  test "a persisting canvas restores its pixels after restart" do
    opts = [
      name: :persist_canvas,
      width: 3,
      height: 2,
      cooldown_ms: 0,
      persist: true,
      snapshot_interval_ms: 60_000,
      topic: "test:persist"
    ]

    start_supervised!({Canvas, opts})
    {:ok, _} = Canvas.place(:persist_canvas, "alice", 2, 1, 4)
    :ok = Canvas.flush(:persist_canvas)
    assert %{player_id: "alice", color: 4} = Store.last_placement(2, 1)

    stop_supervised!(Canvas)
    start_supervised!({Canvas, opts})

    %{pixels: pixels} = Canvas.get(:persist_canvas)
    assert :binary.at(pixels, 1 * 3 + 2) == 4
  end
end
