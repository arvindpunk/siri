# Siri

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `siri` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:siri, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/siri>.

## Conversation summaries

Ask Siri for a recap naturally or by message count/duration:

```text
@siri summarize 100
@siri summarize 30m
@siri give me the gist of this conversation
```

Natural recap requests summarize the newest contiguous conversation session (a maximum
one-minute gap between messages), up to 75 messages. Explicit requests are capped at
200 messages and 30 minutes. Siri uses the channel's in-memory buffer first and can
retrieve older Discord history only when needed; its in-memory history resets whenever
the bot or channel handler restarts.
