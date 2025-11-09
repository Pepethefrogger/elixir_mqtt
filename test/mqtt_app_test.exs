defmodule MqttAppTest.Utils do
  use ExUnit.Case

  test "variable length integer" do
    x = 2090

    {:ok, ^x, _, ""} =
      MqttApp.Utils.encode_variable_length(x) |> MqttApp.Utils.decode_variable_length()
  end

  test "binary" do
    x = "Hello, testing bin"
    {:ok, ^x, _, ""} = MqttApp.Utils.encode_binary(x) |> MqttApp.Utils.decode_binary()
  end
end

defmodule MqttAppTest.Encoding.Packets do
  use ExUnit.Case

  alias MqttApp.Protocol
  alias Protocol.Flags
  alias Protocol.Variable
  alias Protocol.Payload
  alias Protocol.Packet

  @packet_examples [
    %Packet{
      opcode: :connect,
      variable: %Variable.Connect{
        protocol_version: 5,
        user_name_flag: 1,
        password_flag: 1,
        will_retain: 0,
        will_qos: 0,
        will_flag: 1,
        clean_start: 1,
        keep_alive: 60
      },
      payload: %Payload.Connect{
        client_identifier: "client_123",
        will_topic: "topic/will",
        will_payload: "bye",
        user_name: "user",
        password: "pass"
      },
    },
    %Packet{
      opcode: :connack,
      variable: %Variable.Connack{
        session_present: 1,
        connack_reason_code: :success
      },
    },
    %Packet{
      opcode: :publish,
      flags: %Flags{dup: 1, qos: 1, retain: 1},
      variable: %Variable.Publish{
        topic_name: "topic/test",
        packet_identifier: 42
      },
      payload: %Payload.Publish{payload: "Hello MQTT"},
    },
    %Packet{
      opcode: :puback,
      variable: %Variable.Puback{
        packet_identifier: 42,
        puback_reason_code: :success
      },
    },
    %Packet{
      opcode: :pubrec,
      variable: %Variable.Pubrec{
        packet_identifier: 42,
        pubrec_reason_code: :success
      },
    },
    %Packet{
      opcode: :pubrel,
      variable: %Variable.Pubrel{
        packet_identifier: 42,
        pubrel_reason_code: :success
      },
    },
    %Packet{
      opcode: :pubcomp,
      variable: %Variable.Pubcomp{
        packet_identifier: 42,
        pubcomp_reason_code: :success
      },
    },
    %Packet{
      opcode: :subscribe,
      variable: %Variable.Subscribe{
        packet_identifier: 99
      },
      payload: %Payload.Subscribe{topic_filters: [
        {"topic/1", %Payload.Subscribe.Options{qos: 0, retain_handling: 0, rap: 1, nl: 1}}
      ]}
    },
    %Packet{
      opcode: :suback,
      variable: %Variable.Suback{
        packet_identifier: 99
      },
      payload: %Payload.Suback{reason_codes: [:granted_qos_0]}
    },
    %Packet{
      opcode: :unsubscribe,
      variable: %Variable.Unsubscribe{
        packet_identifier: 5
      },
      payload: %Payload.Unsubscribe{topic_filters: ["topic/1"]}
    },
    %Packet{
      opcode: :unsuback,
      variable: %Variable.Unsuback{
        packet_identifier: 5
      },
      payload: %Payload.Unsuback{reason_codes: [:success]}
    },
    %Packet{
      opcode: :pingreq,
    },
    %Packet{
      opcode: :pingresp,
    },
    %Packet{
      opcode: :disconnect,
      variable: %Variable.Disconnect{
        disconnect_reason_code: :normal_disconnection
      },
    },
    %Packet{
      opcode: :auth,
      variable: %Variable.Auth{
        auth_reason_code: :success
      },
    }
  ]

  describe "packet encoding/decoding" do
    for packet = %Packet{opcode: opcode} <- @packet_examples do
      test "parse and encode #{opcode} packet" do
        packet = unquote(Macro.escape(packet))

        encoded = MqttApp.Protocol.Write.write_packet(packet)
        decoded = MqttApp.Protocol.Read.parse_packet(encoded)

        assert packet == decoded
      end
    end
  end
end

defmodule MqttAppTest.Encoding do
  use ExUnit.Case

  @property_sets %{
    connect: %{
      session_expiry_interval: 60,
      receive_maximum: 10,
      maximum_packet_size: 1024,
      topic_alias_maximum: 5,
      request_response_information: 1,
      request_problem_information: 1,
      user_property: [{"other_key", "other_value"}],
      authentication_method: "token",
      authentication_data: <<1, 2, 3>>
    },
    connack: %{
      session_expiry_interval: 120,
      receive_maximum: 100,
      maximum_qos: 1,
      retain_available: 1,
      maximum_packet_size: 4096,
      assigned_client_identifier: "client123",
      topic_alias_maximum: 10,
      reason_string: "accepted",
      user_property: [{"key", "value"}],
      wildcard_subscription_available: 1,
      subscription_identifier_available: 1,
      shared_subscription_available: 1,
      server_keep_alive: 30,
      response_information: "info",
      server_reference: "server.local"
    },
    publish: %{
      payload_format_indicator: 1,
      message_expiry_interval: 300,
      topic_alias: 7,
      response_topic: "reply/topic",
      correlation_data: <<11, 22, 33>>,
      user_property: [{"pub_key", "pub_val"}],
      content_type: "text/plain"
    },
    puback: %{
      reason_string: "ok",
      user_property: [{"ack_key", "ack_val"}]
    },
    pubrec: %{
      reason_string: "ok",
      user_property: [{"rec_key", "rec_val"}]
    },
    pubrel: %{
      reason_string: "ok",
      user_property: [{"rel_key", "rel_val"}]
    },
    pubcomp: %{
      reason_string: "ok",
      user_property: [{"comp_key", "comp_val"}]
    },
    subscribe: %{
      subscription_identifier: [31],
      user_property: [{"sub_key", "sub_val"}]
    },
    suback: %{
      reason_string: "subscribed",
      user_property: [{"suback_key", "suback_val"}]
    },
    unsubscribe: %{
      user_property: [{"unsub_key", "unsub_val"}]
    },
    unsuback: %{
      reason_string: "unsubscribed",
      user_property: [{"unsuback_key", "unsuback_val"}]
    },
    disconnect: %{
      session_expiry_interval: 600,
      reason_string: "bye",
      user_property: [{"disc_key", "disc_val"}],
      server_reference: "disconnect.server"
    },
    auth: %{
      authentication_method: "basic",
      authentication_data: <<1, 2, 3, 4>>,
      reason_string: "reauth",
      user_property: [{"auth_key", "auth_val"}]
    },
    will: %{
      will_delay_interval: 10,
      payload_format_indicator: 1,
      message_expiry_interval: 3600,
      content_type: "application/json",
      response_topic: "client/response",
      correlation_data: <<1, 2, 3, 4>>,
      user_property: [{"key1", "value1"}]
    }
  }

  describe "property encoding/decoding" do
    for {packet_type, properties} <- @property_sets do
      test "parse and encode #{packet_type} properties" do
        packet = unquote(packet_type)
        properties = unquote(Macro.escape(properties))

        encoded = MqttApp.Protocol.Write.write_properties(packet, properties)
        {decoded, <<>>} = MqttApp.Protocol.Read.parse_properties(packet, encoded)

        assert properties == decoded
      end
    end
  end
end
