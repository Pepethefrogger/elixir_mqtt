defmodule MqttApp.Client.Rx do
  alias MqttApp.Client.PacketQueue
  alias MqttApp.Protocol.ReasonCodes
  alias MqttApp.Protocol.Variable
  alias MqttApp.Protocol.Flags
  import MqttApp.Utils
  use Task

  def start_link(mod, socket, agent, tx) do
    Task.start_link(__MODULE__, :loop, [mod, socket, agent, tx])
  end

  @callback handle_packet(agent:: pid(), opcode :: atom(), fixed_flags :: Flags.t(), variable_header :: any(), properties :: map(), payload :: any()) :: :ok

  @callback on_connection(agent:: pid(), tx:: pid()) :: :ok
  @callback on_error({:connect, reason_code:: atom, reason_string:: String.t, server_reference:: String.t} | {:publish, reason_code:: atom, packet_identifier:: non_neg_integer}) :: :ok

  @optional_callbacks :on_error

  def loop(mod, socket, agent, tx, connack_received \\ false) do
    {opcode, fixed_flags, variable_header, properties, payload} = MqttApp.Protocol.Read.parse_packet(socket)
    case opcode do
      :publish -> mod.handle_packet(agent, opcode, fixed_flags, variable_header, properties, payload)
      _ -> handle_packet(mod, tx, agent, opcode, fixed_flags, variable_header, properties, payload)
    end
    loop(mod, socket, agent, tx, connack_received)
  end

  def handle_packet(mod, _tx, agent, :connack, nil, 
    %Variable.Connack{session_present: _session_present, connack_reason_code: connack_reason_code},
    properties, _payload) do
      # TODO: clean session if session_present is set
      if ReasonCodes.atom_to_reason_code(connack_reason_code) > 0 do
        if Module.defines?(mod, {:on_error, 3}) do
          mod.on_error({:connect, connack_reason_code, properties[:reason_string], properties[:server_reference]})
          exit(:normal)
        else
          raise "recieved connack: #{connack_reason_code}"
        end
      end
      # TODO: don't ignore user property?
      Agent.update(agent, fn state ->
        state 
          |> put_if_not_nil(:session_expiry_interval, properties[:session_expiry_interval])
          |> put_if_not_nil(:server_receive_maximum, properties[:receive_maximum])
          |> put_if_not_nil(:maximum_qos, properties[:maximum_qos])
          |> put_if_not_nil(:retain_available, properties[:retain_available])
          |> put_if_not_nil(:server_maximum_packet_size, properties[:maximum_packet_size])
          |> put_if_not_nil(:client_identifier, properties[:assigned_client_identifier])
          |> put_if_not_nil(:user_property, properties[:user_property])
          |> put_if_not_nil(:server_topic_alias_maximum, properties[:topic_alias_maximum])
          |> put_if_not_nil(:wildcard_subscription_available, properties[:wildcard_subscription_available])
          |> put_if_not_nil(:subscription_identifiers_available, properties[:subscription_identifiers_available])
          |> put_if_not_nil(:shared_subscription_available, properties[:shared_subscription_available])
          |> put_if_not_nil(:server_keep_alive, properties[:server_keep_alive])
          |> put_if_not_nil(:response_information, properties[:response_information])
          |> put_if_not_nil(:authentication_method, properties[:authentication_method])
          |> put_if_not_nil(:authentication_data, properties[:autentication_data])
      end)
  end

  def handle_packet(mod, _tx, agent, :puback, nil, %Variable.Puback{puback_reason_code: puback_reason_code, packet_identifier: packet_identifier}, properties, _payload) do
    Agent.update(agent, fn state ->
      new_queue = state.send_queue |> Enum.map(fn %PacketQueue{packet_identifier: queued_id} ->
        packet_identifier != queued_id
      end)
      %{state | send_queue: new_queue}
    end)
    if puback_reason_code != :success do
      mod.on_error({:publish, packet_identifier, puback_reason_code, properties[:reason_string]})
    end
  end

  def handle_packet(mod, tx, agent, :pubrec, nil, %Variable.Puback{packet_identifier: packet_identifier})
end

