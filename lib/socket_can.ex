defmodule SocketCan do
  @moduledoc """
  Documentation for `SocketCan`.
  """

  use GenServer

  @pf_can 29
  @can_raw 1

  ########## PUBLIC API ##########

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, SocketCan)
    config = Application.get_env(:socket_can, name)

    bitrate = Keyword.get(config, :bitrate, 125_000)
    device = Keyword.get(config, :device, "can0")

    state = %{bitrate: bitrate, device: device, socket: nil, subscribers: []}
    GenServer.start_link(__MODULE__, state, opts)
  end

  def subscribe(pid, message_filter) do
    GenServer.call(pid, {:subscribe, message_filter})
  end

  def write(pid, can_frame) do
    frame_raw = SocketCan.Frame.to_binary(can_frame)
    GenServer.cast(pid, {:write, frame_raw})
  end

  ########## SERVER API ##########

  def init(%{device: device} = state) do
    {:ok, socket} = :socket.open(@pf_can, :raw, @can_raw)
    addr = get_addr(socket, device)
    :ok = :socket.bind(socket, addr)

    recv_loop()

    {:ok, %{state | socket: socket}}
  end

  def handle_call({:subscribe, filter}, {from, _tag}, state) do
    subscriber_state = %{
      filter: filter,
      pid: from
    }

    state = Map.update(state, :subscribers, [], &[subscriber_state | &1])
    {:reply, :ok, state}
  end

  def handle_cast({:write, can_frame}, %{socket: socket} = state) when is_binary(can_frame) do
    :ok = :socket.send(socket, can_frame)
    {:noreply, state}
  end

  def handle_info(:recv, %{socket: socket} = state) do
    socket
    |> :socket.recv([], 0)
    |> do_receive(state)
  end

  defp do_receive({:ok, can_data}, state) do
    can_frame = SocketCan.Frame.parse(can_data)

    state =
      state
      |> Map.get(:subscribers, [])
      |> Enum.filter(fn {_filter, pid, _rate_limit} -> Process.alive?(pid) end)
      |> Enum.map(&notify_subscribers(&1, can_frame))
      |> then(&Map.put(state, :subscribers, &1))

    recv_loop()

    {:noreply, state}
  end

  defp do_receive({:error, :timeout}, state) do
    recv_loop()
    {:noreply, state}
  end

  defp notify_subscribers(
         %{filter: filter, pid: pid} = subscriber,
         %SocketCan.Frame{id: id} = frame
       ) do
    if filter.(id) do
      send(pid, {:can_frame, frame})
      # TODO: add rate limiting
    end

    subscriber
  end

  defp recv_loop(), do: send(self(), :recv)

  defp get_addr(socket, device) do
    {:ok, _ifindex} = :socket.ioctl(socket, :gifindex, String.to_charlist(device))

    # temp hack to bind on all interfaces
    ifindex = 0

    %{
      :family => @pf_can,
      :addr =>
        <<@pf_can::size(16)-little, 0::size(16)-little, ifindex::size(32)-little, 0::size(32),
          0::size(32), 0::size(64)>>
    }
  end
end
