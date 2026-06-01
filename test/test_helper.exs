# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs/contributors>
#
# SPDX-License-Identifier: MIT

ExUnit.start(exclude: [:live_llm])

AshAi.TestRepo.start_link()

Oban.start_link(AshOban.config([AshAi.Test.Music], Application.get_env(:ash_ai, :oban)))

Ecto.Adapters.SQL.Sandbox.mode(AshAi.TestRepo, :manual)
