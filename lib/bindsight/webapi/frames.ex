####
## Copyright © 2019 Beads Land-Trujillo.
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License for more details.
##
## You should have received a copy of the GNU Affero General Public License
## along with this program.  If not, see <https://www.gnu.org/licenses/>.
####

defmodule BindSight.WebAPI.Frames do
  @moduledoc "Plug to deliver snapshots and streams to client."

  import Plug.Conn

  alias BindSight.Stage.Spew.Spigot
  alias BindSight.Stage.SpewSupervisor

  @defaults %{camera: :test, action: :snapshot}
  @boundary "SNAP-HACKLE-STOP"

  def send(conn, opts) do
    %{camera: camera, action: action} = Enum.into(opts, @defaults)

    case action do
      :snapshot -> send_snapshot(camera, conn)
      :stream -> send_stream(camera, conn)
    end
  end

  defp send_snapshot(camera, conn) do
    [frame | _] = camera |> get_stream |> Enum.take(1)

    conn
    |> put_resp_content_type("image/jpeg")
    |> send_resp(200, frame)
  end

  defp send_stream(camera, conn) do
    stream = get_stream(camera)

    contype = "multipart/x-mixed-replace; boundary=#{@boundary}"

    # Set protocol options for this connection, rather than globally.
    req = elem(conn.adapter, 1)
    opts = %{idle_timeout: :infinity, chunked: false}
    Kernel.send(req.pid, {{req.pid, req.streamid}, {:set_options, opts}})

    # Don't use put_resp_content_type(), as it appends an unnecessary charset
    # part. This is irrelevant for multipart, and breaks some browsers (namely,
    # Safari), which incorrectly implement RFC 1341(7.2.1), and the semicolon
    # and all that follows as part of the boundary string.
    conn =
      conn
      |> put_resp_header("connection", "close")
      |> put_resp_header("content-type", contype)
      |> send_chunked(200)

    stream
    |> Stream.transform(conn, fn frame, conn ->
      {[true], send_frame(conn, frame)}
    end)
    |> Stream.run()
  end

  defp send_frame(conn, frame) do
    time = System.system_time(:second)
    len = byte_size(frame)

    headers =
      [
        "--#{@boundary}",
        "Content-Type: image/jpeg",
        "Content-Length: #{len}",
        "X-Timestamp: #{time}",
        "\r\n"
      ]
      |> Enum.join("\r\n")

    {:ok, conn} = chunk(conn, headers)
    {:ok, conn} = chunk(conn, frame)
    {:ok, conn} = chunk(conn, "\r\n")
    conn
  end

  defp get_stream(camera) do
    camera = camera |> String.to_existing_atom()
    session = SpewSupervisor.start_session(camera: camera)

    [{Spigot.tap(session), mad_demand: 1}] |> GenStage.stream()
  end
end
