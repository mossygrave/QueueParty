defmodule QueueParty.Rooms do
  @moduledoc "In-memory room and queue state for the first MVP."

  use GenServer

  @topic_prefix "room:"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def create_room, do: GenServer.call(__MODULE__, :create)

  def get_room(code), do: GenServer.call(__MODULE__, {:get, String.upcase(code)})
  def subscribe(code), do: Phoenix.PubSub.subscribe(QueueParty.PubSub, topic(code))

  def add_item(code, youtube_id, submitted_by) do
    GenServer.call(__MODULE__, {:add_item, String.upcase(code), youtube_id, submitted_by})
  end

  def remove_item(code, item_id),
    do: GenServer.call(__MODULE__, {:remove_item, String.upcase(code), item_id})

  def skip(code), do: GenServer.call(__MODULE__, {:skip, String.upcase(code)})

  def finish(code, item_id),
    do: GenServer.call(__MODULE__, {:finish, String.upcase(code), item_id})

  @impl true
  def init(rooms), do: {:ok, rooms}

  @impl true
  def handle_call(:create, _from, rooms) do
    code = unique_code(rooms)
    room = %{code: code, host_token: token(), items: [], now_playing: nil}
    {:reply, {:ok, room}, Map.put(rooms, code, room)}
  end

  def handle_call({:get, code}, _from, rooms), do: {:reply, Map.get(rooms, code), rooms}

  def handle_call({:add_item, code, youtube_id, submitted_by}, _from, rooms) do
    with %{items: items} = room <- Map.get(rooms, code) do
      item = %{
        id: token(),
        youtube_id: youtube_id,
        submitted_by: submitted_by,
        title: "YouTube video #{youtube_id}",
        inserted_at: DateTime.utc_now()
      }

      room = %{room | items: items ++ [item]}
      rooms = Map.put(rooms, code, room)
      broadcast(code, {:room_updated, room})
      {:reply, {:ok, item}, rooms}
    else
      nil -> {:reply, {:error, :not_found}, rooms}
    end
  end

  def handle_call({:remove_item, code, item_id}, _from, rooms) do
    with %{items: items} = room <- Map.get(rooms, code) do
      room = %{room | items: Enum.reject(items, &(&1.id == item_id))}
      rooms = Map.put(rooms, code, room)
      broadcast(code, {:room_updated, room})
      {:reply, {:ok, room}, rooms}
    else
      nil -> {:reply, {:error, :not_found}, rooms}
    end
  end

  def handle_call({:skip, code}, _from, rooms) do
    case Map.get(rooms, code) do
      nil -> {:reply, {:error, :not_found}, rooms}
      room -> advance(room, rooms)
    end
  end

  def handle_call({:finish, code, item_id}, _from, rooms) do
    case Map.get(rooms, code) do
      %{now_playing: %{id: ^item_id}} = room -> advance(room, rooms)
      nil -> {:reply, {:error, :not_found}, rooms}
      room -> {:reply, {:ok, room}, rooms}
    end
  end

  defp advance(room, rooms) do
    {next, rest} =
      case room.items do
        [item | rest] -> {item, rest}
        [] -> {nil, []}
      end

    room = %{room | items: rest, now_playing: next}
    broadcast(room.code, {:room_updated, room})
    {:reply, {:ok, room}, Map.put(rooms, room.code, room)}
  end

  defp broadcast(code, message),
    do: Phoenix.PubSub.broadcast(QueueParty.PubSub, topic(code), message)

  defp topic(code), do: @topic_prefix <> String.upcase(code)
  defp token, do: :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

  defp unique_code(rooms) do
    code = :crypto.strong_rand_bytes(3) |> Base.encode32(case: :upper, padding: false)
    if Map.has_key?(rooms, code), do: unique_code(rooms), else: code
  end
end
