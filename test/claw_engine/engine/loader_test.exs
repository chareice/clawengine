defmodule ClawEngine.Engine.LoaderTest do
  use ExUnit.Case, async: true

  alias ClawEngine.Engine.Loader

  test "loads a config directory and resolves spaces from templates and model profiles" do
    root =
      Path.join(System.tmp_dir!(), "clawengine-loader-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "models"))
    File.mkdir_p!(Path.join(root, "spaces"))
    File.mkdir_p!(Path.join(root, "templates/support"))

    File.write!(
      Path.join(root, "instance.yaml"),
      """
      id: acme
      name: ACME Commerce

      agent:
        name_template: "{{instance.id}}-{{space.slug}}"
        workspace_path_template: "{{openclaw.workspace_root}}/{{instance.id}}/{{space.slug}}"

      defaults:
        template_set: support
        model_profile: default
        memory_enabled: true
      """
    )

    File.write!(
      Path.join(root, "models/default.yaml"),
      """
      id: default
      label: Default
      model_ref: deepseek/deepseek-chat
      reasoning_level: off
      timeout_ms: 45000
      """
    )

    File.write!(
      Path.join(root, "spaces/shop-123.yaml"),
      """
      id: shop-123
      name: Shop 123

      agent:
        display_name: Shop 123 Assistant

      variables:
        region: sg
        storefront: shop-123.example.com
      """
    )

    File.write!(
      Path.join(root, "templates/support/IDENTITY.md"),
      """
      # Identity

      Space {{space.id}}
      """
    )

    File.write!(
      Path.join(root, "templates/support/SOUL.md"),
      """
      # Soul

      Storefront {{vars.storefront}}
      """
    )

    File.write!(
      Path.join(root, "templates/support/USER.md"),
      """
      # User

      Region {{vars.region}}
      """
    )

    on_exit(fn -> File.rm_rf(root) end)

    assert {:ok, snapshot} = Loader.load(root)
    assert snapshot.instance.id == "acme"
    assert snapshot.instance.name == "ACME Commerce"
    assert Map.has_key?(snapshot.model_profiles, "default")

    space = snapshot.spaces["shop-123"]
    assert space.agent_name == "acme-shop-123"
    assert space.workspace_path == "/home/node/.openclaw/workspace/spaces/acme/shop-123"
    assert space.model_profile_id == "default"
    assert space.model_ref == "deepseek/deepseek-chat"
    assert space.reasoning_level == "off"
    assert space.timeout_ms == 45_000
    assert space.identity_md =~ "Space shop-123"
    assert space.soul_md =~ "Storefront shop-123.example.com"
    assert space.user_md =~ "Region sg"
  end
end
