defmodule SocketCan.Frame do
  defstruct [:id, :data, :timestamp]

  def to_message(%__MODULE__{id: id, data: nil}), do: "#{Integer.to_string(id, 16)} 0"

  def to_message(%__MODULE__{id: id, data: data}) when is_binary(data) do
    id_string = Integer.to_string(id, 16)
    dlc = byte_size(data)

    data_string =
      data
      |> :erlang.binary_to_list()
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.join(" ")

    "#{id_string} #{dlc} #{data_string}"
  end
end
