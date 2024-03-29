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

defmodule BindSight do
  @moduledoc "Concurrent frame-scrubbing webcam broadcast gateway daemon."

  alias BindSight.Common.Library

  def start(_type, _args) do
    run_profiler()

    Port.open({:spawn, "epmd -daemon"}, [:binary])
    {:ok, hostname} = :inet.gethostname()

    {:ok, _pid} =
      [String.to_atom("bindsight@#{hostname}")]
      |> :net_kernel.start()

    children = [
      {Registry, keys: :unique, name: Registry.BindSight},
      BindSight.Stage.SloshSupervisor,
      BindSight.Stage.SlurpSupervisor,
      BindSight.WebAPI.Server,
      BindSight.Stage.SpewCounter,
      BindSight.Stage.SpewSupervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, restart: :permanent)
  end

  defp run_profiler do
    if Library.get_env(:run_profiler) do
      :fprof.trace([:start, verbose: true, procs: :all])

      spawn(fn ->
        :timer.sleep(10_000)
        :fprof.trace(:stop)
        :fprof.profile()
        :fprof.analyse(totals: false, dest: 'prof.analysis')
      end)
    end
  end
end
