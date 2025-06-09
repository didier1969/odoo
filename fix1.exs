#!/usr/bin/env elixir

defmodule MixExsFix do
  def run do
    IO.puts("🔧 Fixing mix.exs application configuration...")

    case File.read("mix.exs") do
      {:ok, content} ->
        fixed_content = fix_application_config(content)

        File.write!("mix.exs", fixed_content)
        IO.puts("✅ mix.exs updated successfully!")
        validate_fix()

      {:error, _reason} ->
        IO.puts("❌ Could not read mix.exs")
        create_simple_mix_exs()
    end
  end

  defp fix_application_config(content) do
    content
    |> String.replace("JobShopScheduler.Application", "JSS.Application")
    |> String.replace(":job_shop_scheduler", ":jss")
  end

  defp create_simple_mix_exs do
    IO.puts("📝 Creating simple mix.exs...")

    lines = [
      "defmodule JSS.MixProject do",
      "  use Mix.Project",
      "",
      "  def project do",
      "    [",
      "      app: :jss,",
      "      version: \"0.1.0\",",
      "      elixir: \"~> 1.14\",",
      "      start_permanent: Mix.env() == :prod,",
      "      deps: deps()",
      "    ]",
      "  end",
      "",
      "  def application do",
      "    [",
      "      mod: {JSS.Application, []},",
      "      extra_applications: [:logger]",
      "    ]",
      "  end",
      "",
      "  defp deps do",
      "    [",
      "      {:phoenix, \"~> 1.7.14\"},",
      "      {:ecto_sql, \"~> 3.10\"},",
      "      {:postgrex, \">= 0.0.0\"},",
      "      {:jason, \"~> 1.2\"}",
      "    ]",
      "  end",
      "end"
    ]

    content = Enum.join(lines, "\n")
    File.write!("mix.exs", content)
    IO.puts("✅ Created simple mix.exs")
  end

  defp validate_fix do
    IO.puts("🔍 Testing compilation...")

    case System.cmd("mix", ["compile", "--force"], stderr_to_stdout: true) do
      {_output, 0} ->
        IO.puts("✅ Compilation successful!")
        IO.puts("🎉 Try: iex -S mix")

      {output, _} ->
        IO.puts("❌ Compilation issues:")
        IO.puts(String.slice(output, -200, 200))
    end
  end
end

MixExsFix.run()
