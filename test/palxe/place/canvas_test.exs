defmodule Palxe.Place.CanvasTest do
  use ExUnit.Case, async: true

  alias Palxe.Place.{Canvas, Palette}

  setup do
    topic = "test:canvas:#{System.unique_integer([:positive])}"
    name = :"canvas_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Canvas,
       name: name,
       width: 4,
       height: 3,
       cooldown_ms: 100,
       persist: false,
       snapshot_interval_ms: 60_000,
       topic: topic}
    )

    Phoenix.PubSub.subscribe(Palxe.PubSub, topic)
    %{canvas: name}
  end

  test "starts as a blank white canvas", %{canvas: canvas} do
    assert %{width: 4, height: 3, pixels: pixels} = Canvas.get(canvas)
    assert pixels == :binary.copy(<<Palette.white()>>, 12)
  end

  test "places a pixel, updates the binary and broadcasts", %{canvas: canvas} do
    assert {:ok, until} = Canvas.place(canvas, "alice", 2, 1, 5)
    assert until > System.system_time(:millisecond)

    %{pixels: pixels} = Canvas.get(canvas)
    assert :binary.at(pixels, 1 * 4 + 2) == 5
    assert byte_size(pixels) == 12

    assert_receive {:pixel, 2, 1, 5}
  end

  test "rejects invalid placements", %{canvas: canvas} do
    assert {:error, :invalid} = Canvas.place(canvas, "alice", 4, 0, 1)
    assert {:error, :invalid} = Canvas.place(canvas, "alice", 0, 3, 1)
    assert {:error, :invalid} = Canvas.place(canvas, "alice", -1, 0, 1)
    assert {:error, :invalid} = Canvas.place(canvas, "alice", 0, 0, Palette.size())
    assert {:error, :invalid} = Canvas.place(canvas, "alice", "0", 0, 1)
    assert {:error, :invalid} = Canvas.place(canvas, "", 0, 0, 1)
    refute_receive {:pixel, _, _, _}
  end

  test "enforces a per-player cooldown", %{canvas: canvas} do
    assert {:ok, until} = Canvas.place(canvas, "alice", 0, 0, 1)
    assert {:error, {:cooldown, ^until}} = Canvas.place(canvas, "alice", 1, 0, 1)
    assert Canvas.cooldown_until(canvas, "alice") == until

    # other players are not affected
    assert {:ok, _} = Canvas.place(canvas, "bob", 1, 0, 2)

    Process.sleep(120)
    assert Canvas.cooldown_until(canvas, "alice") == nil
    assert {:ok, _} = Canvas.place(canvas, "alice", 1, 0, 3)
  end

  test "remembers the latest pending placement for a pixel", %{canvas: canvas} do
    assert Canvas.pending_placement(canvas, 0, 0) == nil
    {:ok, _} = Canvas.place(canvas, "alice", 0, 0, 1)
    {:ok, _} = Canvas.place(canvas, "bob", 0, 0, 7)

    assert %{player_id: "bob", color: 7} = Canvas.pending_placement(canvas, 0, 0)
  end
end
