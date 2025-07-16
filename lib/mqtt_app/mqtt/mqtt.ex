defmodule MqttApp.Protocol.Flags do
  defstruct [:dup, :qos, :retain]

  @type t :: %__MODULE__{
    dup: non_neg_integer,
    qos: non_neg_integer,
    retain: non_neg_integer
  }
end

defmodule MqttApp.Protocol.Opcodes do
  @opcodes [
    reserved: 0,
    connect: 1,
    connack: 2,
    publish: 3,
    puback: 4,
    pubrec: 5,
    pubrel: 6,
    pubcomp: 7,
    subscribe: 8,
    suback: 9,
    unsubscribe: 10,
    unsuback: 11,
    pingreq: 12,
    pingresp: 13,
    disconnect: 14,
    auth: 15
  ]

  @spec opcode_to_atom(integer) :: atom
  @spec atom_to_opcode(atom) :: integer
  Enum.each(@opcodes, fn {atom, code} ->
    def opcode_to_atom(unquote(code)), do: unquote(atom)
    def atom_to_opcode(unquote(atom)), do: unquote(code)
  end)
end

defmodule MqttApp.Protocol.ReasonCodes do
  require Logger
  @reason_codes [
    success: {0, [:connack, :puback, :pubrec, :pubrel, :pubcomp, :unsuback, :auth]},
    normal_disconnection: {0, [:disconnect]},
    granted_qos_0: {0, [:suback]},
    granted_qos_1: {1, [:suback]},
    granted_qos_2: {2, [:suback]},
    disconnect_with_will_message: {4, [:disconnect]},
    no_matching_subscribers: {16, [:puback, :pubrec]},
    no_subscription_existed: {17, [:unsuback]},
    continue_authentication: {24, [:auth]},
    reauthenticate: {25, [:auth]},
    unspecified_error: {128, [:connack, :puback, :pubrec, :suback, :unsuback, :disconnect]},
    malformed_packet: {129, [:connack, :disconnect]},
    protocol_error: {130, [:connack, :disconnect]},
    implementation_specific_error: {131, [:connack, :puback, :pubrec, :suback, :unsuback, :disconnect]},
    unsupported_protocol_version: {132, [:connack]},
    client_identifier_not_valid: {133, [:connack]},
    bad_user_name_or_password: {134, [:connack]},
    not_authorized: {135, [:connack, :puback, :pubrec, :suback, :unsuback, :disconnect]},
    server_unavailable: {136, [:connack]},
    server_busy: {137, [:connack, :disconnect]},
    banned: {138, [:connack]},
    server_shutting_down: {139, [:disconnect]},
    bad_authentication_method: {140, [:connack, :disconnect]},
    keep_alive_timeout: {141, [:disconnect]},
    session_taken_over: {142, [:disconnect]},
    topic_filter_invalid: {143, [:suback, :unsuback, :disconnect]},
    topic_name_invalid: {144, [:connack, :puback, :pubrec, :disconnect]},
    packet_identifier_in_use: {145, [:puback, :pubrec, :suback, :unsuback]},
    packet_identifier_not_found: {146, [:pubrel, :pubcomp]},
    receive_maximum_exceeded: {147, [:disconnect]},
    topic_alias_invalid: {148, [:disconnect]},
    packet_too_large: {149, [:connack, :disconnect]},
    message_rate_too_high: {150, [:disconnect]},
    quota_exceeded: {151, [:connack, :puback, :pubrec, :suback, :disconnect]},
    administrative_action: {152, [:disconnect]},
    payload_format_invalid: {153, [:connack, :puback, :pubrec, :disconnect]},
    retain_not_supported: {154, [:connack, :disconnect]},
    qos_not_supported: {155, [:connack, :disconnect]},
    use_another_server: {156, [:connack, :disconnect]},
    server_moved: {157, [:connack, :disconnect]},
    shared_subscriptions_not_supported: {158, [:suback, :disconnect]},
    connection_rate_exceeded: {159, [:connack, :disconnect]},
    maximum_connect_time: {160, [:disconnect]},
    subscription_identifiers_not_supported: {161, [:suback, :disconnect]},
    wildcard_subscriptions_not_supported: {162, [:suback, :disconnect]}
  ]

  @spec reason_code_to_atom(opcode:: atom, code:: integer) :: atom
  @spec atom_to_reason_code(atom) :: integer
  Enum.each(@reason_codes, fn {atom, {code, opcodes}} ->
    def atom_to_reason_code(unquote(atom)), do: unquote(code)
    Enum.each(opcodes, fn opcode ->
      def reason_code_to_atom(unquote(opcode), unquote(code)), do: unquote(atom)
    end)
  end)
end


defmodule MqttApp.Protocol.Variable.Connect do
  defstruct [:protocol_version, :user_name_flag, :password_flag, :will_retain, :will_qos, :will_flag, :clean_start, :keep_alive] 
end

defmodule MqttApp.Protocol.Payload.Connect do
  defstruct [:client_identifier, :will_properties, :will_topic, :will_payload, :user_name, :password] 
end

defmodule MqttApp.Protocol.Variable.Connack do
  defstruct [:session_present, :connack_reason_code]
end

defmodule MqttApp.Protocol.Variable.Publish do
  defstruct [:topic_name, :packet_identifier] 
end

defmodule MqttApp.Protocol.Payload.Publish do
  defstruct [:payload]
end

# TODO: handle puback with only packet identifier
defmodule MqttApp.Protocol.Variable.Puback do
  defstruct [:packet_identifier, :puback_reason_code] 
end

defmodule MqttApp.Protocol.Variable.Pubrec do
  defstruct [:packet_identifier, :pubrec_reason_code] 
end

defmodule MqttApp.Protocol.Variable.Pubrel do
  defstruct [:packet_identifier, :pubrel_reason_code] 
end

defmodule MqttApp.Protocol.Variable.Pubcomp do
  defstruct [:packet_identifier, :pubcomp_reason_code] 
end

defmodule MqttApp.Protocol.Variable.Subscribe do
  defstruct [:packet_identifier]
end

defmodule MqttApp.Protocol.Payload.Subscribe do
  defstruct [:topic_filters]
end

defmodule MqttApp.Protocol.Payload.Subscribe.Options do
  defstruct [:retain_handling, :rap, :nl, :qos]
end

defmodule MqttApp.Protocol.Variable.Suback do
  defstruct [:packet_identifier]
end

defmodule MqttApp.Protocol.Payload.Suback do
  defstruct [:reason_codes]
end

defmodule MqttApp.Protocol.Variable.Unsubscribe do
  defstruct [:packet_identifier]
end

defmodule MqttApp.Protocol.Payload.Unsubscribe do
  defstruct [:topic_filters]
end

defmodule MqttApp.Protocol.Variable.Unsuback do
  defstruct [:packet_identifier]
end

defmodule MqttApp.Protocol.Payload.Unsuback do
  defstruct [:reason_codes]
end

defmodule MqttApp.Protocol.Variable.Disconnect do
  defstruct [:disconnect_reason_code]
end

defmodule MqttApp.Protocol.Variable.Auth do
  defstruct [:auth_reason_code]
end
