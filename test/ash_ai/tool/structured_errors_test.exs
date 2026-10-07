# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.StructuredErrorsTest do
  use ExUnit.Case, async: true

  alias __MODULE__.{Address, Domain, Note}
  alias AshAi.ToolError

  defmodule CustomError do
    @moduledoc false
    use Splode.Error, fields: [:detail], class: :invalid

    def message(error), do: "custom failure: #{error.detail}"
  end

  defimpl AshAi.ToToolError, for: CustomError do
    def to_tool_error(error), do: "custom failure: #{error.detail}"
  end

  defmodule UnimplementedError do
    @moduledoc false
    use Splode.Error, fields: [], class: :framework

    def message(_error), do: "secret internal detail"
  end

  defmodule Address do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute :city, :string,
        public?: true,
        allow_nil?: false,
        constraints: [max_length: 5]
    end
  end

  defmodule Note do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    attributes do
      uuid_v7_primary_key :id, writable?: true
      attribute :title, :string, public?: true, allow_nil?: false
      attribute :code, :string, public?: true, constraints: [max_length: 3]
      attribute :address, Address, public?: true
      attribute :locked, :boolean, public?: true, default: false
    end

    actions do
      defaults [:read, :destroy, create: [:id, :title, :code, :address, :locked]]

      read :keyset_only do
        pagination keyset?: true, default_limit: 2
      end

      action :custom_failure, :string do
        argument :mode, :string, allow_nil?: false

        run fn input, _ ->
          case input.arguments.mode do
            "custom" -> {:error, CustomError.exception(detail: "boom")}
            "unimplemented" -> {:error, UnimplementedError.exception([])}
          end
        end
      end
    end

    policies do
      policy action_type(:create) do
        forbid_if changing_attributes(locked: [to: true])
        authorize_if always()
      end

      policy always() do
        authorize_if always()
      end
    end
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource Note
    end

    tools do
      tool :create_note, Note, :create
      tool :read_notes, Note, :read
      tool :get_note, Note, :read, get_by: :id
      tool :custom_failure, Note, :custom_failure
      tool :read_keyset_only, Note, :keyset_only
    end
  end

  @missing_id "0197b375-4daa-7112-a9d8-7f0104489999"

  defp tool(name) do
    [actions: [{Note, :*}], tools: [name]]
    |> AshAi.exposed_tools()
    |> hd()
  end

  defp run(name, arguments, opts \\ [], context \\ %{}) do
    AshAi.Tools.execute(tool(name), arguments, context, opts)
  end

  # Text returned by `{:error, text}` before structured errors existed,
  # captured from main before the change. The default output must not drift.
  @text_snapshots [
    {:forbidden, :create_note, %{"input" => %{"title" => "t", "locked" => true}}, "forbidden"},
    {:not_found, :get_note, %{"id" => @missing_id}, "could not be found"},
    {:required, :create_note, %{"input" => %{}}, "title: is required"},
    {:invalid_attribute, :create_note, %{"input" => %{"title" => "t", "code" => "toolong"}},
     "code: length must be less than or equal to %{max}"},
    {:invalid_path, :create_note,
     %{"input" => %{"title" => "t", "address" => %{"city" => "toolongcity"}}},
     "address.city: length must be less than or equal to %{max}"},
    {:multiple, :create_note, %{"input" => %{"code" => "toolong"}},
     "code: length must be less than or equal to %{max}\ntitle: is required"},
    {:unknown_input, :create_note, %{"input" => %{"title" => "t", "bogus" => 1}},
     "Unknown arguments provided: bogus. Valid arguments are: address, code, id, locked, title"},
    {:input_shape, :create_note, %{"input" => "not an object"},
     "`input` must be a JSON object, got \"not an object\". Pass the arguments themselves, not a JSON-encoded string of them."},
    {:missing_get_by, :get_note, %{}, "Missing required get_by argument: id"},
    {:bad_get_by, :get_note, %{"id" => "not-a-uuid"},
     "Invalid value for get_by argument id: \"not-a-uuid\""},
    {:custom, :custom_failure, %{"input" => %{"mode" => "custom"}}, "custom failure: boom"},
    {:unimplemented, :custom_failure, %{"input" => %{"mode" => "unimplemented"}},
     "unexpected error occurred"}
  ]

  describe "default text errors" do
    @tag capture_log: true
    test "are unchanged" do
      for {name, tool, arguments, expected} <- @text_snapshots do
        assert {name, {:error, expected}} == {name, run(tool, arguments)}
        assert {name, {:error, expected}} == {name, run(tool, arguments, errors: :text)}
      end
    end

    @tag capture_log: true
    test "are the text of the structured errors" do
      for {name, tool, arguments, expected} <- @text_snapshots do
        {:error, errors} = run(tool, arguments, errors: :structured)
        assert {name, AshAi.ToolError.to_text(errors)} == {name, expected}
      end
    end
  end

  describe "errors: :structured" do
    test "a policy denial is :forbidden" do
      assert {:error, [%ToolError{code: :forbidden, field: nil, path: [], message: "forbidden"}]} =
               run(:create_note, %{"input" => %{"title" => "t", "locked" => true}},
                 errors: :structured
               )
    end

    test "a missing record is :not_found" do
      assert {:error, [%ToolError{code: :not_found, message: "could not be found"}]} =
               run(:get_note, %{"id" => @missing_id}, errors: :structured)
    end

    test "a missing required attribute is :required with its field" do
      assert {:error,
              [
                %ToolError{
                  code: :required,
                  field: "title",
                  path: [],
                  message: "is required",
                  text: "title: is required"
                }
              ]} = run(:create_note, %{"input" => %{}}, errors: :structured)
    end

    test "an invalid attribute is :invalid with its field" do
      assert {:error,
              [
                %ToolError{
                  code: :invalid,
                  field: "code",
                  path: [],
                  message: "length must be less than or equal to %{max}"
                }
              ]} =
               run(:create_note, %{"input" => %{"title" => "t", "code" => "toolong"}},
                 errors: :structured
               )
    end

    test "an invalid nested attribute is :invalid with its field and path" do
      assert {:error,
              [
                %ToolError{
                  code: :invalid,
                  field: "city",
                  path: ["address"],
                  text: "address.city: length must be less than or equal to %{max}"
                }
              ]} =
               run(
                 :create_note,
                 %{"input" => %{"title" => "t", "address" => %{"city" => "toolongcity"}}},
                 errors: :structured
               )
    end

    test "several errors are returned in order" do
      assert {:error,
              [
                %ToolError{code: :invalid, field: "code"},
                %ToolError{code: :required, field: "title"}
              ]} =
               run(:create_note, %{"input" => %{"code" => "toolong"}}, errors: :structured)
    end

    test "an unknown input from the executor's own check is :unknown_input" do
      assert {:error, [%ToolError{code: :unknown_input, field: "bogus", path: []} = error]} =
               run(:create_note, %{"input" => %{"title" => "t", "bogus" => 1}},
                 errors: :structured
               )

      assert error.message == error.text
      assert error.message =~ "Unknown arguments provided: bogus."
    end

    test "several unknown inputs leave the field unset" do
      assert {:error, [%ToolError{code: :unknown_input, field: nil, message: message}]} =
               run(:create_note, %{"input" => %{"title" => "t", "bogus" => 1, "other" => 2}},
                 errors: :structured
               )

      assert message =~ "Unknown arguments provided: bogus, other."
    end

    test "a non-object input is :invalid on the input field" do
      assert {:error, [%ToolError{code: :invalid, field: "input"}]} =
               run(:create_note, %{"input" => "not an object"}, errors: :structured)
    end

    test "get_by lookup errors carry the lookup field" do
      assert {:error, [%ToolError{code: :required, field: "id"}]} =
               run(:get_note, %{}, errors: :structured)

      assert {:error, [%ToolError{code: :invalid, field: "id"}]} =
               run(:get_note, %{"id" => "not-a-uuid"}, errors: :structured)
    end

    test "pagination misuse is :invalid" do
      assert {:error,
              [
                %ToolError{
                  code: :invalid,
                  field: nil,
                  text: "Pass either `after` or `before`, not both."
                }
              ]} =
               run(:read_keyset_only, %{"after" => "a", "before" => "b"}, errors: :structured)

      assert {:error, [%ToolError{code: :invalid, field: "offset"}]} =
               run(:read_keyset_only, %{"offset" => 5}, errors: :structured)
    end

    test "an error type implementing only ToToolError gets its class as code" do
      assert {:error, [%ToolError{code: :invalid, message: "custom failure: boom"}]} =
               run(:custom_failure, %{"input" => %{"mode" => "custom"}}, errors: :structured)
    end

    @tag capture_log: true
    test "an error type without ToToolError gets its class as code and no internals" do
      assert {:error,
              [%ToolError{code: :framework, message: "unexpected error occurred"} = error]} =
               run(:custom_failure, %{"input" => %{"mode" => "unimplemented"}},
                 errors: :structured
               )

      refute inspect(error) =~ "secret internal detail"
      refute inspect(error) =~ "UnimplementedError"
    end

    test "rejects an unknown :errors value" do
      assert_raise ArgumentError, ~r/:errors option/, fn ->
        run(:get_note, %{"id" => @missing_id}, errors: :json)
      end
    end
  end

  describe "Errors.to_tool_errors/1" do
    test "maps Ash errors outside a tool call" do
      error = Ash.Error.Query.NotFound.exception(primary_key: %{id: 1}, resource: Note)

      assert [%ToolError{code: :not_found, text: "could not be found"}] =
               AshAi.Tool.Errors.to_tool_errors(error)

      assert AshAi.Tool.Errors.format(error) == "could not be found"
    end

    test "expands multi-field errors into one error per field" do
      error =
        Ash.Error.Changes.InvalidChanges.exception(
          fields: [:start_date, :end_date],
          message: "must not overlap"
        )

      assert [
               %ToolError{code: :invalid, field: "start_date", message: "must not overlap"},
               %ToolError{code: :invalid, field: "end_date", message: "must not overlap"}
             ] = AshAi.Tool.Errors.to_tool_errors(error)
    end

    test "an empty error class still yields one error" do
      assert [%ToolError{code: :unknown, text: "Tool execution failed"}] =
               AshAi.Tool.Errors.to_tool_errors(%Ash.Error.Unknown{errors: []})
    end
  end

  describe "ReqLLM callback" do
    defp callback(opts) do
      {_tool, callback} = AshAi.Tools.build(tool(:get_note), opts)
      callback
    end

    defp end_event_context do
      test_pid = self()
      %{tool_callbacks: %{on_tool_end: &send(test_pid, {:tool_end, &1})}}
    end

    test "returns text errors by default" do
      assert {:error, "could not be found"} =
               callback([]).(%{"id" => @missing_id}, end_event_context())

      assert_received {:tool_end, %AshAi.ToolEndEvent{result: {:error, "could not be found"}}}
    end

    test "returns structured errors with errors: :structured" do
      assert {:error, [%ToolError{code: :not_found}]} =
               callback(errors: :structured).(%{"id" => @missing_id}, end_event_context())

      assert_received {:tool_end,
                       %AshAi.ToolEndEvent{result: {:error, [%ToolError{code: :not_found}]}}}
    end
  end
end
