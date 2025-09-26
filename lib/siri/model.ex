defmodule Siri.Model do
  use Ecto.Schema
  use Instructor

  @llm_doc """
  Response to be returned by the LLM. The `type` field indicates the type of response, and the other fields are used based on the type.
  - `:react` - React to the message with the specified `emoji`.
  - `:reply` - Reply to the message with the specified `content`.
  - `:react_and_reply` - React to the message with the specified `emoji` and reply with the specified `content`.
  - `:giphy` - Return a search term for a Giphy search.
  """

  @primary_key false
  embedded_schema do
    field(:type, Ecto.Enum, values: [:react, :reply, :react_and_reply, :giphy])
    field(:content, :string)
    field(:emoji, Ecto.Enum, values: Siri.Emoji.list())
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:type])
  end
end
