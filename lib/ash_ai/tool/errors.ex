# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Errors do
  @moduledoc """
  Formats Ash errors into human-readable text for tool responses.

  As the MCP specification dated 2025-06-18, tool execution errors should be
  returned as successful responses with `isError: true` and error details in
  the content array
  """

  require Logger

  alias AshAi.ToolError

  @classes [:invalid, :forbidden, :framework, :unknown]

  @doc """
  Formats an Ash error into a mcp protocol compatible structure for tool error responses.
  """
  def format(error) do
    error
    |> to_tool_errors()
    |> ToolError.to_text()
  end

  @doc """
  Translates an Ash error (or anything `Ash.Error.to_error_class/1` accepts)
  into a list of `AshAi.ToolError` structs.

  `format/1` is `AshAi.ToolError.to_text/1` of this list.
  """
  @spec to_tool_errors(term()) :: [ToolError.t()]
  def to_tool_errors(error) do
    error_class = Ash.Error.to_error_class(error)

    case Map.get(error_class, :errors, []) do
      [] ->
        [
          %ToolError{
            code: class_code(error_class),
            message: "Tool execution failed",
            text: "Tool execution failed"
          }
        ]

      errors ->
        Enum.flat_map(errors, &expand_fields/1)
    end
  end

  @doc false
  # Builds an error raised by the tool executor itself. Its message already
  # names the argument, so the text line is the message alone.
  @spec executor_error(ToolError.code(), String.t() | atom() | nil, String.t()) ::
          ToolError.t()
  def executor_error(code, field, message) do
    %ToolError{
      code: code,
      field: if(field, do: to_string(field)),
      message: message,
      text: message
    }
  end

  defp expand_fields(%{fields: fields} = error) when is_list(fields) and fields != [] do
    Enum.flat_map(fields, fn field ->
      error |> Map.put(:fields, nil) |> Map.put(:field, field) |> expand_fields()
    end)
  end

  defp expand_fields(error), do: [to_tool_error(error)]

  defp to_tool_error(error) do
    msg =
      if AshAi.ToToolError.impl_for(error) do
        AshAi.ToToolError.to_tool_error(error)
      else
        Logger.warning("""
        AshAi.ToToolError not implemented for #{inspect(error.__struct__)}, returning a generic error message.

        #{Exception.format(:error, error)}\
        """)

        "unexpected error occurred"
      end

    path = Map.get(error, :path, [])
    field = Map.get(error, :field)

    text =
      case {path, field} do
        {_, nil} -> msg
        {[], field} -> "#{field}: #{msg}"
        {path, field} -> "#{Enum.join(path ++ [field], ".")}: #{msg}"
      end

    %ToolError{
      code: code(error),
      field: if(field, do: to_string(field)),
      path: Enum.map(List.wrap(path), &path_segment/1),
      message: msg,
      text: text
    }
  end

  defp path_segment(segment) when is_integer(segment), do: segment
  defp path_segment(segment), do: to_string(segment)

  # Finer codes for the Ash errors AshAi can tell apart; everything else falls
  # back to the error's class.
  defp code(%Ash.Error.Query.NotFound{}), do: :not_found
  defp code(%Ash.Error.Changes.Required{}), do: :required
  defp code(%Ash.Error.Query.Required{}), do: :required
  defp code(%Ash.Error.Invalid.NoSuchInput{}), do: :unknown_input
  defp code(error), do: class_code(error)

  defp class_code(%{class: class}) when class in @classes, do: class
  defp class_code(_error), do: :unknown
end
