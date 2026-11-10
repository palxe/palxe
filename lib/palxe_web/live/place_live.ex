defmodule PalxeWeb.PlaceLive do
  use PalxeWeb, :live_view

  alias Palxe.Place

  @impl true
  def mount(_params, session, socket) do
    player_id = session["player_id"]
    canvas = Place.get_canvas()

    if connected?(socket), do: Place.subscribe()

    socket =
      socket
      |> assign(
        page_title: "Canvas",
        player_id: player_id,
        width: canvas.width,
        height: canvas.height,
        palette: Enum.with_index(Place.palette()),
        selected_color: nil,
        selected_pixel: nil,
        pixel_info: nil
      )
      |> assign_cooldown(player_id && Place.cooldown_until(player_id))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} fullscreen>
      <div
        id="place-canvas"
        phx-hook="PlaceCanvas"
        phx-update="ignore"
        data-width={@width}
        data-height={@height}
        class="absolute inset-0 touch-none select-none overflow-hidden bg-zinc-200 cursor-crosshair dark:bg-zinc-950"
      >
        <div data-role="world" class="absolute left-0 top-0 origin-top-left will-change-transform">
          <canvas
            data-role="canvas"
            width={@width}
            height={@height}
            class="pixelated block bg-white shadow-[0_0_0_1px_rgba(0,0,0,0.08),0_20px_60px_-20px_rgba(0,0,0,0.35)]"
          >
          </canvas>
        </div>
        <div data-role="reticle" class="place-reticle pointer-events-none absolute hidden"></div>
        <div
          data-role="loading"
          class="absolute inset-0 grid place-items-center text-sm text-zinc-500 transition-opacity duration-500"
        >
          <div class="flex items-center gap-2 rounded-full bg-white/80 px-4 py-2 shadow-lg backdrop-blur dark:bg-zinc-900/80">
            <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Loading canvas…
          </div>
        </div>
      </div>

      <%!-- Top bar --%>
      <div class="pointer-events-none absolute inset-x-0 top-0 flex items-start justify-between gap-3 p-3 sm:p-4">
        <div class="pointer-events-auto flex items-center gap-2">
          <div class="flex items-center gap-2 rounded-full bg-white/85 py-1.5 pl-1.5 pr-4 shadow-lg ring-1 ring-black/5 backdrop-blur dark:bg-zinc-900/85 dark:ring-white/10">
            <span class="grid size-7 grid-cols-2 grid-rows-2 overflow-hidden rounded-full">
              <span class="bg-[#FF4500]"></span><span class="bg-[#FFD635]"></span>
              <span class="bg-[#3690EA]"></span><span class="bg-[#00A368]"></span>
            </span>
            <span class="font-semibold tracking-tight">Palxe</span>
          </div>
          <div
            id="hover-coords"
            phx-update="ignore"
            class="hidden rounded-full bg-white/85 px-3 py-1.5 font-mono text-xs tabular-nums shadow-lg ring-1 ring-black/5 backdrop-blur sm:block dark:bg-zinc-900/85 dark:ring-white/10"
          >
            (0, 0) 1×
          </div>
        </div>

        <div class="pointer-events-auto flex items-center gap-2">
          <div class="flex overflow-hidden rounded-full bg-white/85 shadow-lg ring-1 ring-black/5 backdrop-blur dark:bg-zinc-900/85 dark:ring-white/10">
            <button
              id="zoom-out"
              type="button"
              aria-label="Zoom out"
              phx-click={JS.dispatch("place:zoom", to: "#place-canvas", detail: %{factor: 0.5})}
              class="grid size-9 place-items-center transition hover:bg-black/5 active:scale-90 dark:hover:bg-white/10"
            >
              <.icon name="hero-minus" class="size-4" />
            </button>
            <button
              id="zoom-in"
              type="button"
              aria-label="Zoom in"
              phx-click={JS.dispatch("place:zoom", to: "#place-canvas", detail: %{factor: 2})}
              class="grid size-9 place-items-center transition hover:bg-black/5 active:scale-90 dark:hover:bg-white/10"
            >
              <.icon name="hero-plus" class="size-4" />
            </button>
          </div>
          <Layouts.theme_toggle />
        </div>
      </div>

      <%!-- Bottom controls --%>
      <div class="pointer-events-none absolute inset-x-0 bottom-0 flex justify-center p-3 sm:p-5">
        <%= if @selected_pixel do %>
          <div
            id="place-panel"
            class="place-panel pointer-events-auto w-full max-w-xl rounded-2xl bg-white/95 p-3 shadow-2xl ring-1 ring-black/5 backdrop-blur sm:p-4 dark:bg-zinc-900/95 dark:ring-white/10"
          >
            <div class="mb-3 flex items-center justify-between gap-3 text-sm">
              <div class="flex min-w-0 items-center gap-2">
                <span class="rounded-md bg-zinc-100 px-2 py-0.5 font-mono text-xs tabular-nums dark:bg-zinc-800">
                  ({elem(@selected_pixel, 0)}, {elem(@selected_pixel, 1)})
                </span>
                <span id="pixel-info" class="truncate text-zinc-500">
                  <%= if @pixel_info do %>
                    <span
                      class="mr-1 inline-block size-2.5 rounded-sm align-middle ring-1 ring-black/10"
                      style={"background: #{Palxe.Place.Palette.hex(@pixel_info.color)}"}
                    >
                    </span>
                    by
                    <span class="font-medium text-zinc-700 dark:text-zinc-300">
                      {handle(@pixel_info.player_id, @player_id)}
                    </span>
                    · {ago(@pixel_info.inserted_at)}
                  <% else %>
                    Untouched pixel
                  <% end %>
                </span>
              </div>
              <button
                id="deselect-btn"
                type="button"
                phx-click="deselect"
                aria-label="Close"
                class="grid size-8 shrink-0 place-items-center rounded-full text-zinc-500 transition hover:bg-zinc-100 hover:text-zinc-900 active:scale-90 dark:hover:bg-zinc-800 dark:hover:text-zinc-100"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div id="palette" class="grid grid-cols-8 gap-1.5 sm:grid-cols-16">
              <button
                :for={{hex, index} <- @palette}
                id={"color-#{index}"}
                type="button"
                phx-click="select_color"
                phx-value-color={index}
                aria-label={"Color #{hex}"}
                style={"background: #{hex}"}
                class={[
                  "aspect-square rounded-md ring-1 ring-black/10 transition duration-150 hover:-translate-y-0.5 hover:shadow-md active:scale-90",
                  @selected_color == index &&
                    "scale-110 shadow-md outline-2 outline-offset-2 outline-zinc-900 dark:outline-white"
                ]}
              >
              </button>
            </div>

            <div class="mt-3 flex items-center gap-2">
              <button
                id="cancel-btn"
                type="button"
                phx-click="deselect"
                class="h-11 flex-1 rounded-xl bg-zinc-100 font-medium transition hover:bg-zinc-200 active:scale-[0.98] dark:bg-zinc-800 dark:hover:bg-zinc-700"
              >
                Cancel
              </button>
              <button
                id="place-btn"
                type="button"
                phx-click="place"
                disabled={is_nil(@selected_color) or not is_nil(@cooldown_until)}
                class="h-11 flex-[2] rounded-xl bg-[#FF4500] font-semibold text-white shadow-lg shadow-[#FF4500]/30 transition hover:brightness-110 active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-zinc-300 disabled:shadow-none disabled:text-zinc-500 dark:disabled:bg-zinc-700 dark:disabled:text-zinc-400 phx-click-loading:opacity-70"
              >
                <%= cond do %>
                  <% @cooldown_until -> %>
                    <span class="inline-flex items-center gap-1.5">
                      <.icon name="hero-clock" class="size-4" />
                      <.cooldown_timer until={@cooldown_until} />
                    </span>
                  <% is_nil(@selected_color) -> %>
                    Pick a color
                  <% true -> %>
                    Place pixel
                <% end %>
              </button>
            </div>
          </div>
        <% else %>
          <div
            id="status-pill"
            class="pointer-events-auto flex items-center gap-2 rounded-full bg-white/90 px-5 py-3 text-sm font-medium shadow-xl ring-1 ring-black/5 backdrop-blur dark:bg-zinc-900/90 dark:ring-white/10"
          >
            <%= if @cooldown_until do %>
              <.icon name="hero-clock" class="size-4 text-zinc-500" /> Next pixel in
              <.cooldown_timer until={@cooldown_until} />
            <% else %>
              <span class="relative flex size-2.5">
                <span class="absolute inline-flex size-full animate-ping rounded-full bg-[#FF4500] opacity-60">
                </span>
                <span class="relative inline-flex size-2.5 rounded-full bg-[#FF4500]"></span>
              </span>
              Tap a pixel to place a tile
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :until, :integer, required: true

  defp cooldown_timer(assigns) do
    ~H"""
    <span
      id="cooldown-timer"
      phx-hook="Cooldown"
      phx-update="ignore"
      data-until={@until}
      class="font-mono tabular-nums"
    >
      {format_remaining(@until)}
    </span>
    """
  end

  ## Events

  @impl true
  def handle_event("load", _params, socket) do
    %{width: w, height: h, pixels: pixels} = Place.get_canvas()

    {:reply, %{width: w, height: h, palette: Place.palette(), pixels: Base.encode64(pixels)},
     socket}
  end

  def handle_event("select_pixel", %{"x" => x, "y" => y}, socket)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 do
    if x < socket.assigns.width and y < socket.assigns.height do
      {:noreply, assign(socket, selected_pixel: {x, y}, pixel_info: Place.pixel_info(x, y))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_pixel", _params, socket), do: {:noreply, socket}

  def handle_event("deselect", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_pixel: nil, pixel_info: nil)
     |> push_event("deselect", %{})}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    case Integer.parse(to_string(color)) do
      {index, ""} when index >= 0 and index < length(socket.assigns.palette) ->
        {:noreply,
         socket
         |> assign(selected_color: index)
         |> push_event("color", %{hex: Palxe.Place.Palette.hex(index)})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("place", _params, socket) do
    %{selected_pixel: pixel, selected_color: color, player_id: player_id} = socket.assigns

    case {pixel, color} do
      {{x, y}, color} when is_integer(color) ->
        case Place.place_pixel(player_id, x, y, color) do
          {:ok, until} ->
            {:noreply,
             socket
             |> assign_cooldown(until)
             |> assign(selected_pixel: nil, pixel_info: nil)
             |> push_event("placed", %{x: x, y: y, c: color})}

          {:error, {:cooldown, until}} ->
            {:noreply,
             socket
             |> assign_cooldown(until)
             |> put_flash(:error, "Slow down! You can place another pixel soon.")}

          {:error, :invalid} ->
            {:noreply, put_flash(socket, :error, "That pixel can't be placed.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:pixel, x, y, color}, socket) do
    socket = push_event(socket, "pixel", %{x: x, y: y, c: color})

    socket =
      if socket.assigns.selected_pixel == {x, y},
        do: assign(socket, pixel_info: Place.pixel_info(x, y)),
        else: socket

    {:noreply, socket}
  end

  def handle_info(:cooldown_check, socket) do
    {:noreply, assign_cooldown(socket, socket.assigns.cooldown_until)}
  end

  ## Helpers

  defp assign_cooldown(socket, until) do
    remaining = if until, do: until - System.system_time(:millisecond), else: 0

    if remaining > 0 do
      if connected?(socket), do: Process.send_after(self(), :cooldown_check, remaining + 50)
      assign(socket, cooldown_until: until)
    else
      assign(socket, cooldown_until: nil)
    end
  end

  defp format_remaining(until) do
    secs = max(0, ceil((until - System.system_time(:millisecond)) / 1000))
    "#{div(secs, 60)}:#{secs |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp handle(player_id, player_id), do: "you"
  defp handle(player_id, _me), do: Place.player_handle(player_id)

  defp ago(%DateTime{} = at) do
    case DateTime.diff(DateTime.utc_now(), at) do
      s when s < 5 -> "just now"
      s when s < 60 -> "#{s}s ago"
      s when s < 3600 -> "#{div(s, 60)}m ago"
      s when s < 86_400 -> "#{div(s, 3600)}h ago"
      s -> "#{div(s, 86_400)}d ago"
    end
  end
end
