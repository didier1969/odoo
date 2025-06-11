# Script de redémarrage complet JSS
# À exécuter dans iex -S mix

# 1. Vérification de l'état du système
IO.puts("🔍 Vérification de l'état du système...")

# Test ParameterManager
try do
  JSS.System.ParameterManager.get("system", "test_param")
  IO.puts("✅ ParameterManager opérationnel")
rescue
  error -> IO.puts("❌ ParameterManager: #{inspect(error)}")
end

# Test SwapEvaluator
try do
  stats = JSS.Actors.SwapEvaluator.get_statistics()
  IO.puts("✅ SwapEvaluator opérationnel: #{inspect(stats)}")
rescue
  error -> IO.puts("❌ SwapEvaluator: #{inspect(error)}")
end

# Test Coordinator
try do
  status = JSS.Optimization.Coordinator.get_status()
  IO.puts("✅ Coordinator opérationnel: #{inspect(status)}")
rescue
  error -> IO.puts("❌ Coordinator: #{inspect(error)}")
end

# 2. Chargement des paramètres par défaut
IO.puts("\n📋 Chargement des paramètres par défaut...")
case JSS.System.ParameterManager.load_defaults() do
  :ok -> IO.puts("✅ Paramètres chargés")
  {:error, reason} -> IO.puts("❌ Erreur paramètres: #{inspect(reason)}")
end

# 3. Test rapide du core système
IO.puts("\n🧪 Test rapide des composants core...")
case JSS.QuickTest.run_core_test() do
  :ok -> IO.puts("✅ Tous les composants core OK")
  {:error, reason} -> IO.puts("❌ Erreur core: #{inspect(reason)}")
end

# 4. Test pipeline d'optimisation simple
IO.puts("\n🚀 Lancement du test pipeline simple...")
case JSS.Test.OptimizationPipelineTest.run_simple_test(
  machine_count: 5,
  order_count: 8,
  optimization_cycles: 1,
  algorithm_timeout: 5000
) do
  {:ok, report} ->
    IO.puts("✅ Test pipeline réussi!")
    IO.puts("   Score initial: #{report.initial_score}")
    IO.puts("   Statut final: #{report.final_status.coordinator_status}")

  {:error, reason} ->
    IO.puts("❌ Erreur pipeline: #{inspect(reason)}")
end

IO.puts("\n🎉 Redémarrage terminé! Système prêt pour optimisation.")
IO.puts("💡 Commandes utiles:")
IO.puts("   - JSS.Optimization.Coordinator.get_status()")
IO.puts("   - JSS.Actors.SwapEvaluator.get_statistics()")
IO.puts("   - JSS.Test.OptimizationPipelineTest.run_complete_test()")
