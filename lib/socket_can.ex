defmodule SocketCan do
  @moduledoc """
  Documentation for `SocketCan`.
  """

  use GenServer
  require Logger
  alias SocketCan.Frame

  @init_state %{socket: nil, device: nil, open: false, subscribers: []}
  @frame_regex ~r/< frame (\d+) (\d+\.\d+) ([A-F0-9\s]+) >/

  def start_link(args \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def send(pid, %Frame{} = frame), do: GenServer.cast(pid, {:send, frame})

  def subscribe(pid, ids), do: GenServer.call(pid, {:subscribe, ids})

  def init(user_args) do
    args =
      :socket_can
      |> Application.get_env(SocketCan, [])
      |> Keyword.merge(user_args, fn _key, _default_arg, user_arg -> user_arg end)

    address = Keyword.fetch!(args, :address)
    port = Keyword.fetch!(args, :port)
    device = Keyword.fetch!(args, :device)

    {:ok, socket} = :gen_tcp.connect(String.to_charlist(address), port, [])

    state =
      @init_state
      |> Map.put(:socket, socket)
      |> Map.put(:device, device)

    {:ok, state}
  end

  def handle_cast({:send, %Frame{} = frame}, %{socket: socket} = state) do
    :ok = :gen_tcp.send(socket, ~c"< send #{Frame.to_message(frame)} >")

    {:noreply, state}
  end

  def handle_call({:subscribe, ids}, {from, _}, %{socket: socket} = state) do
    Enum.each(ids, fn id ->
      :gen_tcp.send(socket, ~c"< subscribe 0 1000 #{Integer.to_string(id, 16)} >")
    end)

    state = Map.update(state, :subscribers, [], fn subscribers -> [from | subscribers] end)

    {:reply, :ok, state}
  end

  def handle_info({:tcp, _port, message}, state) do
    state =
      "#{message}"
      |> parse_message(state)

    {:noreply, state}
  end

  defp parse_message("< hi >", state) do
    %{socket: socket, device: device} = state

    Logger.info("Opening SocketCAN device #{device}")
    :ok = :gen_tcp.send(socket, ~c"< open #{device} >")

    %{state | open: true}
  end

  defp parse_message("< ok >", state), do: state

  defp parse_message(frame_data, state) do
    state =
      Map.update(state, :subscribers, [], &Enum.filter(&1, fn pid -> Process.alive?(pid) end))

    Regex.scan(@frame_regex, frame_data)
    |> Enum.map(fn [_full_message, id_string, timestamp_string, data_string] ->
      id = String.to_integer(id_string, 16)

      timestamp =
        timestamp_string
        |> String.to_float()
        |> then(fn timestamp -> round(timestamp * 1_000_000) end)
        |> DateTime.from_unix!(:microsecond)

      data =
        data_string
        |> String.split()
        |> Enum.map(&String.to_integer(&1, 16))
        |> :erlang.list_to_binary()

      frame = %Frame{id: id, timestamp: timestamp, data: data}

      Map.get(state, :subscribers)
      |> Enum.each(fn pid -> Kernel.send(pid, {:can_frame, frame}) end)
    end)

    state
  end
end
