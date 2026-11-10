defmodule PalxeWeb.PlaceLiveTest do
  use PalxeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Palxe.Place

  defp player_conn(conn) do
    id = "player-#{System.unique_integer([:positive])}"
    {Plug.Test.init_test_session(conn, player_id: id), id}
  end

  test "renders the canvas and status", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#place-canvas[phx-hook=PlaceCanvas]")
    assert has_element?(view, "#status-pill")
    refute has_element?(view, "#place-panel")
  end

  test "assigns an anonymous player id to new visitors", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert is_binary(get_session(conn, "player_id"))
  end

  test "load returns the full canvas", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "load", %{})
    assert_reply view, %{width: w, height: h, pixels: pixels, palette: palette}
    assert byte_size(Base.decode64!(pixels)) == w * h
    assert length(palette) == 32
  end

  test "select a pixel and color, then place it", %{conn: conn} do
    {conn, player_id} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "select_pixel", %{"x" => 10, "y" => 20})
    assert has_element?(view, "#place-panel")
    assert has_element?(view, "#palette")
    assert has_element?(view, "#place-btn[disabled]")

    view |> element("#color-2") |> render_click()
    refute has_element?(view, "#place-btn[disabled]")

    view |> element("#place-btn") |> render_click()
    assert_push_event view, "placed", %{x: 10, y: 20, c: 2}
    assert_push_event view, "pixel", %{x: 10, y: 20, c: 2}

    %{pixels: pixels, width: w} = Place.get_canvas()
    assert :binary.at(pixels, 20 * w + 10) == 2

    # panel closes and the cooldown is shown
    refute has_element?(view, "#place-panel")
    assert has_element?(view, "#cooldown-timer")
    assert Place.cooldown_until(player_id)

    # selecting again keeps the place button disabled during cooldown
    render_hook(view, "select_pixel", %{"x" => 11, "y" => 20})
    view |> element("#color-3") |> render_click()
    assert has_element?(view, "#place-btn[disabled]")
  end

  test "shows who placed a selected pixel", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _} = Place.place_pixel("someone-else", 30, 31, 4)
    render_hook(view, "select_pixel", %{"x" => 30, "y" => 31})

    assert view |> element("#pixel-info") |> render() =~ Place.player_handle("someone-else")
  end

  test "forwards other players' pixels to the client", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _} = Place.place_pixel("another-player", 3, 4, 7)
    assert_push_event view, "pixel", %{x: 3, y: 4, c: 7}
  end

  test "deselect closes the panel", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "select_pixel", %{"x" => 1, "y" => 1})
    view |> element("#cancel-btn") |> render_click()
    refute has_element?(view, "#place-panel")
    assert_push_event view, "deselect", %{}
  end

  test "ignores out-of-bounds selections", %{conn: conn} do
    {conn, _} = player_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "select_pixel", %{"x" => 100_000, "y" => 1})
    refute has_element?(view, "#place-panel")
  end
end
