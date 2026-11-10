defmodule Palxe.Place.Canvas do
  @moduledoc """
  Owns the shared canvas in memory.

  The canvas is a binary with one byte per pixel (a palette index), stored
  row-major. All writes are serialized through this process, which also
  enforces the per-player cooldown, broadcasts placements over PubSub and
  periodically persists the canvas plus the placement log.
  """
  use GenServer

  alias Palxe.Place.{Palette, Store}

  @default_topic "place:canvas"

  defstruct [
    :width,
    :height,
    :pixels,
    :cooldown_ms,
    :persist?,
    :snapshot_interval_ms,
    :topic,
    :pubsub,
    dirty?: false,
    cooldowns: %{},
    pending: []
  ]

  ## Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def default_topic, do: @default_topic

  @doc "Returns `%{width, height, pixels}`."
  def get(server \\ __MODULE__), do: GenServer.call(server, :get)

  @doc """
  Places a pixel for `player_id`.

  Returns `{:ok, cooldown_until_ms}`, `{:error, {:cooldown, cooldown_until_ms}}`
  or `{:error, :invalid}`. Timestamps are unix milliseconds.
  """
  def place(server \\ __MODULE__, player_id, x, y, color),
    do: GenServer.call(server, {:place, player_id, x, y, color})

  @doc "Unix ms timestamp at which `player_id` may place again, or nil."
  def cooldown_until(server \\ __MODULE__, player_id),
    do: GenServer.call(server, {:cooldown_until, player_id})

  @doc "Most recent not-yet-persisted placement at `{x, y}`, or nil."
  def pending_placement(server \\ __MODULE__, x, y),
    do: GenServer.call(server, {:pending_placement, x, y})

  @doc "Persists immediately (used on shutdown and in tests)."
  def flush(server \\ __MODULE__), do: GenServer.call(server, :flush)

  ## Server

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    config = Keyword.merge(Application.get_env(:palxe, Palxe.Place, []), opts)

    width = Keyword.get(config, :width, 500)
    height = Keyword.get(config, :height, 500)
    persist? = Keyword.get(config, :persist, true)

    pixels =
      with true <- persist?,
           {:ok, pixels} <- Store.load_pixels(width, height) do
        pixels
      else
        _ -> :binary.copy(<<Palette.white()>>, width * height)
      end

    state = %__MODULE__{
      width: width,
      height: height,
      pixels: pixels,
      cooldown_ms: Keyword.get(config, :cooldown_ms, 5_000),
      persist?: persist?,
      snapshot_interval_ms: Keyword.get(config, :snapshot_interval_ms, 5_000),
      topic: Keyword.get(config, :topic, @default_topic),
      pubsub: Keyword.get(config, :pubsub, Palxe.PubSub)
    }

    schedule_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, %{width: state.width, height: state.height, pixels: state.pixels}, state}
  end

  def handle_call({:place, player_id, x, y, color}, _from, state) do
    now = now_ms()

    cond do
      not valid_placement?(state, player_id, x, y, color) ->
        {:reply, {:error, :invalid}, state}

      (until = active_cooldown(state, player_id, now)) != nil ->
        {:reply, {:error, {:cooldown, until}}, state}

      true ->
        offset = y * state.width + x
        <<before::binary-size(offset), _old, rest::binary>> = state.pixels

        placement = %{
          x: x,
          y: y,
          color: color,
          player_id: player_id,
          inserted_at: DateTime.utc_now()
        }

        Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:pixel, x, y, color})

        state = %{
          state
          | pixels: <<before::binary, color, rest::binary>>,
            dirty?: true,
            cooldowns: Map.put(state.cooldowns, player_id, now),
            pending: [placement | state.pending]
        }

        {:reply, {:ok, now + state.cooldown_ms}, state}
    end
  end

  def handle_call({:cooldown_until, player_id}, _from, state) do
    {:reply, active_cooldown(state, player_id, now_ms()), state}
  end

  def handle_call({:pending_placement, x, y}, _from, state) do
    {:reply, Enum.find(state.pending, &(&1.x == x and &1.y == y)), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, persist(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    state = state |> persist() |> prune_cooldowns()
    schedule_tick(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    persist(state)
    :ok
  end

  ## Helpers

  defp valid_placement?(state, player_id, x, y, color) do
    is_binary(player_id) and player_id != "" and is_integer(x) and is_integer(y) and
      x >= 0 and y >= 0 and x < state.width and y < state.height and Palette.valid?(color)
  end

  defp active_cooldown(state, player_id, now) do
    case Map.fetch(state.cooldowns, player_id) do
      {:ok, last} when now - last < state.cooldown_ms -> last + state.cooldown_ms
      _ -> nil
    end
  end

  defp persist(%{persist?: false} = state), do: %{state | dirty?: false, pending: []}

  defp persist(state) do
    if state.dirty? do
      Store.save_pixels(state.width, state.height, state.pixels)
    end

    Store.insert_placements(Enum.reverse(state.pending))
    %{state | dirty?: false, pending: []}
  end

  defp prune_cooldowns(state) do
    now = now_ms()
    cooldowns = Map.reject(state.cooldowns, fn {_, last} -> now - last >= state.cooldown_ms end)
    %{state | cooldowns: cooldowns}
  end

  defp schedule_tick(state), do: Process.send_after(self(), :tick, state.snapshot_interval_ms)

  defp now_ms, do: System.system_time(:millisecond)
end
