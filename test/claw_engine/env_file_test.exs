defmodule ClawEngine.EnvFileTest do
  use ExUnit.Case, async: true

  alias ClawEngine.EnvFile

  test "read/1 loads key value pairs and skips comments" do
    path =
      write_env_file("""
      # comment
      OPENCLAW_GATEWAY_URL=ws://127.0.0.1:28789
      export OPENCLAW_GATEWAY_TOKEN = change-me
      QUOTED_VALUE="hello world"
      INLINE_COMMENT=value # ignored
      """)

    assert EnvFile.read(path) == [
             {"OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:28789"},
             {"OPENCLAW_GATEWAY_TOKEN", "change-me"},
             {"QUOTED_VALUE", "hello world"},
             {"INLINE_COMMENT", "value"}
           ]
  end

  test "load_system/2 keeps existing values by default" do
    path =
      write_env_file("""
      OPENCLAW_GATEWAY_URL=ws://127.0.0.1:28789
      """)

    System.put_env("OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:9999")

    try do
      assert :ok = EnvFile.load_system(path)
      assert System.get_env("OPENCLAW_GATEWAY_URL") == "ws://127.0.0.1:9999"
    after
      System.delete_env("OPENCLAW_GATEWAY_URL")
    end
  end

  test "load_system/2 can override existing values" do
    path =
      write_env_file("""
      OPENCLAW_GATEWAY_URL=ws://127.0.0.1:28789
      """)

    System.put_env("OPENCLAW_GATEWAY_URL", "ws://127.0.0.1:9999")

    try do
      assert :ok = EnvFile.load_system(path, override: true)
      assert System.get_env("OPENCLAW_GATEWAY_URL") == "ws://127.0.0.1:28789"
    after
      System.delete_env("OPENCLAW_GATEWAY_URL")
    end
  end

  defp write_env_file(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "clawengine-env-#{System.unique_integer([:positive])}.env"
      )

    File.write!(path, contents)
    path
  end
end
