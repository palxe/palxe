defmodule PalxeWeb.Plugs.PlayerId do
  @moduledoc "Assigns every visitor an anonymous, session-backed player id."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "player_id") do
      id when is_binary(id) and id != "" ->
        conn

      _ ->
        put_session(conn, "player_id", Base.url_encode64(:crypto.strong_rand_bytes(12)))
    end
  end
end
