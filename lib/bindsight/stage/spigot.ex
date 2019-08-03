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

defmodule BindSight.Stage.Spigot do
  use GenServer

  def tap(camera), do: name(:snapsource, camera)

  def start_link(camera \\ :test) do
    children = [
      {BindSight.Stage.SnapSource, [camera: camera,
                                    name: name(:snapsource, camera)]}
    ]

    Supervisor.start_link(children, strategy: :rest_for_one)
  end

  defp name(mod, cam), do: "#{mod}:#{cam}" |> String.to_atom

  def init(camera), do: tap(camera).init(camera)

end