defmodule ClawEngine.OpenClaw.ModelRefTest do
  use ExUnit.Case, async: true

  alias ClawEngine.OpenClaw.ModelRef

  test "normalizes provider:model refs for Gateway requests" do
    assert ModelRef.normalize_for_gateway("openai:glm-5-turbo") == "openai/glm-5-turbo"
  end

  test "preserves slash-delimited model refs" do
    assert ModelRef.normalize_for_gateway("deepseek/deepseek-chat") == "deepseek/deepseek-chat"
  end

  test "returns nil for blank values" do
    assert ModelRef.normalize_for_gateway("   ") == nil
  end
end
