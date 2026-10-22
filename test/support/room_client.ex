defmodule QueueParty.RoomClient do
  use GenServer, restart: :temporary

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    {:ok, room} =
      QueueParty.Rooms.join_room(
        opts[:code],
        opts[:guest_id],
        opts[:host_token],
        opts[:name] || "Guest"
      )

    {:ok, room.code}
  end
end
