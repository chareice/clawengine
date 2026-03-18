defmodule ClawEngine.DeviceIdentity do
  @moduledoc "Generates and persists Ed25519 device identity for Gateway auth."

  @identity_filename "clawengine-device-identity.json"

  @doc "Returns {:ok, identity} with device_id, public_key_raw, private_key_raw — generates on first call, persists to disk."
  def ensure_identity do
    path = identity_path()

    case read_identity(path) do
      {:ok, identity} -> {:ok, identity}
      :not_found -> create_and_persist(path)
    end
  end

  defp identity_path do
    dir =
      System.get_env("CLAWENGINE_DEVICE_IDENTITY_DIR") ||
        Path.join(System.tmp_dir!(), "clawengine")

    Path.join(dir, @identity_filename)
  end

  defp read_identity(path) do
    case File.read(path) do
      {:ok, json} ->
        data = Jason.decode!(json)

        {:ok,
         %{
           device_id: data["device_id"],
           public_key_raw: Base.decode64!(data["public_key_raw"]),
           private_key_raw: Base.decode64!(data["private_key_raw"])
         }}

      {:error, _} ->
        :not_found
    end
  end

  defp create_and_persist(path) do
    {public_key_raw, private_key_raw} = :crypto.generate_key(:eddsa, :ed25519)

    device_id =
      :crypto.hash(:sha256, public_key_raw)
      |> Base.encode16(case: :lower)

    identity = %{
      device_id: device_id,
      public_key_raw: public_key_raw,
      private_key_raw: private_key_raw
    }

    # Persist
    File.mkdir_p!(Path.dirname(path))

    json =
      Jason.encode!(%{
        "device_id" => device_id,
        "public_key_raw" => Base.encode64(public_key_raw),
        "private_key_raw" => Base.encode64(private_key_raw),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    File.write!(path, json)

    {:ok, identity}
  end

  @doc "Builds base64url-encoded public key for connect params."
  def public_key_base64url(public_key_raw) do
    Base.url_encode64(public_key_raw, padding: false)
  end

  @doc "Signs a payload string with the device's private key (Ed25519)."
  def sign(private_key_raw, payload) when is_binary(payload) do
    signature = :crypto.sign(:eddsa, :none, payload, [private_key_raw, :ed25519])
    Base.url_encode64(signature, padding: false)
  end

  @doc "Builds the V3 signature payload string."
  def build_payload_v3(params) do
    [
      "v3",
      params.device_id,
      params.client_id,
      params.client_mode,
      params.role,
      Enum.join(params.scopes, ","),
      Integer.to_string(params.signed_at_ms),
      params.token || "",
      params.nonce,
      normalize_metadata(params.platform),
      normalize_metadata(params.device_family)
    ]
    |> Enum.join("|")
  end

  defp normalize_metadata(nil), do: ""

  defp normalize_metadata(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end
end
