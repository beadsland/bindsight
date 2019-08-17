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

defmodule BindSight.Common.MintJulep do
  @moduledoc "Poll to obtain MJPEG snapshots as Mint messages."

  require Logger

  alias BindSight.Common.Library

  @doc "Return state for polling camera."
  def sip(uri), do: {uri, connect(uri)}

  defp connect(uri) do
    case mint_connect(uri.scheme |> String.to_atom(), uri.host, uri.port) do
      {:ok, conn} -> request(conn, uri)
      {:error, err} -> try_again(nil, uri, :connect, err)
    end
  end

  # Try ipv6 by default, but fail-over to ipv4 gracefully.
  defp mint_connect(scheme, host, port) do
    opts = [transport_opts: [{:tcp_module, :inet6_tcp}]]

    case Mint.HTTP.connect(scheme, host, port, opts) do
      {:ok, conn} -> {:ok, conn}
      _ -> Mint.HTTP.connect(scheme, host, port, [])
    end
  end

  defp request(conn, uri) do
    case Mint.HTTP.request(conn, "GET", Library.query_path(uri), []) do
      {:ok, conn, _ref} -> conn
      {:error, conn, err} -> try_again(conn, uri, :request, err)
    end
  end

  @doc "Drop and reopen connection on error."
  def try_again(conn, uri, call, err) do
    path = Library.query_path(uri)

    Logger.warn(fn ->
      "Failed #{call}: #{uri.host}:#{uri.port}/#{path}: " <> inspect(err)
    end)

    Mint.HTTP.close(conn)
    Process.sleep(1000)
    connect(uri)
  end
end
