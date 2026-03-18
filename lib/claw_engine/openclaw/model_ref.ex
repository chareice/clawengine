defmodule ClawEngine.OpenClaw.ModelRef do
  @moduledoc false

  @spec normalize_for_gateway(term()) :: String.t() | nil
  def normalize_for_gateway(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      String.contains?(trimmed, "/") ->
        trimmed

      true ->
        case String.split(trimmed, ":", parts: 2) do
          [provider, model] ->
            provider = String.trim(provider)
            model = String.trim(model)

            if provider != "" and model != "" do
              "#{provider}/#{model}"
            else
              trimmed
            end

          _other ->
            trimmed
        end
    end
  end

  def normalize_for_gateway(_value), do: nil
end
