defmodule Siri.Substitutions.Giphy do
  require Logger

  @spec apply_subsitition(String.t()) :: String.t()
  def apply_subsitition(text) do
    search_gif(text)
  end

  @spec client() :: Req.Request.t()
  defp client do
    Req.new(base_url: "https://api.giphy.com")
  end

  @spec search_gif(String.t()) :: String.t()
  defp search_gif(query) do
    api_key = System.get_env("GIPHY_API_KEY")

    case Req.get(client(),
           url: "/v1/gifs/search",
           params: %{api_key: api_key, q: query, limit: 1}
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body["data"] do
          [first | _] -> first["url"]
          [] -> ""
        end

      _ ->
        ""
    end
  end
end
