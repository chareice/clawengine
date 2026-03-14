defmodule OpenClawZalify.Skills.Runner do
  @moduledoc false

  @callback search_skills(String.t(), keyword()) ::
              {:ok, [map()]} | {:error, term()}
  @callback inspect_skill(String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback install_skill(String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback update_skill(String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback uninstall_skill(String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
end
