# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolEndEvent do
  @moduledoc """
  Event data passed to the `on_tool_end` callback used by `AshAi.ToolLoop`.

  Contains the tool name and execution result. The error is text unless the
  tool was built with `errors: :structured` (see `AshAi.Tool.Builder.build/2`),
  in which case it is a list of `AshAi.ToolError` structs.
  """
  @type t :: %__MODULE__{
          tool_name: String.t(),
          result: {:ok, String.t(), any()} | {:error, String.t() | [AshAi.ToolError.t()]}
        }

  defstruct [:tool_name, :result]
end
