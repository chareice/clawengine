defmodule ClawEngine.Agents.Store do
  @moduledoc """
  Persistence boundary for workspace-agent state.
  """

  alias ClawEngine.Agents.AgentRecord

  @callback get_workspace_agent(String.t()) :: {:ok, AgentRecord.t() | nil} | {:error, term()}
  @callback upsert_workspace_agent(map()) :: {:ok, AgentRecord.t()} | {:error, term()}
  @callback delete_workspace_agent(String.t()) :: {:ok, AgentRecord.t() | nil} | {:error, term()}
end
