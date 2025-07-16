defmodule MqttApp.Timer do
  use GenServer
  
  @spec start_link(non_neg_integer, GenServer.options) :: GenServer.on_start
  def start_link(duration, opts \\ []) do
    GenServer.start_link(__MODULE__, duration, opts)
  end

  @spec init(non_neg_integer) :: {:ok, reference}
  def init(duration) do
    ref = Process.send_after(self(), :timeout, duration)
    {:ok, ref}
  end

  def handle_cast({:reset, duration}, ref) do
    Process.cancel_timer(ref)
    new_ref = Process.send_after(self(), :timeout, duration)
    {:noreply, new_ref}
  end

  def handle_info(:timeout, _ref) do
    raise "timeout exceeded"
  end

  def reset(pid, duration) do
    GenServer.cast(pid, {:reset, duration})
  end
end

defmodule MqttApp.Client.Will do
  defstruct [:will_properties, :will_topic, :will_payload, :will_qos, :will_retain]
  @type t :: %__MODULE__{will_properties: map, will_topic: String.t, will_payload: binary, will_qos: non_neg_integer, will_retain: 0 | 1}
end

defmodule MqttApp.Client.PacketQueue do
  alias MqttApp.Protocol.Flags
  defstruct [:packet_identifier, :flags, :variable, :properties, :payload]
  @type t :: %__MODULE__{packet_identifier: non_neg_integer, flags: Flags.t, variable: any, properties: map, payload: any}
end

defmodule MqttApp.Client.State do
  defstruct [
    :client_identifier, 
    :keep_alive, 
    :session_expiry_interval, 
    :receive_maximum, 
    :maximum_packet_size, 
    :topic_alias_maximum, 
    :connack_wait_timer, 
    :server_receive_maximum, 
    :server_maximum_packet_size,
    :server_topic_alias_maximum,
    :maximum_qos,
    :retain_available,
    :wildcard_subscription_available, 
    :subscription_identifiers_available, 
    :shared_subscription_available, 
    next_packet_id: 0,
    send_queue: [],
    receive_queue: [],
  ]
end


defmodule MqttApp.Client do
  alias MqttApp.Client
  alias MqttApp.Client.Will
  use Agent

  @type options :: 
    {:connack_wait_time, non_neg_integer} 
    | {:clean_start, 0 | 1} 
    | {:will, Will.t} 
    | {:username, String.t} 
    | {:password, binary} 
    | {:keep_alive, non_neg_integer}
    | {:session_expiry_interval, non_neg_integer}
    | {:receive_maximum, non_neg_integer}
    | {:maximum_packet_size, non_neg_integer}
    | {:topic_alias_maximum, non_neg_integer}
    | {:request_response_information, 0 | 1}
    | {:request_problem_information, 0 | 1}
    | {:user, String.t}
    | {:authentication_method, String.t}
    | {:authentication_data, binary}
    | {:client_identifier, String.t}

  def start_link(mod, host, port \\ 1883, options \\ []) do
    {:ok, agent} = Agent.start_link(fn -> %Client.State{} end)
    {:ok, socket} = :gen_tcp.connect(host, port, [])
    {:ok, tx} = Client.Tx.start_link(socket, agent, options, [])
    Client.Rx.start_link(mod, socket, agent, tx)
    {:ok, tx}
  end
end
