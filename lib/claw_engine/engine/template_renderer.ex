defmodule ClawEngine.Engine.TemplateRenderer do
  @moduledoc """
  Tiny template renderer for config-driven markdown and naming templates.
  """

  @placeholder ~r/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/

  @spec render(String.t(), map()) :: String.t()
  def render(template, context) when is_binary(template) and is_map(context) do
    Regex.replace(@placeholder, template, fn _match, path ->
      case lookup(context, String.split(path, ".", trim: true)) do
        nil -> ""
        value when is_binary(value) -> value
        value when is_atom(value) -> Atom.to_string(value)
        value when is_integer(value) -> Integer.to_string(value)
        value when is_float(value) -> :erlang.float_to_binary(value, [:compact])
        value when is_boolean(value) -> to_string(value)
        value -> Jason.encode!(value)
      end
    end)
  end

  defp lookup(value, []), do: value
  defp lookup(nil, _parts), do: nil

  defp lookup(map, [part | rest]) when is_map(map) do
    next =
      cond do
        Map.has_key?(map, part) -> Map.get(map, part)
        Map.has_key?(map, String.to_atom(part)) -> Map.get(map, String.to_atom(part))
        true -> nil
      end

    lookup(next, rest)
  rescue
    ArgumentError -> lookup(Map.get(map, part), rest)
  end

  defp lookup(_value, _parts), do: nil
end
