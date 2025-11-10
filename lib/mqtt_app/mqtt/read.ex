defmodule MqttApp.Protocol.Read do
  alias MqttApp.Protocol.Payload
  alias MqttApp.Protocol.Flags
  alias MqttApp.Utils
  alias MqttApp.Protocol.Variable
  alias MqttApp.Protocol.Opcodes
  alias MqttApp.Protocol.ReasonCodes
  import Utils
  require Logger

  @spec parse_fixed_header(flags :: binary) :: {opcode :: atom, flags :: Flags.t()}
  def parse_fixed_header(<<type::4, flags::bitstring-size(4)>>) do
    case {Opcodes.opcode_to_atom(type), flags} do
      {:reserved, _flags} ->
        raise "reserved opcode"

      {:publish, <<dup::1, qos::2, retain::1>>} ->
        {:publish, %Flags{dup: dup, qos: qos, retain: retain}}

      {type, <<0::1, 0::1, 1::1, 0::1>>} when type in [:pubrel, :subscribe, :unsubscribe] ->
        {type, %Flags{}}

      {type, <<0::4>>} ->
        {type, %Flags{}}
    end
  end

  @spec parse_variable(opcode :: atom, data :: binary) :: {values :: any, rest :: binary}
  def parse_variable(:pingreq, data), do: {nil, data}
  def parse_variable(:pingresp, data), do: {nil, data}

  def parse_variable(
        :connect,
        <<4::16, "MQTT", version, username::1, password::1, will_retain::1, will_qos::2,
          will_flag::1, clean_start::1, 0::1, keep_alive::size(2)-unit(8), rest::binary>>
      ) do
    {
      %Variable.Connect{
        protocol_version: version,
        user_name_flag: username,
        password_flag: password,
        will_retain: will_retain,
        will_qos: will_qos,
        will_flag: will_flag,
        clean_start: clean_start,
        keep_alive: keep_alive
      },
      rest
    }
  end

  def parse_variable(:connack, <<0::7, session_present::1, connack_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:connack, connack_reason_code)
    {%Variable.Connack{session_present: session_present, connack_reason_code: reason_code}, rest}
  end

  def parse_variable(:puback, <<packet_identifier::size(16), puback_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:puback, puback_reason_code)

    {%Variable.Puback{packet_identifier: packet_identifier, puback_reason_code: reason_code},
     rest}
  end

  def parse_variable(:pubrec, <<packet_identifier::size(16), pubrec_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:pubrec, pubrec_reason_code)

    {%Variable.Pubrec{packet_identifier: packet_identifier, pubrec_reason_code: reason_code},
     rest}
  end

  def parse_variable(:pubrel, <<packet_identifier::size(16), pubrel_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:pubrel, pubrel_reason_code)

    {%Variable.Pubrel{packet_identifier: packet_identifier, pubrel_reason_code: reason_code},
     rest}
  end

  def parse_variable(:pubcomp, <<packet_identifier::size(16), pubcomp_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:pubcomp, pubcomp_reason_code)

    {%Variable.Pubcomp{packet_identifier: packet_identifier, pubcomp_reason_code: reason_code},
     rest}
  end

  def parse_variable(:subscribe, <<packet_identifier::size(16), rest::binary>>) do
    {%Variable.Subscribe{packet_identifier: packet_identifier}, rest}
  end

  def parse_variable(:suback, <<packet_identifier::size(16), rest::binary>>) do
    {%Variable.Suback{packet_identifier: packet_identifier}, rest}
  end

  def parse_variable(:unsubscribe, <<packet_identifier::size(16), rest::binary>>) do
    {%Variable.Unsubscribe{packet_identifier: packet_identifier}, rest}
  end

  def parse_variable(:unsuback, <<packet_identifier::size(16), rest::binary>>) do
    {%Variable.Unsuback{packet_identifier: packet_identifier}, rest}
  end

  def parse_variable(:disconnect, <<disconnect_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:disconnect, disconnect_reason_code)
    {%Variable.Disconnect{disconnect_reason_code: reason_code}, rest}
  end

  def parse_variable(:auth, <<auth_reason_code, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:auth, auth_reason_code)
    {%Variable.Auth{auth_reason_code: reason_code}, rest}
  end

  @spec parse_variable(opcode :: atom, data :: binary, qos :: integer) ::
          {values :: any, rest :: binary}
  def parse_variable(:publish, data, qos) when qos > 0 do
    {:ok, topic_name, _consumed, rest} = Utils.decode_utf8(data)
    <<packet_identifier::size(16), rest::binary>> = rest
    {%Variable.Publish{topic_name: topic_name, packet_identifier: packet_identifier}, rest}
  end

  def parse_variable(:publish, data, 0) do
    {:ok, topic_name, _consumed, rest} = Utils.decode_utf8(data)
    {%Variable.Publish{topic_name: topic_name}, rest}
  end

  @spec parse_properties(opcode :: atom, binary) :: {map | nil, rest :: binary}
  def parse_properties(opcode, data) do
    {:ok, length, _consumed, rest} = Utils.decode_variable_length(data)

    if length == 0 do
      {nil, rest}
    else
      parse_properties(opcode, rest, Map.new(), length)
    end
  end

  @spec parse_properties(opcode :: atom, data :: binary, map, remaining :: integer) ::
          {map, rest :: binary}
  def parse_properties(_opcode, _data, _map, remaining) when remaining < 0 do
    raise "properties length overrun, remaining: #{remaining}"
  end

  def parse_properties(_opcode, data, map, 0) do
    {map, data}
  end

  def parse_properties(opcode, data, map, remaining) do
    {map, consumed, rest} = parse_property(opcode, map, data)
    parse_properties(opcode, rest, map, remaining - consumed)
  end

  @spec parse_property(opcode :: atom, map :: map, data :: binary) ::
          {map, consumed :: integer, rest :: binary}
  defp parse_property(opcode, map, <<1, data, rest::binary>>) when opcode in [:publish, :will] do
    {put_if_not_exists!(map, :payload_format_indicator, data), 2, rest}
  end

  defp parse_property(opcode, map, <<2, data::size(32), rest::binary>>)
       when opcode in [:publish, :will] do
    {put_if_not_exists!(map, :message_expiry_interval, data), 5, rest}
  end

  defp parse_property(opcode, map, <<3, rest::binary>>) when opcode in [:publish, :will] do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :content_type, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<8, rest::binary>>) when opcode in [:publish, :will] do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :response_topic, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<9, rest::binary>>) when opcode in [:publish, :will] do
    {:ok, data, consumed, rest} = Utils.decode_binary(rest)
    {put_if_not_exists!(map, :correlation_data, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<11, rest::binary>>) when opcode in [:publish, :subscribe] do
    {:ok, data, consumed, rest} = Utils.decode_variable_length(rest)
    {put_append(map, :subscription_identifier, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<17, data::size(32), rest::binary>>)
       when opcode in [:connect, :connack, :disconnect] do
    {put_if_not_exists!(map, :session_expiry_interval, data), 5, rest}
  end

  defp parse_property(:connack, map, <<18, rest::binary>>) do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :assigned_client_identifier, data), 1 + consumed, rest}
  end

  defp parse_property(:connack, map, <<19, data::size(16), rest::binary>>) do
    {put_if_not_exists!(map, :server_keep_alive, data), 3, rest}
  end

  defp parse_property(opcode, map, <<21, rest::binary>>)
       when opcode in [:connect, :connack, :auth] do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :authentication_method, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<22, rest::binary>>)
       when opcode in [:connect, :connack, :auth] do
    {:ok, data, consumed, rest} = Utils.decode_binary(rest)
    {put_if_not_exists!(map, :authentication_data, data), 1 + consumed, rest}
  end

  defp parse_property(:connect, map, <<23, data, rest::binary>>) do
    {put_if_not_exists!(map, :request_problem_information, data), 2, rest}
  end

  defp parse_property(:will, map, <<24, data::size(4)-unit(8), rest::binary>>) do
    {put_if_not_exists!(map, :will_delay_interval, data), 5, rest}
  end

  defp parse_property(:connect, map, <<25, data, rest::binary>>) do
    {put_if_not_exists!(map, :request_response_information, data), 2, rest}
  end

  defp parse_property(:connack, map, <<26, rest::binary>>) do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :response_information, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<28, rest::binary>>) when opcode in [:connack, :disconnect] do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :server_reference, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<31, rest::binary>>)
       when opcode in [
              :connack,
              :puback,
              :pubrec,
              :pubrel,
              :pubcomp,
              :suback,
              :unsuback,
              :disconnect,
              :auth
            ] do
    {:ok, data, consumed, rest} = Utils.decode_utf8(rest)
    {put_if_not_exists!(map, :reason_string, data), 1 + consumed, rest}
  end

  defp parse_property(opcode, map, <<33, data::size(16), rest::binary>>)
       when opcode in [:connect, :connack] do
    {put_if_not_exists!(map, :receive_maximum, data), 3, rest}
  end

  defp parse_property(opcode, map, <<34, data::size(16), rest::binary>>)
       when opcode in [:connect, :connack] do
    {put_if_not_exists!(map, :topic_alias_maximum, data), 3, rest}
  end

  defp parse_property(:publish, map, <<35, data::size(16), rest::binary>>) do
    {put_if_not_exists!(map, :topic_alias, data), 3, rest}
  end

  defp parse_property(:connack, map, <<36, data, rest::binary>>) do
    {put_if_not_exists!(map, :maximum_qos, data), 2, rest}
  end

  defp parse_property(:connack, map, <<37, data, rest::binary>>) do
    {put_if_not_exists!(map, :retain_available, data), 2, rest}
  end

  defp parse_property(opcode, map, <<38, rest::binary>>)
       when opcode in [
              :connect,
              :connack,
              :publish,
              :will,
              :properties,
              :puback,
              :pubrec,
              :pubrel,
              :pubcomp,
              :subscribe,
              :suback,
              :unsubscribe,
              :unsuback,
              :disconnect,
              :auth
            ] do
    {:ok, data1, consumed1, rest} = Utils.decode_utf8(rest)
    {:ok, data2, consumed2, rest} = Utils.decode_utf8(rest)
    length = 1 + consumed1 + consumed2
    {put_append(map, :user_property, {data1, data2}), length, rest}
  end

  defp parse_property(opcode, map, <<39, data::size(32), rest::binary>>)
       when opcode in [:connect, :connack] do
    {put_if_not_exists!(map, :maximum_packet_size, data), 5, rest}
  end

  defp parse_property(:connack, map, <<40, data, rest::binary>>) do
    {put_if_not_exists!(map, :wildcard_subscription_available, data), 2, rest}
  end

  defp parse_property(:connack, map, <<41, data, rest::binary>>) do
    {put_if_not_exists!(map, :subscription_identifier_available, data), 2, rest}
  end

  defp parse_property(:connack, map, <<42, data, rest::binary>>) do
    {put_if_not_exists!(map, :shared_subscription_available, data), 2, rest}
  end

  @spec parse_payload(opcode :: atom, extra :: any, data :: binary) :: values :: any
  def parse_payload(:connect, %Variable.Connect{} = variable_header, data) do
    {:ok, client_identifier, _consumed, rest} = Utils.decode_utf8(data)

    {payload, rest} =
      variable_header
      |> Map.from_struct()
      |> then(fn map ->
        for key <- [:will_properties, :will_flag, :user_name_flag, :password_flag],
            do: {key, Map.get(map, key)}
      end)
      |> Enum.reduce(
        {%Payload.Connect{client_identifier: client_identifier}, rest},
        fn {k, v}, {payload, rest} ->
          if v == 1 do
            case k do
              :will_properties ->
                {will_properties, rest} = parse_properties(:will, rest)
                {%{payload | will_properties: will_properties}, rest}

              :will_flag ->
                {:ok, will_topic, _consumed, rest} = Utils.decode_utf8(rest)
                {:ok, will_payload, _consumed, rest} = Utils.decode_binary(rest)

                {%{
                   payload
                   | will_topic: will_topic,
                     will_payload: will_payload
                 }, rest}

              :user_name_flag ->
                {:ok, user_name, _consumed, rest} = Utils.decode_utf8(rest)
                {%{payload | user_name: user_name}, rest}

              :password_flag ->
                {:ok, password, _consumed, rest} = Utils.decode_binary(rest)
                {%{payload | password: password}, rest}
            end
          else
            {payload, rest}
          end
        end
      )

    <<>> = rest
    payload
  end

  def parse_payload(:subscribe, _, <<>>) do
    %Payload.Subscribe{}
  end

  def parse_payload(:subscribe, extra, rest) do
    {:ok, topic_filter, _consumed, rest} = Utils.decode_utf8(rest)
    <<0::2, retain_handling::2, rap::1, nl::1, qos::2, rest::binary>> = rest

    options = %Payload.Subscribe.Options{
      retain_handling: retain_handling,
      rap: rap,
      nl: nl,
      qos: qos
    }

    %Payload.Subscribe{topic_filters: topic_filters} = parse_payload(:subscribe, extra, rest)
    %Payload.Subscribe{topic_filters: [{topic_filter, options} | topic_filters || []]}
  end

  def parse_payload(:suback, _, <<>>) do
    %Payload.Suback{}
  end

  def parse_payload(:suback, extra, <<reason_number, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:suback, reason_number)
    %Payload.Suback{reason_codes: reason_codes} = parse_payload(:suback, extra, rest)
    %Payload.Suback{reason_codes: [reason_code | reason_codes || []]}
  end

  def parse_payload(:unsubscribe, _, <<>>) do
    %Payload.Unsubscribe{}
  end

  def parse_payload(:unsubscribe, extra, rest) do
    {:ok, topic_filter, _consumed, rest} = Utils.decode_utf8(rest)
    %Payload.Unsubscribe{topic_filters: topic_filters} = parse_payload(:unsubscribe, extra, rest)
    %Payload.Unsubscribe{topic_filters: [topic_filter | topic_filters || []]}
  end

  def parse_payload(:unsuback, _, <<>>) do
    %Payload.Unsuback{}
  end

  def parse_payload(:unsuback, extra, <<reason_number, rest::binary>>) do
    reason_code = ReasonCodes.reason_code_to_atom(:unsuback, reason_number)
    %Payload.Unsuback{reason_codes: reason_codes} = parse_payload(:unsuback, extra, rest)
    %Payload.Unsuback{reason_codes: [reason_code | reason_codes || []]}
  end

  def parse_payload(:publish, _, data), do: %Payload.Publish{payload: data}

  def parse_payload(_, _, <<>>) do
    nil
  end

  @spec parse_packet(data :: binary) :: MqttApp.Protocol.Packet.t()
  def parse_packet(data) do
    <<fixed_header_flags::binary-size(1), rest::binary>> = data
    {:ok, _, _, rest} = Utils.decode_variable_length(rest)
    {opcode, flags} = parse_fixed_header(fixed_header_flags)

    {variable_header, rest} =
      case opcode do
        :publish ->
          %Flags{qos: qos} = flags
          parse_variable(:publish, rest, qos)

        _ ->
          parse_variable(opcode, rest)
      end

    {properties, rest} = parse_properties(opcode, rest)
    payload = parse_payload(opcode, variable_header, rest)
    {opcode, flags, variable_header, properties, payload}

    %MqttApp.Protocol.Packet{
      opcode: opcode,
      flags: flags,
      variable: variable_header,
      properties: properties,
      payload: payload
    }
  end

  @spec read_packet(:gen_tcp.socket()) :: MqttApp.Protocol.Packet.t()
  def read_packet(socket) do
    {:ok, <<fixed_header_flags::binary-size(1), length_byte>>} = :gen_tcp.recv(socket, 2)
    length = take_variable_header(socket, length_byte)
    {:ok, length, _, <<>>} = Utils.decode_variable_length(length)
    {opcode, flags} = parse_fixed_header(fixed_header_flags)
    {:ok, rest} = :gen_tcp.recv(socket, length)

    {variable_header, rest} =
      case opcode do
        :publish ->
          %Flags{qos: qos} = flags
          parse_variable(:publish, rest, qos)

        _ ->
          parse_variable(opcode, rest)
      end

    {properties, rest} = parse_properties(opcode, rest)
    payload = parse_payload(opcode, variable_header, rest)

    %MqttApp.Protocol.Packet{
      opcode: opcode,
      flags: flags,
      variable: variable_header,
      properties: properties,
      payload: payload
    }
  end

  defp take_variable_header(socket, byte, count \\ 1)
  defp take_variable_header(_, _, 5), do: raise("malformed length")

  defp take_variable_header(socket, byte, count) do
    if Bitwise.band(byte, 128) != 0 do
      {:ok, next_byte} = :gen_tcp.recv(socket, 1)
      <<byte, take_variable_header(socket, next_byte, count + 1)::binary>>
    else
      <<>>
    end
  end
end
