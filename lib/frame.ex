defmodule SocketCan.Frame do
  defstruct [:id, :data, :dlc]

  def parse(raw) when is_binary(raw) do
    <<id::size(32)-little, dlc::size(8), _pad::size(24), data::binary-size(8)>> = raw

    %__MODULE__{id: id, data: data, dlc: dlc}
  end

  def to_binary(%__MODULE__{id: id, data: data, dlc: dlc}) when is_binary(data) do
    <<id::size(32)-little, dlc::size(8), 0::size(24), data::binary-size(8)>>
  end
end
