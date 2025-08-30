defmodule Siri.Model do
  use Ecto.Schema
  use Instructor

  @llm_doc """
  A response or reaction to the given Discord message.
  If reply, populat type as reply and populate content with the response to the message.
  If reaction, populate type as react and emoji as one of the given emoji.
  """

  @primary_key false
  embedded_schema do
    field(:type, Ecto.Enum, values: [:react, :reply, :react_and_reply])
    field(:content, :string)

    field(:emoji, Ecto.Enum, values: Siri.Emoji.list())
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:type])
  end
end
