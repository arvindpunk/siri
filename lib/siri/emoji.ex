defmodule Siri.Emoji do
  alias Nostrum.Struct.Emoji

  @emoji_map %{
    hmm: %Emoji{id: 780_087_508_314_619_924, name: "hmm"},
    lmao: %Emoji{id: 780_087_576_194_580_532, name: "lmao"},
    vim: %Emoji{id: 797_417_653_370_093_579, name: "vim"},
    letsfuckinggo: %Emoji{id: 856_461_558_602_793_000, name: "letsfuckinggo"},

    # base emojis
    skull: %Emoji{name: "skull"},
    laugh: %Emoji{name: "laugh"}
  }

  @emoji_list @emoji_map |> Map.keys()

  def list do
    @emoji_list
  end

  def get(key) do
    Map.get(@emoji_map, key)
  end
end
