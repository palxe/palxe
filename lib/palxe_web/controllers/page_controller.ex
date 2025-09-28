defmodule PalxeWeb.PageController do
  use PalxeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
