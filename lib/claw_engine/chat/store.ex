defmodule ClawEngine.Chat.Store do
  @moduledoc false

  alias ClawEngine.Chat.SessionRecord

  @callback get_session(String.t()) :: {:ok, SessionRecord.t() | nil} | {:error, term()}
  @callback create_session(map()) :: {:ok, SessionRecord.t()} | {:error, term()}
end
