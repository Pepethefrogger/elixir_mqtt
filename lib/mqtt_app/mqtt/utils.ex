defmodule MqttApp.Utils do
  require Logger

  @spec decode_variable_length(data :: binary) ::
          {:ok, integer, consumed :: integer, rest :: binary} | {:err, :malformed_variable_length}
  def decode_variable_length(data) do
    decode_variable_length(data, 1)
  end

  defp decode_variable_length(<<>>, _count) do
    Logger.error("EOF when decoding variable length")
    {:err, :malformed_packet}
  end

  defp decode_variable_length(_data, 5) do
    Logger.error("Too big of a number when decoding variable length")
    {:err, :malformed_packet}
  end

  defp decode_variable_length(<<num, rest::binary>>, count) when Bitwise.band(num, 128) == 0 do
    {:ok, Bitwise.band(num, 127), count, rest}
  end

  defp decode_variable_length(<<num, rest::binary>>, count) do
    with {:ok, length, result_count, rest} <- decode_variable_length(rest, count + 1) do
      {:ok, Bitwise.band(num, 127) + 128 * length, result_count, rest}
    end
  end

  @spec decode_binary(binary) ::
          {:ok, binary, consumed :: integer, rest :: binary} | {:err, :malformed_packet}
  def decode_binary(<<length::size(16), rest::binary>>) do
    if byte_size(rest) >= length do
      <<data::binary-size(^length), rest::binary>> = rest
      {:ok, data, 2 + length, rest}
    else
      Logger.error("Binary decode hit EOF")
      {:err, :malformed_packet}
    end
  end

  @spec decode_utf8(binary) ::
          {:ok, String.t(), consumed :: integer, rest :: binary} | {:err, :malformed_packet}
  def decode_utf8(<<length::size(16), rest::binary>>) do
    if byte_size(rest) >= length do
      <<string::binary-size(^length), rest::binary>> = rest

      if String.valid?(string) and :binary.match(string, <<0>>) == :nomatch do
        {:ok, string, 2 + length, rest}
      else
        Logger.error("Invalid utf8 string")
        {:err, :malformed_packet}
      end
    else
      Logger.error("String decode hit EOF")
      {:err, :malformed_packet}
    end
  end

  @spec encode_binary(binary) :: binary
  def encode_binary(data) do
    length = byte_size(data)
    <<length::16, data::binary>>
  end

  @spec encode_utf8(String.t()) :: binary
  def encode_utf8(data) do
    length = byte_size(data)
    <<length::16, data::binary>>
  end

  @spec encode_variable_length(integer) :: binary
  def encode_variable_length(num) do
    encoded = rem(num, 128)
    num = div(num, 128)

    if num > 0 do
      encoded = Bitwise.bor(encoded, 128)
      <<encoded, encode_variable_length(num)::binary>>
    else
      <<encoded>>
    end
  end

  def put_if_not_nil(map, _, nil), do: map
  def put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  def put_if_not_exists!(map, key, value) do
    Map.update(map, key, value, fn _a -> raise "key #{key} already exists" end)
  end

  def put_append(map, key, value) do
    Map.update(map, key, [value], fn prev -> [value | prev] end)
  end
end
