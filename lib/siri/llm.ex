defmodule Siri.LLM do
  @moduledoc false

  @provider :gemini
  @model "gemini-3.5-flash-lite"

  def chat(messages, options \\ []) do
    ExLLM.chat(@provider, messages, Keyword.put_new(options, :model, @model))
  end
end
