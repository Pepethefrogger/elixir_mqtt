defmodule MqttAppTest.Utils do
  use ExUnit.Case

  test "variable length integer" do
    x = 2090
    {:ok, ^x, _, ""} = MqttApp.Utils.encode_variable_length(x) |> MqttApp.Utils.decode_variable_length 
  end

  test "binary" do
    x = "Hello, testing bin"
    {:ok, ^x, _, ""}  = MqttApp.Utils.encode_binary(x) |> MqttApp.Utils.decode_binary 
  end
end

defmodule MqttAppTest.Encoding.Packets do
  use ExUnit.Case

  test "connect packet" do
    # defstruct [:protocol_version, :user_name_flag, :password_flag, :will_retain, :will_qos, :will_flag, :clean_start, :keep_alive] 
    variable = %MqttApp.Protocol.Variable.Connect{
      protocol_version: 5,
      user_name_flag: 0,
      password_flag: 0,
      will_retain: 0,
      will_qos: 0,
      will_flag: 0,
      clean_start: 0,
      keep_alive: 123,
    }
    properties = Map.new
    # defstruct [:client_identifier, :will_properties, :will_topic, :will_payload, :user_name, :password] 
    payload = %MqttApp.Protocol.Payload.Connect{
      client_identifier: "im a client bish",
    }
    packet = MqttApp.Protocol.Write.write_packet_testing(:connect, nil, variable, properties, payload)
    {:connect, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "connack packet" do
      variable = %MqttApp.Protocol.Variable.Connack{
        session_present: 0,
        connack_reason_code: :success
      }

      properties = Map.new
      payload = nil

      packet = MqttApp.Protocol.Write.write_packet_testing(:connack, nil, variable, properties, payload)
      {:connack, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
    end

    test "subscribe packet" do
    variable = %MqttApp.Protocol.Variable.Subscribe{packet_identifier: 123}
    properties = Map.new()
    payload = %MqttApp.Protocol.Payload.Subscribe{
      topic_filters: [
        {"a/b", %MqttApp.Protocol.Payload.Subscribe.Options{retain_handling: 0, rap: 0, nl: 1, qos: 2}},
        {"x/y", %MqttApp.Protocol.Payload.Subscribe.Options{retain_handling: 1, rap: 1, nl: 1, qos: 2}}
      ]
    }

    packet = MqttApp.Protocol.Write.write_packet_testing(:subscribe, nil, variable, properties, payload)
    {:subscribe, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "suback packet" do
    variable = %MqttApp.Protocol.Variable.Suback{packet_identifier: 321}
    properties = Map.new()
    payload = %MqttApp.Protocol.Payload.Suback{reason_codes: [0, 1, 2]}

    packet = MqttApp.Protocol.Write.write_packet_testing(:suback, nil, variable, properties, payload)
    {:suback, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "unsubscribe packet" do
    variable = %MqttApp.Protocol.Variable.Unsubscribe{packet_identifier: 555}
    properties = Map.new()
    payload = %MqttApp.Protocol.Payload.Unsubscribe{topic_filters: ["u/v", "m/n"]}

    packet = MqttApp.Protocol.Write.write_packet_testing(:unsubscribe, nil, variable, properties, payload)
    {:unsubscribe, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "unsuback packet" do
    variable = %MqttApp.Protocol.Variable.Unsuback{packet_identifier: 555}
    properties = Map.new()
    payload = %MqttApp.Protocol.Payload.Unsuback{reason_codes: [0, 16]}

    packet = MqttApp.Protocol.Write.write_packet_testing(:unsuback, nil, variable, properties, payload)
    {:unsuback, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "publish packet" do
    flags = %MqttApp.Protocol.Flags{
      dup: 0,
      qos: 1,
      retain: 0
    }

    variable = %MqttApp.Protocol.Variable.Publish{
      topic_name: "test/topic",
      packet_identifier: 42
    }

    properties = Map.new

    payload = %MqttApp.Protocol.Payload.Publish{
      payload: "hello world"
    }

    packet = MqttApp.Protocol.Write.write_packet_testing(:publish, flags, variable, properties, payload)
    {:publish, ^flags, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end


  test "pingreq packet" do
    variable = nil
    properties = Map.new
    payload = nil

    packet = MqttApp.Protocol.Write.write_packet_testing(:pingreq, nil, variable, properties, payload)
    {:pingreq, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "pingresp packet" do
    packet = MqttApp.Protocol.Write.write_packet_testing(:pingresp, nil, nil, %{}, nil)
    {:pingresp, _, nil, %{}, nil} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "disconnect packet" do
    variable = %MqttApp.Protocol.Variable.Disconnect{
      disconnect_reason_code: :normal_disconnection
    }

    properties = Map.new
    payload = nil

    packet = MqttApp.Protocol.Write.write_packet_testing(:disconnect, nil, variable, properties, payload)
    {:disconnect, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  test "auth packet" do
    variable = %MqttApp.Protocol.Variable.Auth{auth_reason_code: :success}
    properties = Map.new()
    payload = nil

    packet = MqttApp.Protocol.Write.write_packet_testing(:auth, nil, variable, properties, payload)
    {:auth, _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
  end

  for pkt <- [:puback, :pubrec, :pubrel, :pubcomp] do
    pkt_str = pkt |> Atom.to_string
    module_name = pkt_str |> :string.titlecase |> String.to_atom
    module = Module.concat(MqttApp.Protocol.Variable, module_name)
    struct_field = pkt_str <> "_reason_code" |> String.to_atom
    test "#{pkt} packet" do
      variable = %unquote(module){:packet_identifier => 99, unquote(struct_field) => :success}
      properties = Map.new()
      payload = nil

      packet = MqttApp.Protocol.Write.write_packet_testing(unquote(pkt), nil, variable, properties, payload)
      {unquote(pkt), _, ^variable, ^properties, ^payload} = MqttApp.Protocol.Read.parse_packet_testing(packet)
    end
  end
  
end

defmodule MqttAppTest.Encoding do
  use ExUnit.Case
  
  @tag :encoding
  test "parse and encode connect properties" do
    properties = %{
      session_expiry_interval: 120,
      receive_maximum: 50,
      maximum_packet_size: 1024
    }

    encoded = MqttApp.Protocol.Write.write_properties(:connect, properties)
    {decoded, <<>>} = MqttApp.Protocol.Read.parse_properties(:connect, encoded)

    assert decoded == properties
  end
end

