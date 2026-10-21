defmodule QueuePartyWeb.PageController do
  use QueuePartyWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
