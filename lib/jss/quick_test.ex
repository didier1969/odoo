defmodule JSS.QuickTest do
  @moduledoc "Tests rapides pour vérifier le système JSS sans interface."
  
  require Logger

  def run_core_test do
    Logger.info("🧪 Running JSS Core Test")
    
    try do
      # Test 1: ParameterManager
      :ok = JSS.System.ParameterManager.set("test", "quick_test", 42)
      42 = JSS.System.ParameterManager.get("test", "quick_test")
      Logger.info("✅ ParameterManager working")

      # Test 2: Structures de base
      machine = JSS.Core.Machine.new("test_machine", "Test Machine", "type_a", "pool_1")
      :ok = JSS.Core.Machine.validate(machine)
      Logger.info("✅ Core structures working")

      # Test 3: SwapEvaluator
      stats = JSS.Actors.SwapEvaluator.get_statistics()
      Logger.info("✅ SwapEvaluator responding: #{inspect(stats)}")

      # Test 4: Coordinator
      status = JSS.Optimization.Coordinator.get_status()
      Logger.info("✅ Coordinator status: #{inspect(status)}")

      Logger.info("🎉 All core components working!")
      :ok
      
    rescue
      error ->
        Logger.error("❌ Core test failed: #{inspect(error)}")
        {:error, error}
    end
  end
end