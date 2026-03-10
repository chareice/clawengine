defmodule OpenClawZalify.Chat.Store do
  @moduledoc false

  alias OpenClawZalify.Chat.SessionRecord

  @callback get_session(String.t()) :: {:ok, SessionRecord.t() | nil} | {:error, term()}
  @callback create_session(map()) :: {:ok, SessionRecord.t()} | {:error, term()}
end
