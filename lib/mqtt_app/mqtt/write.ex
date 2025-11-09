defmodule MqttApp.Protocol.Write do
  alias MqttApp.Protocol.Payload
  alias MqttApp.Protocol.Flags
  alias MqttApp.Utils
  alias MqttApp.Protocol.Variable
  alias MqttApp.Protocol.Opcodes
  alias MqttApp.Protocol.ReasonCodes
  require Logger

  @spec write_fixed_header(opcode :: atom, flags :: Flags.t(), length :: integer) :: binary
  def write_fixed_header(opcode, flags, length) do
    opcode_num = Opcodes.atom_to_opcode(opcode)

    flags =
      case opcode do
        :reserved ->
          raise "reserved opcode"

        :publish ->
          %Flags{dup: dup, qos: qos, retain: retain} = flags
          <<dup::1, qos::2, retain::1>>

        other when other in [:pubrel, :subscribe, :unsubscribe] ->
          <<0::1, 0::1, 1::1, 0::1>>

        _ ->
          <<0::4>>
      end

    <<opcode_num::4, flags::bitstring, Utils.encode_variable_length(length)::binary>>
  end

  @spec write_variable(values :: any) :: binary
  def write_variable(nil), do: <<>>

  def write_variable(%Variable.Connect{
        protocol_version: protocol_version,
        user_name_flag: user_name_flag,
        password_flag: password_flag,
        will_retain: will_retain,
        will_qos: will_qos,
        will_flag: will_flag,
        clean_start: clean_start,
        keep_alive: keep_alive
      }) do
    <<4::16, "MQTT", protocol_version, user_name_flag::1, password_flag::1, will_retain::1,
      will_qos::2, will_flag::1, clean_start::1, 0::1, keep_alive::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Connack{
        session_present: session_present,
        connack_reason_code: connack_reason_code
      }) do
    <<0::7, session_present::1, ReasonCodes.atom_to_reason_code(connack_reason_code)>>
  end

  def write_variable(%Variable.Publish{
        topic_name: topic_name,
        packet_identifier: packet_identifier
      })
      when is_nil(packet_identifier) do
    Utils.encode_utf8(topic_name)
  end

  def write_variable(%Variable.Publish{
        topic_name: topic_name,
        packet_identifier: packet_identifier
      }) do
    <<Utils.encode_utf8(topic_name)::binary, packet_identifier::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Puback{
        packet_identifier: packet_identifier,
        puback_reason_code: puback_reason_code
      }) do
    <<packet_identifier::size(2)-unit(8), ReasonCodes.atom_to_reason_code(puback_reason_code)>>
  end

  def write_variable(%Variable.Pubrec{
        packet_identifier: packet_identifier,
        pubrec_reason_code: pubrec_reason_code
      }) do
    <<packet_identifier::size(2)-unit(8), ReasonCodes.atom_to_reason_code(pubrec_reason_code)>>
  end

  def write_variable(%Variable.Pubrel{
        packet_identifier: packet_identifier,
        pubrel_reason_code: pubrel_reason_code
      }) do
    <<packet_identifier::size(2)-unit(8), ReasonCodes.atom_to_reason_code(pubrel_reason_code)>>
  end

  def write_variable(%Variable.Pubcomp{
        packet_identifier: packet_identifier,
        pubcomp_reason_code: pubcomp_reason_code
      }) do
    <<packet_identifier::size(2)-unit(8), ReasonCodes.atom_to_reason_code(pubcomp_reason_code)>>
  end

  def write_variable(%Variable.Subscribe{packet_identifier: packet_identifier}) do
    <<packet_identifier::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Suback{packet_identifier: packet_identifier}) do
    <<packet_identifier::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Unsubscribe{packet_identifier: packet_identifier}) do
    <<packet_identifier::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Unsuback{packet_identifier: packet_identifier}) do
    <<packet_identifier::size(2)-unit(8)>>
  end

  def write_variable(%Variable.Disconnect{disconnect_reason_code: disconnect_reason_code}) do
    <<ReasonCodes.atom_to_reason_code(disconnect_reason_code)>>
  end

  def write_variable(%Variable.Auth{auth_reason_code: auth_reason_code}) do
    <<ReasonCodes.atom_to_reason_code(auth_reason_code)>>
  end

  @spec write_properties(opcode :: atom, properties :: map) :: binary
  def write_properties(_, nil), do: Utils.encode_variable_length(0)

  def write_properties(opcode, props) do
    properties =
      Enum.reduce(props, <<>>, fn {k, v}, acc ->
        <<acc::binary, write_property(opcode, k, v)::binary>>
      end)

    property_length = properties |> byte_size |> Utils.encode_variable_length()
    property_length <> properties
  end

  @spec write_property(opcode :: atom, property :: atom, value :: any) :: binary
  defp write_property(opcode, :payload_format_indicator, value)
       when opcode in [:publish, :will] do
    <<1, value>>
  end

  defp write_property(opcode, :message_expiry_interval, value) when opcode in [:publish, :will] do
    <<2, value::size(4)-unit(8)>>
  end

  defp write_property(opcode, :content_type, value) when opcode in [:publish, :will] do
    <<3, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :response_topic, value) when opcode in [:publish, :will] do
    <<8, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :correlation_data, value) when opcode in [:publish, :will] do
    <<9, Utils.encode_binary(value)::binary>>
  end

  defp write_property(opcode, :subscription_identifier, value)
       when opcode in [:publish, :subscribe] do
    Enum.reduce(value, <<>>, fn identifier, acc ->
      <<acc::binary, 11, Utils.encode_variable_length(identifier)::binary>>
    end)
  end

  defp write_property(opcode, :session_expiry_interval, value)
       when opcode in [:connect, :connack, :disconnect] do
    <<17, value::size(4)-unit(8)>>
  end

  defp write_property(:connack, :assigned_client_identifier, value) do
    <<18, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(:connack, :server_keep_alive, value) do
    <<19, value::size(2)-unit(8)>>
  end

  defp write_property(opcode, :authentication_method, value)
       when opcode in [:connect, :connack, :auth] do
    <<21, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :authentication_data, value)
       when opcode in [:connect, :connack, :auth] do
    <<22, Utils.encode_binary(value)::binary>>
  end

  defp write_property(:connect, :request_problem_information, value) do
    <<23, value>>
  end

  defp write_property(:will, :will_delay_interval, value) do
    <<24, value::size(4)-unit(8)>>
  end

  defp write_property(:connect, :request_response_information, value) do
    <<25, value>>
  end

  defp write_property(:connack, :response_information, value) do
    <<26, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :server_reference, value) when opcode in [:connack, :disconnect] do
    <<28, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :reason_string, value)
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
    <<31, Utils.encode_utf8(value)::binary>>
  end

  defp write_property(opcode, :receive_maximum, value) when opcode in [:connect, :connack] do
    <<33, value::size(2)-unit(8)>>
  end

  defp write_property(opcode, :topic_alias_maximum, value) when opcode in [:connect, :connack] do
    <<34, value::size(2)-unit(8)>>
  end

  defp write_property(:publish, :topic_alias, value) do
    <<35, value::size(2)-unit(8)>>
  end

  defp write_property(:connack, :maximum_qos, value) do
    <<36, value>>
  end

  defp write_property(:connack, :retain_available, value) do
    <<37, value>>
  end

  defp write_property(opcode, :user_property, value)
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
    Enum.reduce(value, <<>>, fn {string1, string2}, acc ->
      <<acc::binary, 38, Utils.encode_utf8(to_string(string1))::binary,
        Utils.encode_utf8(string2)::binary>>
    end)
  end

  defp write_property(opcode, :maximum_packet_size, value) when opcode in [:connect, :connack] do
    <<39, value::size(4)-unit(8)>>
  end

  defp write_property(:connack, :wildcard_subscription_available, value) do
    <<40, value>>
  end

  defp write_property(:connack, :subscription_identifier_available, value) do
    <<41, value>>
  end

  defp write_property(:connack, :shared_subscription_available, value) do
    <<42, value>>
  end

  @spec write_payload(any) :: binary
  def write_payload(nil), do: <<>>

  def write_payload(%Payload.Connect{} = payload) do
    Enum.reduce(
      [:client_identifier, :will_properties, :will_topic, :will_payload, :user_name, :password],
      <<>>,
      fn field, acc ->
        value = Map.get(payload, field)

        if !is_nil(value) do
          case field do
            :client_identifier ->
              <<acc::binary, Utils.encode_utf8(value)::binary>>

            :will_properties ->
              <<acc::binary, write_properties(:connect, value)::binary>>

            :will_topic ->
              <<acc::binary, Utils.encode_utf8(value)::binary>>

            :will_payload ->
              <<acc::binary, Utils.encode_binary(value)::binary>>

            :user_name ->
              <<acc::binary, Utils.encode_utf8(value)::binary>>

            :password ->
              <<acc::binary, Utils.encode_binary(value)::binary>>
          end
        else
          acc
        end
      end
    )
  end

  def write_payload(%Payload.Subscribe{topic_filters: []}) do
    <<>>
  end

  def write_payload(%Payload.Subscribe{
        topic_filters: [
          {topic_filter,
           %Payload.Subscribe.Options{
             retain_handling: retain_handling,
             rap: rap,
             nl: nl,
             qos: qos
           }}
          | topic_filters
        ]
      }) do
    topic_filter = Utils.encode_utf8(topic_filter)
    next_payload = write_payload(%Payload.Subscribe{topic_filters: topic_filters})

    <<topic_filter::binary, 0::2, retain_handling::2, rap::1, nl::1, qos::2,
      next_payload::binary>>
  end

  def write_payload(%Payload.Suback{reason_codes: []}) do
    <<>>
  end

  def write_payload(%Payload.Suback{reason_codes: [reason_code | reason_codes]}) do
    number_code = ReasonCodes.atom_to_reason_code(reason_code)
    <<number_code, write_payload(%Payload.Suback{reason_codes: reason_codes})::binary>>
  end

  def write_payload(%Payload.Unsubscribe{topic_filters: []}) do
    <<>>
  end

  def write_payload(%Payload.Unsubscribe{topic_filters: [topic_filter | topic_filters]}) do
    topic_filter = Utils.encode_utf8(topic_filter)
    next_payload = write_payload(%Payload.Unsubscribe{topic_filters: topic_filters})
    <<topic_filter::binary, next_payload::binary>>
  end

  def write_payload(%Payload.Unsuback{reason_codes: []}) do
    <<>>
  end

  def write_payload(%Payload.Unsuback{reason_codes: [reason_code | reason_codes]}) do
    number_code = ReasonCodes.atom_to_reason_code(reason_code)
    <<number_code, write_payload(%Payload.Unsuback{reason_codes: reason_codes})::binary>>
  end

  def write_payload(%Payload.Publish{payload: payload}) do
    payload || <<>>
  end

  @spec write_packet(MqttApp.Protocol.Packet.t()) :: binary
  def write_packet(%MqttApp.Protocol.Packet{
        opcode: opcode,
        flags: flags,
        variable: variable,
        properties: properties,
        payload: payload
      }) do
    data = write_variable(variable)
    properties = write_properties(opcode, properties)
    data = <<data::binary, properties::binary>>
    payload = write_payload(payload)
    data = <<data::binary, payload::binary>>
    length = byte_size(data)
    fixed = write_fixed_header(opcode, flags, length)
    data = <<fixed::binary, data::binary>>
    data
  end

  @spec write_packet(socket :: :gen_tcp.socket(), packet :: MqttApp.Protocol.Packet.t()) :: :ok
  def write_packet(socket, packet) do
    data = write_packet(packet)
    :ok = :gen_tcp.send(socket, data)
    :ok
  end
end
