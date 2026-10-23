defmodule QueueParty.YouTubePlaylist do
  @moduledoc "Imports bounded, ordered snapshots of public YouTube playlists."
  @hosts ~w(youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be www.youtu.be)
  @limit 200

  def playlist_id(url) when is_binary(url) do
    url = String.trim(url)
    uri = URI.parse(if String.contains?(url, "://"), do: url, else: "https://" <> url)
    id = URI.decode_query(uri.query || "")["list"]

    if uri.scheme in ["http", "https"] && String.downcase(uri.host || "") in @hosts &&
         is_binary(id) && Regex.match?(~r/\A[A-Za-z0-9_-]{10,100}\z/, id) &&
         !String.starts_with?(id, "RD"), do: {:ok, id}, else: {:error, :invalid_url}
  rescue
    ArgumentError -> {:error, :invalid_url}
  end

  def playlist_id(_), do: {:error, :invalid_url}

  def fetch(url, options \\ []) do
    key = Keyword.get(options, :api_key, Application.get_env(:queue_party, :youtube_api_key))
    options = Keyword.delete(options, :api_key)

    with {:ok, id} <- playlist_id(url),
         :ok <- configured_key(key),
         {:ok, metadata} <- request("playlists", [part: "snippet,status", id: id], key, options),
         {:ok, title} <- public_title(metadata),
         {:ok, tracks} <- pages(id, key, options, nil, [], MapSet.new(), 0),
         false <- tracks == [] do
      {:ok,
       %{id: id, title: title, tracks: tracks, url: "https://www.youtube.com/playlist?list=#{id}"}}
    else
      true -> {:error, :empty}
      {:error, _} = error -> error
    end
  end

  defp configured_key(key) when is_binary(key) do
    if String.trim(key) == "", do: {:error, :missing_api_key}, else: :ok
  end

  defp configured_key(_), do: {:error, :missing_api_key}

  defp public_title(%{
         "items" => [
           %{"status" => %{"privacyStatus" => "public"}, "snippet" => %{"title" => title}} | _
         ]
       })
       when is_binary(title), do: {:ok, String.slice(title, 0, 500)}

  defp public_title(_), do: {:error, :not_public}

  defp pages(id, key, options, page_token, tracks, seen, count) do
    params = [part: "snippet,contentDetails", playlistId: id, maxResults: 50]
    params = if page_token, do: params ++ [pageToken: page_token], else: params

    with {:ok, %{"items" => items} = body} when is_list(items) <-
           request("playlistItems", params, key, options) do
      count = count + length(items)
      tracks = tracks ++ Enum.flat_map(items, &track/1)
      next = body["nextPageToken"]

      cond do
        count > @limit ->
          {:error, :too_large}

        is_nil(next) || next == "" ->
          {:ok, tracks}

        count >= @limit ->
          {:error, :too_large}

        !is_binary(next) || MapSet.member?(seen, next) || MapSet.size(seen) >= 3 ->
          {:error, :invalid_response}

        true ->
          pages(id, key, options, next, tracks, MapSet.put(seen, next), count)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp track(%{"snippet" => %{"title" => title, "resourceId" => %{"videoId" => id}}})
       when is_binary(title) and is_binary(id) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{11}\z/, id) && String.trim(title) != "" &&
         title not in ["Private video", "Deleted video"],
       do: [%{youtube_id: id, title: String.slice(title, 0, 500)}],
       else: []
  end

  defp track(_), do: []

  defp request(path, params, key, options) do
    options =
      [
        url: "https://www.googleapis.com/youtube/v3/#{path}",
        params: params,
        headers: [{"x-goog-api-key", key}, {"accept", "application/json"}],
        finch: [conn_opts: [timeout: 2_000], pool_timeout: 2_000],
        receive_timeout: 3_000,
        request_timeout: 5_000,
        retry: false,
        redirect: false
      ]
      |> Keyword.merge(Application.get_env(:queue_party, :youtube_playlist_request_options, []))
      |> Keyword.merge(options)

    case Req.get(options) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 403}} -> {:error, :api_access}
      {:ok, %{status: 429}} -> {:error, :api_access}
      {:ok, %{status: 404}} -> {:error, :not_public}
      _ -> {:error, :unavailable}
    end
  end
end
