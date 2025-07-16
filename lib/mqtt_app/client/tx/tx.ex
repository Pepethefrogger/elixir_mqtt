defmodule MqttApp.Client.Tx do
  alias MqttApp.Protocol.Payload
  alias MqttApp.Protocol.Variable
  alias MqttApp.Protocol.Flags
  alias MqttApp.Timer
  alias MqttApp.Client.Will
  alias MqttApp.Client
  alias MqttApp.Client.PacketQueue
  import MqttApp.Utils
  use GenServer

  def start_link(socket, agent, opts, gen_server_opts) do
    GenServer.start_link(__MODULE__, {socket, agent, opts}, gen_server_opts)
  end

  def init({socket, agent, opts}) do
    start_client(socket, agent, opts)
    {:ok, {agent, socket}}
  end

  def start_client(socket, agent,
    connack_wait_time: connack_wait_time,
    clean_start: clean_start,
    will: will, 
    username: username, 
    password: password, 
    keep_alive: keep_alive, 
    session_expiry_interval: session_expiry_interval, 
    receive_maximum: receive_maximum,
    maximum_packet_size: maximum_packet_size,
    topic_alias_maximum: topic_alias_maximum,
    request_response_information: request_response_information,
    request_problem_information: request_problem_information,
    user: user,
    authentication_method: authentication_method,
    authentication_data: authentication_data,
    client_identifier: client_identifier
  ) do
    connack_wait_time = connack_wait_time || 60 # Default: wait 60 seconds to recieve connack
    {:ok, connack_wait_timer} = Timer.start_link(connack_wait_time * 1000)

    clean_start = clean_start || 0
    keep_alive = keep_alive || 0
    client_identifier = client_identifier || random_client_identifier()
    session_expiry_interval = session_expiry_interval || 0
    receive_maximum = receive_maximum || 0
    maximum_packet_size = maximum_packet_size || 0
    topic_alias_maximum = topic_alias_maximum || 0
    if is_nil(username) && !is_nil(password) do
      raise "provided password without providing username"
    end
    variable = %MqttApp.Protocol.Variable.Connect{clean_start: clean_start, keep_alive: keep_alive, user_name_flag: !is_nil(username), password_flag: !is_nil(password)}
      |> maybe_add_will(will)

    properties = %{}
      |> put_if_not_nil(:session_expiry_interval, session_expiry_interval)
      |> put_if_not_nil(:receive_maximum, receive_maximum)
      |> put_if_not_nil(:maximum_packet_size, maximum_packet_size)
      |> put_if_not_nil(:topic_alias_maximum, topic_alias_maximum)
      |> put_if_not_nil(:request_response_information, request_response_information)
      |> put_if_not_nil(:request_problem_information, request_problem_information)
      |> put_if_not_nil(:user, user)
      |> put_if_not_nil(:authentication_method, authentication_method)
      |> put_if_not_nil(:authentication_data, authentication_data)

    payload = %MqttApp.Protocol.Payload.Connect{
      client_identifier: client_identifier, 
      will_topic: will.will_topic,
      will_properties: will.will_properties,
      will_payload: will.will_payload,
    }
    MqttApp.Protocol.Write.write_packet(socket, :connect, nil, variable, properties, payload)

    client_state = %Client.State{
      client_identifier: client_identifier,
      keep_alive: keep_alive,
      session_expiry_interval: session_expiry_interval,
      receive_maximum: receive_maximum,
      maximum_packet_size: maximum_packet_size,
      topic_alias_maximum: topic_alias_maximum,
      connack_wait_timer: connack_wait_timer
    }

    Agent.update(agent, fn -> client_state end)
  end

  def subscribe(agent)

  def publish(agent, socket, data, qos, retain, topic_name,
    # TODO: implement timers for resending
    payload_format: payload_format_indicator,
    message_expiry_interval: message_expiry_interval,
    topic_alias: topic_alias,
    response_topic: response_topic,
    correlation_data: correlation_data,
    user_property: user_property,
    content_type: content_type
  ) do
    flags = %Flags{dup: 0, qos: qos, retain: retain}
    variable = %Variable.Publish{
      topic_name: topic_name,
    }
    properties = %{}
      |> put_if_not_nil(:payload_format_indicator, payload_format_indicator)
      |> put_if_not_nil(:message_expiry_interval, message_expiry_interval)
      |> put_if_not_nil(:topic_alias, topic_alias)
      |> put_if_not_nil(:response_topic, response_topic)
      |> put_if_not_nil(:correlation_data, correlation_data)
      |> put_if_not_nil(:user_property, user_property)
      |> put_if_not_nil(:content_type, content_type)
    payload = %Payload.Publish{payload: data}

    MqttApp.Protocol.Write.write_packet(socket, :publish, flags, variable, properties, payload)
    Agent.update(agent, fn state -> 
      %{state | 
        send_queue: state.send_queue ++ [%PacketQueue{packet_identifier: state.next_packet_id, flags: flags, variable: variable, properties: properties, payload: payload}],
        next_packet_id: rem(state.next_packet_id + 1, 65535)
      }
    end)
  end

  defp maybe_add_will(variable, nil) do
      %{ variable | will_flag: 0, will_retain: 0, will_qos: 0 }
  end
  defp maybe_add_will(variable, %Will{will_qos: will_qos, will_retain: will_retain}) do
    %{variable | will_flag: 1, will_retain: will_retain, will_qos: will_qos}
  end

  defp random_client_identifier() do
    :crypto.strong_rand_bytes(10) |> Base.encode16(case: :lower)
  end

end
