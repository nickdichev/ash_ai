# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolError do
  @moduledoc """
  A structured tool failure, returned when a tool runs with `errors: :structured`.

  `AshAi.Tool.Execution.run/4` and `AshAi.Tools.execute/4` return
  `{:error, [%AshAi.ToolError{}]}` when given `errors: :structured`. Without
  that option they return `{:error, text}`, where `text` is `to_text/1` of the
  same list.

  This struct is the public error vocabulary for tool calls. Ash errors are
  translated into it; it never carries exception structs, module names or
  stacktraces.

  ## Fields

    * `:code` - a stable atom describing the kind of failure, see "Codes".
    * `:field` - the name of the input or argument the error is about, as a
      string, or `nil` when the error is not tied to one.
    * `:path` - the path to `:field` inside nested input (for example an
      embedded resource or a map argument), as a list of strings and integer
      indexes. Empty for top-level inputs.
    * `:message` - a concise description, as produced by `AshAi.ToToolError`
      for Ash errors. It does not repeat `:field` or `:path`.
    * `:text` - the line this error contributes to the default text output.
      For Ash errors with a field this is `"path.field: message"`, otherwise
      it equals `:message`.

  ## Codes

    * `:forbidden` - the actor is not allowed to perform the action or to
      access a field. Retrying with the same actor will not help.
    * `:not_found` - the record the tool addressed does not exist (or is not
      visible to the actor).
    * `:required` - a required input or argument was not provided.
    * `:unknown_input` - the call named an input the tool does not accept.
    * `:invalid` - any other problem with the call's input, such as a value
      failing a constraint, a malformed filter or misused pagination options.
    * `:framework` - a failure inside Ash or its extensions, not caused by the
      input.
    * `:unknown` - any other failure, including exceptions raised by
      application code.

  New codes may be added in future releases; treat an unrecognized code like
  the closest of `:invalid`, `:framework` or `:unknown` for your use case.

  Errors from your own exception types get a code from their Ash error class
  (`:invalid`, `:forbidden`, `:framework` or `:unknown`), so implementing
  `AshAi.ToToolError` for them is enough.

  ## Example

      {:error, errors} =
        AshAi.Tools.execute(tool, %{"input" => %{}}, %{actor: user}, errors: :structured)

      errors
      #=> [
      #=>   %AshAi.ToolError{
      #=>     code: :required,
      #=>     field: "title",
      #=>     path: [],
      #=>     message: "is required",
      #=>     text: "title: is required"
      #=>   }
      #=> ]

      AshAi.ToolError.to_text(errors)
      #=> "title: is required"
  """

  @type code ::
          :forbidden
          | :not_found
          | :required
          | :unknown_input
          | :invalid
          | :framework
          | :unknown

  @type t :: %__MODULE__{
          code: code(),
          field: String.t() | nil,
          path: [String.t() | non_neg_integer()],
          message: String.t(),
          text: String.t()
        }

  @enforce_keys [:code, :message, :text]
  defstruct [:code, :field, :message, :text, path: []]

  @doc """
  Joins the errors' `:text` lines into the default text output for a failed
  tool call.
  """
  @spec to_text([t()]) :: String.t()
  def to_text(errors) when is_list(errors) do
    case Enum.map_join(errors, "\n", & &1.text) do
      "" -> "Tool execution failed"
      text -> text
    end
  end
end
