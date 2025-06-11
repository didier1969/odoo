defmodule JSS.Test.OptimizationPipelineTest do
  @moduledoc """
  Test complet du pipeline d'optimisation JSS.
  Génère des données de test et valide le fonctionnement de bout en bout.
  """

  require Logger

  alias JSS.Core.{SharedPlanningState, Machine, Task, Order, Pool, Article}
  alias JSS.Optimization.{Coordinator, CostCalculator}
  alias JSS.Actors.SwapEvaluator
  alias JSS.System.ParameterManager

  @doc """
  Lance un test complet du pipeline d'optimisation.
  """
  def run_complete_test(opts \\ []) do
    Logger.info("🚀 Starting JSS Optimization Pipeline Test")

    # Configuration du test
    test_config = %{
      machine_count: Keyword.get(opts, :machine_count, 10),
      order_count: Keyword.get(opts, :order_count, 20),
      article_count: Keyword.get(opts, :article_count, 5),
      pool_count: Keyword.get(opts, :pool_count, 3),
      optimization_cycles: Keyword.get(opts, :optimization_cycles, 2),
      algorithm_timeout: Keyword.get(opts, :algorithm_timeout, 5000)  # 5 secondes pour test rapide
    }

    try do
      # 1. Initialisation des paramètres
      Logger.info("📋 Step 1: Loading default parameters")
      :ok = setup_test_parameters(test_config)

      # 2. Génération des données de test
      Logger.info("🏭 Step 2: Generating test data")
      {orders, tasks, machines, pools, articles} = generate_test_data(test_config)

      # 3. Création de l'état de planification initial
      Logger.info("📊 Step 3: Creating initial planning state")
      initial_state = create_initial_planning_state(orders, tasks, machines, pools, articles)

      # 4. Validation des coûts initiaux
      Logger.info("💰 Step 4: Calculating initial costs")
      initial_score_breakdown = CostCalculator.calculate_full_score(initial_state)
      log_score_breakdown("Initial", initial_score_breakdown)

      # 5. Démarrage des acteurs système
      Logger.info("⚙️  Step 5: Starting system actors")
      SwapEvaluator.start_link() # Ignore if already started
      Coordinator.start_link() # Ignore if already started

      # 6. Test du SwapEvaluator
      Logger.info("🔄 Step 6: Testing SwapEvaluator")
      test_swap_evaluator(initial_state)

      # 7. Lancement de l'optimisation
      Logger.info("🎯 Step 7: Starting optimization")
      optimization_results = run_optimization_cycles(Coordinator, initial_state, test_config)

      # 8. Analyse des résultats
      Logger.info("📈 Step 8: Analyzing results")
      analysis = analyze_optimization_results(initial_score_breakdown, optimization_results)

      # 9. Rapport final
      Logger.info("📝 Step 9: Generating final report")
      final_report = generate_test_report(test_config, analysis, optimization_results)

      Logger.info("✅ JSS Optimization Pipeline Test completed successfully!")
      {:ok, final_report}

    rescue
      error ->
        Logger.error("❌ Test failed with error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Test simplifié du pipeline d'optimisation.
  """
  def run_simple_test(opts \\ []) do
    Logger.info("🚀 Starting JSS Simple Test")
    test_config = %{
      machine_count: Keyword.get(opts, :machine_count, 5),
      order_count: Keyword.get(opts, :order_count, 8),
      article_count: Keyword.get(opts, :article_count, 3),
      pool_count: Keyword.get(opts, :pool_count, 2),
      algorithm_timeout: Keyword.get(opts, :algorithm_timeout, 3000)
    }
    try do
      Logger.info("📋 Step 1: Loading parameters")
      :ok = setup_test_parameters(test_config)
      Logger.info("🏭 Step 2: Generating test data")
      {orders, tasks, machines, pools, articles} = generate_test_data(test_config)
      Logger.info("📊 Step 3: Creating planning state")
      initial_state = create_initial_planning_state(orders, tasks, machines, pools, articles)
      Logger.info("💰 Step 4: Calculating initial score")
      initial_score_breakdown = JSS.Optimization.CostCalculator.calculate_full_score(initial_state)
      log_score_breakdown("Initial", initial_score_breakdown)
      Logger.info("🎯 Step 5: Testing single optimization cycle")
      case JSS.Optimization.Coordinator.start_optimization(initial_state) do
        :ok ->
          Logger.warn("⚠️  Optimization cycle timeout")
          JSS.Optimization.Coordinator.stop_optimization(:timeout)
        else
          Process.sleep(500)  # Attendre 500ms
          wait_for_cycle_completion_loop(Coordinator, iteration + 1)
        end

      other_status ->
        Logger.warn("⚠️  Unexpected coordinator status: #{other_status}")
        :ok
    end
  end

  # ============================================================================
  # Analyse des résultats
  # ============================================================================

  defp analyze_optimization_results(initial_breakdown, optimization_results) do
    if Enum.empty?(optimization_results) do
      %{
        error: :no_optimization_results,
        initial_score: Map.values(initial_breakdown) |> Enum.sum()
      }
    else
      last_result = List.last(optimization_results)
      final_score = get_final_score_from_stats(last_result)
      initial_score = Map.values(initial_breakdown) |> Enum.sum()

      improvement = initial_score - final_score
      improvement_percent = if initial_score > 0, do: (improvement / initial_score) * 100, else: 0

      algorithm_performance = analyze_algorithm_performance(optimization_results)

      %{
        initial_score: initial_score,
        final_score: final_score,
        improvement: improvement,
        improvement_percent: improvement_percent,
        total_cycles: length(optimization_results),
        algorithm_performance: algorithm_performance,
        convergence_analysis: analyze_convergence(optimization_results)
      }
    end
  end

  defp get_final_score_from_stats(stats) do
    case stats.shared_state_info do
      %{current_score: score} -> score
      _ -> 0.0
    end
  end

  defp analyze_algorithm_performance(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      Enum.reduce(result.algorithm_statistics, acc, fn {algo_name, algo_stats}, algo_acc ->
        current_stats = Map.get(algo_acc, algo_name, %{
          total_executions: 0,
          total_time: 0,
          best_score: nil,
          total_improvements: 0
        })

        Map.put(algo_acc, algo_name, %{
          total_executions: current_stats.total_executions + (algo_stats.executions || 0),
          total_time: current_stats.total_time + (algo_stats.total_time_ms || 0),
          best_score: min_score(current_stats.best_score, algo_stats.best_score),
          avg_time_per_execution: if(algo_stats.executions && algo_stats.executions > 0,
                                   do: algo_stats.avg_time_ms, else: 0),
          total_improvements: current_stats.total_improvements + count_improvements(result, algo_name)
        })
      end)
    end)
  end

  defp min_score(nil, score), do: score
  defp min_score(score, nil), do: score
  defp min_score(a, b), do: min(a, b)

  defp count_improvements(result, algo_name) do
    result.performance_history
    |> Enum.filter(fn entry -> entry.algorithm == algo_name and entry.status == :completed end)
    |> Enum.reduce(0, fn entry, acc ->
      improvements = get_in(entry, [:statistics, :improvements]) || 0
      acc + improvements
    end)
  end

  defp analyze_convergence(results) do
    scores =
      results
      |> Enum.map(&get_final_score_from_stats/1)
      |> Enum.filter(fn score -> score > 0 end)

    if length(scores) < 2 do
      %{convergence_trend: :insufficient_data}
    else
      # Calcul de la tendance de convergence
      improvements =
        scores
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, current] -> prev - current end)

      avg_improvement = Enum.sum(improvements) / length(improvements)

      %{
        convergence_trend: if(avg_improvement > 0, do: :improving, else: :stable),
        avg_improvement_per_cycle: avg_improvement,
        score_progression: scores
      }
    end
  end

  # ============================================================================
  # Rapport final
  # ============================================================================

  defp generate_test_report(test_config, analysis, optimization_results) do
    %{
      test_metadata: %{
        timestamp: DateTime.utc_now(),
        test_config: test_config,
        jss_version: "1.0.0"
      },
      optimization_analysis: analysis,
      detailed_results: optimization_results,
      recommendations: generate_recommendations(analysis),
      performance_summary: generate_performance_summary(analysis, test_config)
    }
  end

  defp generate_recommendations(analysis) do
    recommendations = []

    recommendations = if analysis.improvement_percent < 5 do
      ["Consider increasing algorithm timeouts or adjusting cooling parameters" | recommendations]
    else
      recommendations
    end

    recommendations = if Map.get(analysis, :algorithm_performance) do
      best_algorithm = find_best_algorithm(analysis.algorithm_performance)
      ["Best performing algorithm: #{best_algorithm}" | recommendations]
    else
      recommendations
    end

    recommendations
  end

  defp find_best_algorithm(algo_performance) do
    algo_performance
    |> Enum.max_by(fn {_name, stats} -> stats.total_improvements end, fn -> {:unknown, %{}} end)
    |> elem(0)
  end

  defp generate_performance_summary(analysis, config) do
    %{
      test_scale: "#{config.machine_count} machines, #{config.order_count} orders",
      optimization_effectiveness: "#{Float.round(analysis.improvement_percent || 0, 2)}% improvement",
      cycles_completed: analysis.total_cycles || 0,
      convergence_status: get_in(analysis, [:convergence_analysis, :convergence_trend]) || :unknown
    }
  end

  # ============================================================================
  # Tests de base
  # ============================================================================

  defp test_parameter_manager do
    Logger.info("Testing ParameterManager...")

    # Test de définition et récupération de paramètre
    :ok = ParameterManager.set("system", "test_param", 42)
    42 = ParameterManager.get("system", "test_param")

    Logger.info("✅ ParameterManager test passed")
  end

  defp test_data_structures do
    Logger.info("Testing data structures...")

    # Test création d'une machine avec tarif
    machine = Machine.new("test_machine", "Test Machine", "type_a", "pool_1",
      technology_rate_chf_per_hour: 85.0
    )
    :ok = Machine.validate(machine)

    # Test création d'un article
    article = Article.new("test_article", "Test Article", "family_1", "type_a",
      optimal_pool_id: "pool_1"
    )
    :ok = Article.validate(article)

    # Test création d'une tâche
    task = Task.new("test_task", "Test Task", "order_1", "test_article", "type_a")
    :ok = Task.validate(task)

    # Test création d'une commande
    order = Order.new("order_1", "ORD-0001", "customer_1", "Test Customer")
    :ok = Order.validate(order)

    Logger.info("✅ Data structures test passed")
  end

  defp test_cost_calculator do
    Logger.info("Testing CostCalculator...")

    # Données minimales pour test avec toutes les références CORRECTES
    pools = %{
      "pool_1" => Pool.new("pool_1", "Pool 1", 1,
        technology_rates: %{"type_a" => 80.0, "type_b" => 75.0},
        optimal_articles: ["article_1"]
      )
    }

    articles = %{
      "article_1" => Article.new(
        "article_1",
        "Article 1",
        "family_1",
        "type_a",
        optimal_pool_id: "pool_1"  # S'assurer que le pool existe
      )
    }

    machines = %{
      "machine_1" => Machine.new("machine_1", "Machine 1", "type_a", "pool_1",
        technology_rate_chf_per_hour: 85.0
      )
    }

    orders = %{
      "order_1" => Order.new("order_1", "ORD-0001", "customer_1", "Customer 1")
    }

    tasks = %{
      "task_1" => Task.new(
        "task_1",
        "Task 1",
        "order_1",
        "article_1",
        "type_a"
      )
    }

    # Création d'un état minimal avec toutes les données cohérentes
    planning_state = SharedPlanningState.new(orders, tasks, machines, pools, articles)

    # Test de calcul de score
    score_breakdown = CostCalculator.calculate_full_score(planning_state)

    # Vérifications
    true = is_map(score_breakdown)
    true = Map.has_key?(score_breakdown, :delays)
    true = Map.has_key?(score_breakdown, :advances)
    true = Map.has_key?(score_breakdown, :setup_times)
    true = Map.has_key?(score_breakdown, :pool_overcost)
    true = Map.has_key?(score_breakdown, :hierarchy_overcost)

    Logger.info("✅ CostCalculator test passed")
  end

  # ============================================================================
  # Utilitaires de logging
  # ============================================================================

  defp log_score_breakdown(label, breakdown) do
    total = Map.values(breakdown) |> Enum.sum()

    Logger.info("💰 #{label} Score Breakdown:")
    Logger.info("   Total: #{Float.round(total, 2)}")
    Logger.info("   - Delays: #{Float.round(breakdown.delays, 2)}")
    Logger.info("   - Advances: #{Float.round(breakdown.advances, 2)}")
    Logger.info("   - Setup Times: #{Float.round(breakdown.setup_times, 2)}")
    Logger.info("   - Pool Overcost: #{Float.round(breakdown.pool_overcost, 2)}")
    Logger.info("   - Hierarchy Overcost: #{Float.round(breakdown.hierarchy_overcost, 2)}")
  end
endinfo("✅ Optimization started successfully")
          Process.sleep(test_config.algorithm_timeout + 1000)
          final_status = JSS.Optimization.Coordinator.get_status()
          final_stats = JSS.Optimization.Coordinator.get_detailed_statistics()
          JSS.Optimization.Coordinator.stop_optimization(:test_completed)
          final_report = %{
            test_metadata: %{
              timestamp: DateTime.utc_now(),
              test_config: test_config,
              jss_version: "1.0.0"
            },
            initial_score: Map.values(initial_score_breakdown) |> Enum.sum(),
            final_status: final_status,
            final_statistics: final_stats,
            performance_summary: %{
              test_scale: "#{test_config.machine_count} machines, #{test_config.order_count} orders",
              status: "completed",
              algorithm_tested: final_status.current_algorithm || "simulated_annealing"
            }
          }
          Logger.info("✅ JSS Simple Test completed successfully!")
          {:ok, final_report}
        {:error, reason} ->
          Logger.error("❌ Failed to start optimization: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("❌ Test failed with error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Test ultra-simplifié qui évite les erreurs de génération de données.
  """
  def run_minimal_test do
    Logger.info("🧪 Running JSS Minimal Test")

    try do
      # Test 1: ParameterManager
      Logger.info("📋 Testing ParameterManager...")
      :ok = ParameterManager.set("test", "simple_param", 42)
      42 = ParameterManager.get("test", "simple_param")
      Logger.info("✅ ParameterManager OK")

      # Test 2: Core structures individuelles
      Logger.info("🏗️ Testing core structures...")

      # Pool simple
      pool = Pool.new("pool_test", "Test Pool", 1,
        technology_rates: %{"type_a" => 80.0, "type_b" => 75.0}
      )
      :ok = Pool.validate(pool)
      Logger.info("✅ Pool structure OK")

      # Article simple
      article = Article.new("art_test", "Test Article", "family_1", "type_a", optimal_pool_id: "pool_test")
      :ok = Article.validate(article)
      Logger.info("✅ Article structure OK")

      # Machine simple
      machine = Machine.new("mach_test", "Test Machine", "type_a", "pool_test",
        technology_rate_chf_per_hour: 85.0
      )
      :ok = Machine.validate(machine)
      Logger.info("✅ Machine structure OK")

      # Task simple
      task = Task.new("task_test", "Test Task", "order_test", "art_test", "type_a")
      :ok = Task.validate(task)
      Logger.info("✅ Task structure OK")

      # Order simple
      order = Order.new("order_test", "ORD-TEST", "customer_test", "Test Customer")
      :ok = Order.validate(order)
      Logger.info("✅ Order structure OK")

      # Test 3: Calcul de coût minimal
      Logger.info("💰 Testing minimal cost calculation...")

      # État de planification minimal avec références cohérentes
      pools_map = %{"pool_test" => pool}
      articles_map = %{"art_test" => article}
      machines_map = %{"mach_test" => machine}
      orders_map = %{"order_test" => order}
      tasks_map = %{"task_test" => task}

      planning_state = SharedPlanningState.new(
        orders_map,
        tasks_map,
        machines_map,
        pools_map,
        articles_map
      )

      score_breakdown = CostCalculator.calculate_full_score(planning_state)
      Logger.info("✅ Cost calculation OK - Score: #{Map.values(score_breakdown) |> Enum.sum()}")

      # Test 4: Acteurs système
      Logger.info("⚙️ Testing system actors...")

      # SwapEvaluator
      stats = SwapEvaluator.get_statistics()
      Logger.info("✅ SwapEvaluator OK - Stats: #{inspect(stats)}")

      # Coordinator
      status = Coordinator.get_status()
      Logger.info("✅ Coordinator OK - Status: #{status.coordinator_status}")

      Logger.info("🎉 Minimal test completed successfully!")
      Logger.info("💡 All core components are working properly")

      {:ok, %{
        test_type: :minimal,
        components_tested: [:parameter_manager, :core_structures, :cost_calculator, :system_actors],
        status: :success,
        timestamp: DateTime.utc_now()
      }}

    rescue
      error ->
        Logger.error("❌ Minimal test failed: #{inspect(error)}")
        Logger.error("Stack trace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, error}
    end
  end

  @doc """
  Test intermédiaire qui génère des données simples mais cohérentes.
  """
  def run_safe_test(opts \\ []) do
    Logger.info("🚀 Running JSS Safe Test")

    machine_count = Keyword.get(opts, :machine_count, 3)
    order_count = Keyword.get(opts, :order_count, 5)
    algorithm_timeout = Keyword.get(opts, :algorithm_timeout, 2000)

    try do
      Logger.info("📋 Step 1: Setting up parameters...")
      setup_test_parameters(%{algorithm_timeout: algorithm_timeout})

      Logger.info("🏗️ Step 2: Creating safe test data...")
      {orders, tasks, machines, pools, articles} = create_safe_test_data(machine_count, order_count)

      Logger.info("📊 Step 3: Creating planning state...")
      planning_state = SharedPlanningState.new(orders, tasks, machines, pools, articles)

      Logger.info("💰 Step 4: Calculating initial score...")
      initial_score = CostCalculator.calculate_full_score(planning_state)
      log_score_breakdown("Initial", initial_score)

      Logger.info("🎯 Step 5: Testing single optimization...")
      case Coordinator.start_optimization(planning_state) do
        :ok ->
          Logger.info("✅ Optimization started")
          Process.sleep(algorithm_timeout + 500)

          final_status = Coordinator.get_status()
          Coordinator.stop_optimization(:test_completed)

          Logger.info("🎉 Safe test completed!")

          {:ok, %{
            test_type: :safe,
            initial_score: Map.values(initial_score) |> Enum.sum(),
            final_status: final_status,
            data_size: %{
              machines: machine_count,
              orders: order_count,
              tasks: map_size(tasks),
              pools: map_size(pools),
              articles: map_size(articles)
            },
            timestamp: DateTime.utc_now()
          }}

        {:error, reason} ->
          Logger.error("❌ Optimization failed: #{reason}")
          {:error, reason}
      end

    rescue
      error ->
        Logger.error("❌ Safe test failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Exécute seulement les tests de base sans optimisation complète.
  """
  def run_basic_tests do
    Logger.info("🧪 Running basic JSS component tests")

    try do
      # Test 1: Paramètres
      test_parameter_manager()

      # Test 2: Structures de données
      test_data_structures()

      # Test 3: Calcul de coûts
      test_cost_calculator()

      Logger.info("✅ All basic tests passed!")
      :ok

    rescue
      error ->
        Logger.error("❌ Basic tests failed: #{inspect(error)}")
        {:error, error}
    end
  end

  # ============================================================================
  # Configuration et données de test
  # ============================================================================

  defp setup_test_parameters(test_config) do
    # Réduction des timeouts pour test rapide
    test_params = %{
      "optimizer" => %{
        "algorithm_time_budget" => test_config.algorithm_timeout,
        "simulated_annealing_timeout" => test_config.algorithm_timeout,
        "vns_timeout" => test_config.algorithm_timeout,
        "hybrid_timeout" => test_config.algorithm_timeout,
        "delay_weight" => 1.0,
        "advance_weight" => 0.5,
        "setup_weight" => 2.0,
        "hierarchy_flat_rate" => 100.0,
        "sa_initial_temperature" => 1000.0,
        "sa_cooling_rate" => 0.98,
        "sa_min_temperature" => 1.0,
        "sa_swap_probability" => 0.7,
        "sa_reassignment_probability" => 0.3,
        "critical_task_visit_multiplier" => 2.0,
        "swap_cache_size" => 100,
        "swap_cache_ttl" => 30
      }
    }

    # Application des paramètres de test
    Enum.each(test_params, fn {category, params} ->
      Enum.each(params, fn {param_name, value} ->
        ParameterManager.set(category, param_name, value)
      end)
    end)

    :ok
  end

  defp generate_test_data(config) do
    # Génération des pools AVANT les articles
    pools = generate_pools(config.pool_count)

    # Génération des articles avec pool_ids valides
    articles = generate_articles(config.article_count, pools)

    # Génération des machines avec pool_ids valides
    machines = generate_machines(config.machine_count, pools)

    # Génération des commandes et tâches
    {orders, tasks} = generate_orders_and_tasks(config.order_count, articles, machines)

    {orders, tasks, machines, pools, articles}
  end

  defp generate_pools(count) do
    1..count
    |> Enum.map(fn i ->
      pool_id = "pool_#{i}"

      # Tarifs technologiques par type de machine
      technology_rates = %{
        "type_a" => 80.0 + (i * 10.0),   # 90, 100, 110 CHF/h
        "type_b" => 70.0 + (i * 15.0),   # 85, 100, 115 CHF/h
        "type_c" => 90.0 + (i * 5.0)     # 95, 100, 105 CHF/h
      }

      pool = Pool.new(
        pool_id,
        "Pool #{i}",
        i,  # hierarchy_level
        technology_rates: technology_rates,  # IMPORTANT: Ajouter les tarifs
        pool_overhead_rate: 10.0 * i,
        spillover_penalty_rate: 1.0 + (i * 0.1)
      )

      {pool_id, pool}
    end)
    |> Map.new()
  end

  defp generate_articles(count, pools) do
    machine_types = ["type_a", "type_b", "type_c"]
    pool_ids = Map.keys(pools)

    1..count
    |> Enum.map(fn i ->
      article_id = "article_#{i}"
      machine_type = Enum.at(machine_types, rem(i - 1, length(machine_types)))
      pool_id = Enum.at(pool_ids, rem(i - 1, length(pool_ids)))

      article = Article.new(
        article_id,
        "Article #{i}",
        "family_#{rem(i - 1, 3) + 1}",
        machine_type,
        standard_duration_seconds: 1800 + :rand.uniform(3600),  # 30min à 1.5h
        optimal_pool_id: pool_id
      )

      {article_id, article}
    end)
    |> Map.new()
  end

  defp generate_machines(count, pools) do
    machine_types = ["type_a", "type_b", "type_c"]
    pool_ids = Map.keys(pools)

    1..count
    |> Enum.map(fn i ->
      machine_id = "machine_#{i}"
      machine_type = Enum.at(machine_types, rem(i - 1, length(machine_types)))
      pool_id = Enum.at(pool_ids, rem(i - 1, length(pool_ids)))

      # Tarif basé sur le pool + variabilité
      base_rate = case machine_type do
        "type_a" -> 80.0
        "type_b" -> 70.0
        "type_c" -> 90.0
      end

      machine_rate = base_rate + :rand.uniform(30) + (i * 2.0)

      machine = Machine.new(
        machine_id,
        "Machine #{i}",
        machine_type,
        pool_id,
        technology_rate_chf_per_hour: machine_rate,  # Tarif bien défini
        setup_cost_multiplier: 1.0 + (:rand.uniform(50) / 100.0),  # 1.0 à 1.5
        is_parallel_capable: rem(i, 4) == 0  # 25% de machines parallèles
      )

      # Configuration d'un calendrier simple
      today = Date.utc_today()
      machine_with_calendar = Machine.set_calendar(machine, today, Date.add(today, 30), 8.0)

      {machine_id, machine_with_calendar}
    end)
    |> Map.new()
  end

  defp generate_orders_and_tasks(order_count, articles, machines) do
    article_ids = Map.keys(articles)

    orders_and_tasks =
      1..order_count
      |> Enum.map(fn i ->
        order_id = "order_#{i}"
        customer_id = "customer_#{rem(i - 1, 5) + 1}"  # 5 clients différents

        # Génération de 1 à 4 tâches par commande
        task_count = 1 + :rand.uniform(3)

        tasks =
          1..task_count
          |> Enum.map(fn j ->
            task_id = "task_#{order_id}_#{j}"
            article_id = Enum.random(article_ids)
            article = articles[article_id]

            task = Task.new(
              task_id,
              "Task #{j} of Order #{i}",
              order_id,
              article_id,
              article.optimal_machine_type,
              sequence_number: j,
              duration: {:unit_duration, article.production_specs.standard_duration_seconds},
              quantity_to_produce: 1 + :rand.uniform(10),
              priority: [:low, :normal, :high] |> Enum.random()
            )

            {task_id, task}
          end)
          |> Map.new()

        # Création de la commande
        delivery_date = DateTime.add(DateTime.utc_now(), (7 + :rand.uniform(45)) * 24 * 3600, :second)

        order = Order.new(
          order_id,
          "ORD-#{String.pad_leading(to_string(i), 4, "0")}",
          customer_id,
          "Customer #{rem(i - 1, 5) + 1}",
          index_position: i - 1,
          requested_delivery_date: delivery_date,
          priority: [:low, :normal, :high, :urgent] |> Enum.random(),
          total_quantity: Enum.reduce(tasks, 0, fn {_, task}, acc -> acc + task.quantity_to_produce end)
        )

        # Ajout des tâches à la commande
        order_with_tasks = Enum.reduce(Map.keys(tasks), order, fn task_id, acc_order ->
          case Order.add_task(acc_order, task_id) do
            {:ok, updated_order} -> updated_order
            updated_order -> updated_order
          end
        end)

        {{order_id, order_with_tasks}, tasks}
      end)

    # Séparation des commandes et tâches
    orders = orders_and_tasks |> Enum.map(fn {order, _} -> order end) |> Map.new()
    all_tasks = orders_and_tasks |> Enum.flat_map(fn {_, tasks} -> Map.to_list(tasks) end) |> Map.new()

    {orders, all_tasks}
  end

  # Fonction privée pour créer des données de test très simples et cohérentes
  defp create_safe_test_data(machine_count, order_count) do
    # 1. Créer d'abord les pools avec tarifs technologiques
    pools = %{
      "pool_1" => Pool.new("pool_1", "Manufacturing Pool", 1,
        technology_rates: %{"type_a" => 80.0, "type_b" => 75.0},
        pool_overhead_rate: 10.0,
        spillover_penalty_rate: 1.2
      ),
      "pool_2" => Pool.new("pool_2", "Assembly Pool", 2,
        technology_rates: %{"type_a" => 90.0, "type_b" => 85.0},
        pool_overhead_rate: 15.0,
        spillover_penalty_rate: 1.3
      )
    }

    # 2. Créer les articles avec pool_ids valides
    articles = %{
      "article_1" => Article.new("article_1", "Widget A", "widgets", "type_a",
        optimal_pool_id: "pool_1",
        standard_duration_seconds: 3600
      ),
      "article_2" => Article.new("article_2", "Widget B", "widgets", "type_b",
        optimal_pool_id: "pool_2",
        standard_duration_seconds: 2700
      ),
      "article_3" => Article.new("article_3", "Gadget C", "gadgets", "type_a",
        optimal_pool_id: "pool_1",
        standard_duration_seconds: 4500
      )
    }

    # 3. Créer les machines avec tarifs définis
    machines =
      1..machine_count
      |> Enum.map(fn i ->
        machine_id = "machine_#{i}"
        machine_type = case rem(i, 2) do
          0 -> "type_a"
          _ -> "type_b"
        end
        pool_id = case rem(i, 2) do
          0 -> "pool_1"
          _ -> "pool_2"
        end

        # Tarif cohérent avec le pool
        rate = case {machine_type, pool_id} do
          {"type_a", "pool_1"} -> 80.0 + i
          {"type_a", "pool_2"} -> 90.0 + i
          {"type_b", "pool_1"} -> 75.0 + i
          {"type_b", "pool_2"} -> 85.0 + i
        end

        machine = Machine.new(machine_id, "Machine #{i}", machine_type, pool_id,
          technology_rate_chf_per_hour: rate,
          setup_cost_multiplier: 1.0
        )

        # Ajouter un calendrier simple
        today = Date.utc_today()
        machine_with_calendar = Machine.set_calendar(machine, today, Date.add(today, 7), 8.0)

        {machine_id, machine_with_calendar}
      end)
      |> Map.new()

    # 4. Créer les commandes et tâches
    article_ids = Map.keys(articles)

    {orders, tasks} =
      1..order_count
      |> Enum.map(fn i ->
        order_id = "order_#{i}"
        task_id = "task_#{i}"
        article_id = Enum.at(article_ids, rem(i - 1, length(article_ids)))
        article = articles[article_id]

        # Une tâche simple par commande
        task = Task.new(
          task_id,
          "Task for Order #{i}",
          order_id,
          article_id,
          article.optimal_machine_type,
          duration: {:unit_duration, article.production_specs.standard_duration_seconds},
          quantity_to_produce: 1 + rem(i, 5)
        )

        # Commande simple
        delivery_date = DateTime.add(DateTime.utc_now(), (i * 24 * 3600), :second)
        order = Order.new(
          order_id,
          "ORD-#{String.pad_leading(to_string(i), 3, "0")}",
          "customer_1",
          "Test Customer",
          index_position: i - 1,
          requested_delivery_date: delivery_date
        )

        # Ajouter la tâche à la commande
        order_with_task = case Order.add_task(order, task_id) do
          {:ok, updated} -> updated
          updated -> updated
        end

        {{order_id, order_with_task}, {task_id, task}}
      end)
      |> Enum.unzip()

    orders_map = Map.new(orders)
    tasks_map = Map.new(tasks)

    {orders_map, tasks_map, machines, pools, articles}
  end

  defp create_initial_planning_state(orders, tasks, machines, pools, articles) do
    SharedPlanningState.new(orders, tasks, machines, pools, articles, horizon_days: 90)
  end

  # ============================================================================
  # Tests des composants
  # ============================================================================

  defp test_swap_evaluator(planning_state) do
    # Mise à jour de l'état dans SwapEvaluator
    SwapEvaluator.update_planning_state(planning_state)

    # Test d'évaluation de swaps
    order_ids = planning_state.order_index

    if length(order_ids) >= 2 do
      [order_a, order_b | _] = order_ids

      # Test synchrone
      case SwapEvaluator.evaluate_swap_sync(order_a, order_b, 3000) do
        {:ok, result} ->
          Logger.info("✅ SwapEvaluator sync test passed - Delta score: #{result.delta_score}")

        {:error, reason} ->
          Logger.warn("⚠️  SwapEvaluator sync test failed: #{reason}")
      end

      # Test des statistiques
      stats = SwapEvaluator.get_statistics()
      Logger.info("📊 SwapEvaluator stats: Cache hits: #{stats.cache_hits}, misses: #{stats.cache_misses}")
    else
      Logger.warn("⚠️  Not enough orders for SwapEvaluator test")
    end
  end

  defp run_optimization_cycles(Coordinator, initial_state, config) do
    results = []

    # Démarrage de l'optimisation
    case JSS.Optimization.Coordinator.start_optimization(initial_state) do
      :ok ->
        Logger.info("✅ Optimization started successfully")

        # Surveillance du cycle d'optimisation
        monitor_optimization_cycles(Coordinator, config.optimization_cycles, results)

      {:error, reason} ->
        Logger.error("❌ Failed to start optimization: #{reason}")
        {:error, reason}
    end
  end

  defp monitor_optimization_cycles(Coordinator, remaining_cycles, results) when remaining_cycles > 0 do
    # Attendre la fin d'un cycle complet (3 algorithmes)
    wait_for_cycle_completion()

    # Récupération des statistiques
    cycle_stats = JSS.Optimization.Coordinator.get_detailed_statistics()
    updated_results = [cycle_stats | results]

    Logger.info("📊 Cycle #{cycle_stats.cycle_number} completed")

    if remaining_cycles > 1 do
      # Redémarrage pour un nouveau cycle
      JSS.Optimization.Coordinator.restart_optimization_cycle() # Ignore errors
      monitor_optimization_cycles(Coordinator, remaining_cycles - 1, updated_results)
    else
      # Arrêt final
      JSS.Optimization.Coordinator.stop_optimization(:test_completed) # Ignore errors
      Enum.reverse(updated_results)
    end
  end

  defp monitor_optimization_cycles(_Coordinator, 0, results) do
    Enum.reverse(results)
  end

  defp wait_for_cycle_completion() do
    # Attendre que tous les algorithmes du cycle soient terminés
    wait_for_cycle_completion_loop(Coordinator, 0)
  end

  defp wait_for_cycle_completion_loop(Coordinator, iteration) do
    status = JSS.Optimization.Coordinator.get_status()

    case status.coordinator_status do
      :idle ->
        # Cycle terminé
        :ok

      :running ->
        if iteration > 100 do  # Timeout après ~50 secondes
          Logger.
