defmodule Siri.SummaryModel do
  use Ecto.Schema
  use Instructor

  @llm_doc "A concise, factual summary of a Discord conversation."

  @primary_key false
  embedded_schema do
    field(:summary, :string)
  end

  @impl true
  def validate_changeset(changeset) do
    Ecto.Changeset.validate_required(changeset, [:summary])
  end
end
