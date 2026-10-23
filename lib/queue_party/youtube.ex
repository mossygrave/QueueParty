defmodule QueueParty.YouTube do
  @moduledoc "Validates YouTube links and retrieves public video titles."

  @hosts ~w(youtube.com www.youtube.com m.youtube.com music.youtube.com youtube-nocookie.com www.youtube-nocookie.com)

  def video_id(url) when is_binary(url) do
    uri = url |> String.trim() |> with_scheme() |> URI.parse()
    host = String.downcase(uri.host || "")

    id =
      cond do
        uri.scheme not in ["http", "https"] ->
          nil

        host in ["youtu.be", "www.youtu.be"] ->
          List.first(String.split(uri.path || "", "/", trim: true))

        host in @hosts ->
          from_path(uri.path, uri.query)

        true ->
          nil
      end

    if is_binary(id) && Regex.match?(~r/\A[A-Za-z0-9_-]{11}\z/, id), do: {:ok, id}, else: :error
  rescue
    ArgumentError -> :error
  end

  def video_id(_), do: :error

  @doc "Fetches a public title using YouTube oEmbed, without a YouTube API key."
  def fetch_title(id, options \\ []) do
    if is_binary(id) && Regex.match?(~r/\A[A-Za-z0-9_-]{11}\z/, id) do
      request_options =
        [
          url: "https://www.youtube.com/oembed",
          params: [url: "https://www.youtube.com/watch?v=#{id}", format: "json"],
          headers: [accept: "application/json"],
          receive_timeout: 3_000,
          finch: [conn_opts: [timeout: 2_000], pool_timeout: 2_000],
          request_timeout: 5_000,
          retry: false,
          redirect: false
        ]
        |> Keyword.merge(Application.get_env(:queue_party, :youtube_request_options, []))
        |> Keyword.merge(options)

      case Req.get(request_options) do
        {:ok, %{status: 200, body: %{"title" => title}}} when is_binary(title) ->
          normalize_title(title)

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp normalize_title(title) do
    if String.valid?(title) && String.trim(title) != "" do
      {:ok, title |> String.trim() |> String.slice(0, 500)}
    else
      :error
    end
  end

  defp with_scheme(url) do
    if String.contains?(url, "://"), do: url, else: "https://" <> url
  end

  defp from_path("/watch", query), do: URI.decode_query(query || "")["v"]

  defp from_path(path, _) do
    case String.split(path || "", "/", trim: true) do
      [kind, id] when kind in ["shorts", "embed", "live"] -> id
      _ -> nil
    end
  end
end
