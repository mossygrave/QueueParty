defmodule QueueParty.YouTube do
  @moduledoc "Validates YouTube links and extracts their video IDs."

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
