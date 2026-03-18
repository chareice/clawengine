defmodule ClawEngine.DeviceTokenStore do
  @moduledoc "Persists device tokens received from Gateway hello-ok."

  @filename "clawengine-device-tokens.json"

  def get_token(role) do
    case read_store() do
      {:ok, store} ->
        case Map.get(store, role) do
          %{"token" => token} -> {:ok, token}
          _ -> :not_found
        end

      _ ->
        :not_found
    end
  end

  def save_token(role, token, scopes) do
    store =
      case read_store() do
        {:ok, s} -> s
        _ -> %{}
      end

    updated =
      Map.put(store, role, %{
        "token" => token,
        "scopes" => scopes,
        "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    path = store_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(updated))
    :ok
  end

  defp store_path do
    dir =
      System.get_env("CLAWENGINE_DEVICE_IDENTITY_DIR") ||
        Path.join(System.tmp_dir!(), "clawengine")

    Path.join(dir, @filename)
  end

  defp read_store do
    case File.read(store_path()) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      {:error, _} -> :not_found
    end
  end
end
