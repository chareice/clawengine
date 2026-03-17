defmodule ClawEngine.EnvFile do
  @moduledoc false

  @default_path Path.expand("../../.env", __DIR__)

  @spec default_path() :: Path.t()
  def default_path, do: @default_path

  @spec load_system(Path.t(), keyword()) :: :ok
  def load_system(path, opts \\ []) do
    override? = Keyword.get(opts, :override, false)

    path
    |> read()
    |> Enum.each(fn {key, value} ->
      if override? or is_nil(System.get_env(key)) do
        System.put_env(key, value)
      end
    end)

    :ok
  end

  @spec read(Path.t()) :: [{String.t(), String.t()}]
  def read(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split(~r/\r?\n/u)
      |> Enum.reduce([], fn line, acc ->
        case parse_line(line) do
          nil -> acc
          parsed -> [parsed | acc]
        end
      end)
      |> Enum.reverse()
    else
      []
    end
  end

  @spec parse_line(String.t()) :: {String.t(), String.t()} | nil
  def parse_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        nil

      String.starts_with?(trimmed, "#") ->
        nil

      true ->
        with [raw_key, raw_value] <- String.split(trimmed, "=", parts: 2),
             key when key != "" <- normalize_key(raw_key) do
          {key, normalize_value(raw_value)}
        else
          _other -> nil
        end
    end
  end

  defp normalize_key(raw_key) do
    raw_key
    |> String.trim()
    |> String.replace_prefix("export ", "")
    |> String.trim()
  end

  defp normalize_value(raw_value) do
    value = String.trim(raw_value)

    cond do
      quoted?(value, "\"") ->
        String.trim(value, "\"")

      quoted?(value, "'") ->
        String.trim(value, "'")

      true ->
        value
        |> String.split(~r/\s+#/u, parts: 2)
        |> hd()
        |> String.trim()
    end
  end

  defp quoted?(value, quote) do
    String.starts_with?(value, quote) and String.ends_with?(value, quote) and
      String.length(value) >= 2
  end
end
