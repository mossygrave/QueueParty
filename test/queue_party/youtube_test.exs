defmodule QueueParty.YouTubeTest do
  use ExUnit.Case, async: true
  alias QueueParty.YouTube

  test "accepts YouTube URL formats, optional scheme, and reordered parameters" do
    for url <- [
          "https://www.youtube.com/watch?si=abc&v=dQw4w9WgXcQ&t=5",
          "https://youtu.be/dQw4w9WgXcQ?si=abc",
          "youtube.com/shorts/dQw4w9WgXcQ",
          "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
          "https://www.youtube.com/embed/dQw4w9WgXcQ",
          "https://youtube.com/live/dQw4w9WgXcQ"
        ] do
      assert YouTube.video_id(url) == {:ok, "dQw4w9WgXcQ"}
    end
  end

  test "rejects lookalike domains, non-HTTP URLs, and invalid IDs" do
    for url <- [
          "https://evil.example/youtube.com/watch?v=dQw4w9WgXcQ",
          "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
          "ftp://youtube.com/watch?v=dQw4w9WgXcQ",
          "https://youtube.com/watch?v=short",
          "https://youtube.com/watch?v=dQw4w9WgXcQextra",
          "",
          nil
        ] do
      assert YouTube.video_id(url) == :error
    end
  end
end
