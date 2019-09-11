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

defmodule BindSight.Stage.Slosh.Digest do
  @moduledoc "Slurp consumer-producer to frames from chunks."

  use GenStage
  require Logger

  alias BindSight.Common.Library

  @defaults %{source: :producer_not_specified, name: __MODULE__}

  defstruct status: nil,
            bound: "Lorem ipsum dolor sit amet",
            boundsize: nil,
            eolex: nil,
            eohex: nil,
            eopre: nil,
            data: [],
            done: false,
            frames: [],
            camera: nil

  # per RFC 1341
  @bcharsnospace "[:alnum:]\\'\\(\\(\\+\\_\\,\\-\\.\\/\\:\\=\\?"

  def start_link(opts \\ []) do
    %{name: name} = Enum.into(opts, @defaults)
    GenStage.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    %{source: source, camera: camera} = Enum.into(opts, @defaults)

    {:producer_consumer, _state = %__MODULE__{camera: camera},
     subscribe_to: [source]}
  end

  def handle_events([head | tail], from, state = %__MODULE__{}) do
    status = state.status
    boundsize = state.boundsize

    case head do
      {:status, _ref, status} ->
        handle_events(tail, from, _state = %{state | status: status})

      {:headers, _ref, hdrs} when status == 200 ->
        handle_headers(hdrs, tail, from, state)

      {:headers, _ref, _hdrs} ->
        [
          "Request failed",
          state.camera |> Atom.to_string(),
          state.status |> Integer.to_string()
        ]
        |> Library.error_chain()
        |> Logger.warn()

        handle_events(tail, from, state)

      {:frame_headers, _ref, hdrs} ->
        frame = state.data |> Enum.reverse() |> Enum.join()
        frames = if frame == "", do: state.frames, else: [frame | state.frames]

        handle_events(tail, from, _state = %{state | frames: frames, data: []})

      {:text, _ref, text} when byte_size(text) > boundsize ->
        handle_text([head | tail], from, state)

      {:text, ref, text} ->
        handle_events([{:data, ref, text} | tail], from, state)

      {:data, _ref, ""} ->
        handle_events(tail, from, state)

      {:data, _ref, data} ->
        handle_events(tail, from, _state = %{state | data: [data | state.data]})

      {:done, _ref} ->
        handle_events(tail, from, _state = %{state | done: true})
    end
  end

  def handle_events([], _from, state = %__MODULE__{}) do
    cond do
      state.done and state.status == 200 ->
        {:noreply, [state.data], _state = %__MODULE__{camera: state.camera}}

      state.done ->
        {:noreply, [], _state = %__MODULE__{camera: state.camera}}

      state.frames ->
        {:noreply, Enum.reverse(state.frames),
         _state = %__MODULE__{state | frames: []}}

      true ->
        {:noreply, [], state}
    end
  end

  defp handle_headers([], events, from, state),
    do: handle_events(events, from, state)

  defp handle_headers([{"content-type", ctype} | tail], events, from, state) do
    {:ok, noquote} = Regex.compile("; *boundary=(?<bound>[#{@bcharsnospace}]+)")

    {:ok, yesquote} =
      Regex.compile("; *boundary=\"(?<bound>[ #{@bcharsnospace}]+)\"")

    cond do
      Regex.match?(noquote, ctype) ->
        handle_bound(noquote, ctype, tail, events, from, state)

      Regex.match?(yesquote, ctype) ->
        handle_bound(yesquote, ctype, tail, events, from, state)

      true ->
        [
          "digest",
          "bad content-type",
          state.camera |> Atom.to_string(),
          ctype
        ]
        |> Library.error_chain()
        |> Logger.warn()

        {:stop, [], state}
    end
  end

  defp handle_headers([_head | tail], events, from, state),
    do: handle_headers(tail, events, from, state)

  defp handle_bound(pattern, ctype, tail, events, from, state) do
    caps = Regex.named_captures(pattern, ctype)

    bound = "--" <> caps["bound"]
    boundsize = byte_size(bound)
    state = %__MODULE__{state | bound: bound, boundsize: boundsize}
    handle_headers(tail, events, from, state)
  end

  defp handle_text([head = {:text, ref, text} | tail], from, state) do
    if String.contains?(text, state.bound) do
      strip_boundary(head, tail, from, state)
    else
      handle_events([{:data, ref, text} | tail], from, state)
    end
  end

  defp strip_boundary({:text, ref, text}, tail, from, state) do
    [pre, post] = String.split(text, state.bound, parts: 2)

    state = if state.eohex == nil, do: determine_eol(text, state), else: state
    pre = Regex.replace(state.eopre, pre, "")

    [headers, post] = Regex.split(state.eohex, post, parts: 2)

    events =
      [{:data, ref, pre}, {:frame_headers, ref, headers}, {:data, ref, post}] ++
        tail

    handle_events(events, from, state)
  end

  defp determine_eol(text, state) do
    [eol] = Regex.run(~r/[\n\r]{1,2}/, text, parts: 1)
    {:ok, eolex} = Regex.compile(eol)
    {:ok, eohex} = Regex.compile(eol <> eol)
    {:ok, eopre} = Regex.compile(eol <> "$")
    %__MODULE__{state | eolex: eolex, eohex: eohex, eopre: eopre}
  end
end
