# Revolutionary Job Shop Scheduler - Elixir Actor-Based Architecture

## Conceptual Vision

This system revolutionizes traditional job shop scheduling by combining:
- A distributed actor model where each entity (machine, task, pool, order) is an autonomous process
- Continuous parallel optimization using all available CPU cores
- Degressive temporal rigidity (ultra-rigid short-term, flexible long-term)
- Real-time operator feedback integrated into the optimization loop
- Order-based sequencing with atomic movements for optimal global solutions

## Problem Dimensions

### Scale
- **1000 machines** distributed across specialized pools
- **5000 production orders** for 500 different articles
- **~30,000 tasks** (1-10 tasks per order, sequential)
- **Temporal horizon**: 2 years with active optimization on 3 months

### Temporal Constraints
- **D+0 to D+30**: Quasi-frozen planning (enormous modification cost)
- **D+30 to D+90**: Active optimization with continuity constraints
- **D+90 to 2 years**: Coarse allocation for investment planning

## Entity Architecture

### Machines
- **Specific type**: each machine belongs to a technical type
- **Pool membership**: grouping by business specialization
- **Individual calendar**: 0 to 24 hours capacity per day (any value), granularity in seconds
- **Parallel capability**: some machines can work in parallel with overlapping tasks
- **Unit vs Parallel**:
  - Unit machines: one task at a time
  - Parallel machines: multiple overlapping tasks, capacity consumed sequentially
- **Wait time parameter**: configurable delay (normally zero, adjustable for parallel machines)
- **Autonomous GenServer process** managing its state and availability

### Tasks
- **Required machine type**: optimal type for execution
- **Production order**: mandatory sequentiality (task N+1 after end of N)
- **Produced article**: determines optimal execution pool
- **Duration**: 
  - Unit machines: duration in seconds
  - Parallel machines: duration in working days (with decimals)
- **Immutability constraint**: started tasks cannot be modified
- **GenServer process** negotiating optimal placement

### Articles and Pools
- **500 articles** distributed in families
- **Machine pools**: specialization by article family
- **Pool hierarchy**: superior pools can handle inferior pools' work
- **No overlap**: each machine belongs to a single pool
- **Technology rates**: each technology has an hourly rate in CHF

### Production Orders
- **Strict sequentiality**: tasks of the same order are sequential
- **Business properties**: priorities, delivery dates, special constraints
- **Order index**: determines processing sequence for all orders
- **Index-based sequencing**: all operations follow order index position

## Multi-Objective Cost Model

### Global Score Function
```
Score = (Delays × delay_weight) + (Advances × advance_weight) + 
        (Setup_Times × setup_weight) + (Pool_Overcost) + (Hierarchy_Overcost)
```

### Cost Components

#### Delays and Advances
- **Delay**: configurable weight per second of delay
- **Advance**: configurable weight per second of advance
- Objective: minimize deviations from target date

#### Setup/Changeover Times
- **Matrix per machine type**: transition time article A → article B
- **Range**: configurable from seconds to days depending on complexity
- **Optimization**: intelligent sequencing to minimize changeovers
- **Exception**: no setup if same article on same machine in sequence

#### Pool Overcost (Spillover)
- **Technology rate difference**: `Task_duration × (Rate_TechA - Rate_TechB)`
- Applied when a task executes outside its optimal pool
- Based on theoretical task duration

#### Hierarchical Overcost (Machine)
- **Configurable flat rate** per task
- Applied when using a superior machine type
- Fixed cost regardless of duration

## Revolutionary Optimization Architecture

### Order Index System

#### Core Concept
Experience shows individual task optimization yields poor results. Instead:
- **Order processing index**: determines sequence for all orders
- **Sequential processing**: orders are processed according to index position
- **Task sequencing**: operations follow both order index and internal task sequence
- **Global coherence**: ensures optimal global solution vs local optimizations

#### Atomic Movements
Only two types of atomic movements possible:
1. **Task reassignment**: assign task to another compatible machine
2. **Order swap**: swap two orders in the processing index

#### Constraints
- Tasks on a machine always follow ascending index order
- Started tasks cannot be moved
- Order swaps affect all tasks of both orders

### Specialized Optimization Algorithms

#### Simulated Annealing on Permutations
```elixir
SimulatedAnnealingActor.State:
  - current_order_index
  - current_temperature
  - cooling_schedule
  - swap_probability_matrix
  - critical_task_weights
```

**Responsibilities**:
- Order index optimization through random swaps
- Temperature-based acceptance of degrading solutions
- Higher visit frequency for short-deadline/high-cost operations
- Adaptive cooling based on improvement rate

#### Variable Neighborhood Search (VNS)
```elixir
VNSActor.State:
  - current_neighborhood
  - order_index_state
  - machine_assignment_state
  - neighborhood_change_criteria
```

**Responsibilities**:
- Alternates between order index and machine assignment optimization
- Neighborhood 1: adjacent/distant order swaps
- Neighborhood 2: machine reassignment for critical orders
- Changes neighborhood when local optimum reached

#### Hybrid 2-Phase Algorithm
```elixir
HybridActor.State:
  - phase_1_optimizer (index optimization)
  - phase_2_optimizer (machine assignment)
  - convergence_criteria
  - phase_switch_threshold
```

**Responsibilities**:
- Phase 1: optimizes order index (adaptive sorting algorithm)
- Phase 2: optimizes machine assignments (modified Hungarian algorithm)
- Loops between phases until convergence
- Prioritizes global solution coherence

### Algorithm Coordination

#### Multi-Algorithm Orchestrator
```elixir
OptimizationCoordinator.State:
  - active_algorithms
  - algorithm_selection_strategy
  - performance_metrics
  - time_slice_allocation
  - stopping_criteria
```

**Selection Strategies**:
- **Parallel execution**: all algorithms run simultaneously
- **Sequential time slices**: configurable time allocation per algorithm
- **Dynamic selection**: choose best performer based on recent results
- **Hybrid approach**: combine solutions from multiple algorithms

## Communicating Actor Model

### Machine Actors (GenServer)
```elixir
MachineActor.State:
  - machine_id
  - machine_type
  - pool_id
  - technology_rate_chf_per_hour
  - calendar (capacity per day in seconds)
  - is_parallel_capable
  - wait_time_seconds
  - current_tasks (for parallel machines)
  - current_task (for unit machines)
  - task_queue
  - setup_state (current_article, remaining_time)
```

**Responsibilities**:
- Calendar and availability management
- Negotiation with tasks requesting placement
- Setup time calculation based on previous article
- Cost calculation based on technology rates
- Parallel capacity consumption tracking
- State communication to optimizers

### Task Actors (GenServer)
```elixir
TaskActor.State:
  - task_id
  - order_id
  - order_index_position
  - required_machine_type
  - article_id (determines optimal pool)
  - duration_seconds (unit) / duration_days (parallel)
  - dependencies (previous tasks)
  - assigned_machine
  - status (:waiting, :setup, :running, :completed, :immutable)
  - cost_calculation
```

**Responsibilities**:
- Placement negotiation with machines
- Cost calculation based on assignment (pool + hierarchy)
- Communication with dependent tasks
- Status updates based on operator feedback
- Immutability enforcement for started tasks

### Order Actors (GenServer)
```elixir
OrderActor.State:
  - order_id
  - index_position
  - priority
  - delivery_date
  - tasks_list
  - status
  - properties
```

**Responsibilities**:
- Index position management
- Task sequence coordination
- Priority and delivery date tracking
- Communication during index swaps

### Pool Actors (GenServer)
```elixir
PoolActor.State:
  - pool_id
  - machines_by_type (Map)
  - hierarchy_level
  - parent_pools
  - child_pools
  - technology_rates
  - load_balancing_strategy
```

**Responsibilities**:
- Pool machine orchestration
- Spillover management to parent pools
- Load and availability calculation by type
- Inter-pool communication for balancing
- Technology rate management

## Real-Time Feedback System

### Operator Timestamping
Operators can timestamp at any time:
- **Task start**: start confirmation
- **Setup progress**: changeover percentage
- **Setup completion**: effective production start
- **Quantity produced**: production progress
- **Task completion**: termination confirmation
- **Problem codes**: predefined codes with free text field

### Problem Code System
```elixir
ProblemCode.Schema:
  - code_id
  - code_name
  - description
  - category
  - is_active
  
ProblemReport.Schema:
  - report_id
  - problem_code_id
  - entity_type (:task, :machine, :order)
  - entity_id
  - free_text
  - timestamp
  - operator_id
```

### Planning Impact
Each timestamp triggers:
1. **Immediate update** of task state
2. **Dependency recalculation**: impact on subsequent tasks in same order
3. **Deviation evaluation**: comparison between forecast vs actual
4. **Conditional triggering** of reoptimization if significant deviation

### Machine Management Events
Real-time events handled:
- **Add/remove machine**: dynamic machine pool updates
- **Calendar modification**: availability changes
- **Add/remove order**: production plan updates
- **Task modification/deletion**: planning adjustments

## Multi-Granularity Temporal Management

### Continuous Updates (configurable interval)
- **Configurable timer**: Process.send_after with adaptable interval
- **Virtual progress**: task advancement based on current time
- **Real-time perception**: operators see a "living" planning
- **Automatic snapshots**: SQL backup at each cycle

### Permanent Optimization
- **Dedicated process**: continuous background optimization
- **Maximum utilization**: all available CPU cores
- **Intelligent interruption**: stop/resume based on priority events
- **Incremental improvement**: start from current solution, not from zero
- **Critical task focus**: higher visit frequency for short-deadline/high-cost operations

## Persistence and Rollback

### SQL Snapshots
```sql
CREATE TABLE planning_snapshots (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    snapshot_type VARCHAR(20) NOT NULL, -- 'full' or 'partial'
    planning_state JSONB NOT NULL,
    parameters JSONB,
    optimization_score DECIMAL,
    active_algorithm VARCHAR(50),
    created_by VARCHAR(50), -- 'timer' or 'event'
    INDEX (timestamp),
    INDEX (snapshot_type)
);
```

### Backup Policy
- **Full snapshots**: every N minutes (configurable)
  - Complete planning state serialized
  - All parameters and detailed tasks
- **Partial snapshots**: every Y minutes (configurable)  
  - Only parameters and detailed tasks
  - Lighter backup for frequent saves
- **Rollback capability**: restore any snapshot
- **Automatic rotation**: deletion of old snapshots

## Configurable Parameters System

### Parameter Categories

#### SQL Configuration
```sql
CREATE TABLE system_parameters (
    id SERIAL PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    parameter_name VARCHAR(100) NOT NULL,
    parameter_value TEXT NOT NULL,
    data_type VARCHAR(20) NOT NULL,
    description TEXT,
    is_hot_reloadable BOOLEAN DEFAULT true,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    UNIQUE(category, parameter_name)
);
```

#### Optimizer Parameters
- `delay_weight`: cost per second of delay
- `advance_weight`: cost per second of advance  
- `setup_weight`: setup time cost multiplier
- `hierarchy_flat_rate`: fixed cost for superior machine usage
- `optimization_interval_seconds`: timer interval for updates
- `algorithm_time_slice_seconds`: time allocation per algorithm
- `stopping_criteria_*`: convergence thresholds
- `critical_task_visit_multiplier`: frequency boost for critical tasks

#### Demo Data Parameters
- `demo_machine_count`: number of demo machines
- `demo_order_count`: number of demo orders
- `demo_article_count`: number of demo articles
- `demo_task_duration_range`: min/max task durations

#### System Parameters
- `snapshot_full_interval_minutes`: full backup frequency
- `snapshot_partial_interval_minutes`: partial backup frequency
- `websocket_push_interval_seconds`: real-time update frequency
- `gantt_filter_*`: display filters configuration

#### UI Parameters
- `gantt_time_scale`: display granularity
- `filter_default_*`: default filter values
- `problem_codes_*`: predefined problem code definitions

### Hot Configuration System
```elixir
ParameterManager.State:
  - cached_parameters
  - subscribers (processes to notify on changes)
  - reload_strategies
```

**Hot Reload Capabilities**:
- Parameter changes via Phoenix LiveView admin interface
- Immediate notification to affected processes
- No system restart required
- Validation before application

## Phoenix LiveView Frontend

### Real-Time Gantt Visualization
```elixir
GanttLive.State:
  - machines_filter
  - time_range_filter
  - article_filter
  - order_filter
  - zoom_level
  - websocket_updates
```

**Features**:
- **Real-time updates**: WebSocket push from backend
- **Smart filtering**: avoid display overload
- **Zoom capabilities**: second to month granularity
- **Status indicators**: task progress, setup phases
- **Interactive elements**: hover for details, click for actions

### Administrative Interface
```elixir
AdminLive.State:
  - parameter_categories
  - active_algorithms
  - performance_metrics
  - system_health
```

**Capabilities**:
- **Parameter management**: hot configuration changes
- **Algorithm control**: start/stop/configure optimizers
- **Performance monitoring**: real-time metrics display
- **System health**: process supervision status

## Inter-Process Communication

### Message Types
```elixir
# Placement negotiation
{:request_placement, task_id, constraints, callback_pid}
{:placement_offer, machine_id, cost, start_time, setup_time}
{:accept_placement, task_id, machine_id}
{:reject_placement, task_id, reason}

# State updates
{:task_status_update, task_id, new_status, progress}
{:machine_availability_change, machine_id, new_calendar}
{:order_index_swap, order_1_id, order_2_id}
{:optimization_improvement, algorithm, old_score, new_score}

# System events
{:new_order, order_data}
{:priority_change, order_id, new_priority}
{:machine_added, machine_data}
{:machine_removed, machine_id}
{:parameter_updated, category, parameter_name, new_value}

# Problem reporting
{:problem_reported, entity_type, entity_id, problem_code, free_text}
```

### OTP Supervision
```
JobShopSupervisor
├── PlanningStateSupervisor
│   ├── MachineActorSupervisor (DynamicSupervisor)
│   ├── TaskActorSupervisor (DynamicSupervisor)
│   ├── OrderActorSupervisor (DynamicSupervisor)
│   └── PoolActorSupervisor (DynamicSupervisor)
├── OptimizationSupervisor
│   ├── SimulatedAnnealingActor
│   ├── VNSActor
│   ├── HybridActor
│   └── OptimizationCoordinator
├── TimingSystemSupervisor
│   ├── TimerActor (periodic updates)
│   ├── SnapshotActor (SQL backup)
│   └── ParameterManager (hot configuration)
├── EventSystemSupervisor
│   ├── OperatorFeedbackActor
│   ├── ExternalEventActor
│   └── ProblemReportingActor
└── WebSupervisor
    ├── Phoenix.Endpoint
    ├── GanttLive
    └── AdminLive
```

## Implementation Specificities

### Performance
- **Lightweight processes**: thousands of simultaneous GenServers
- **Asynchronous communication**: no blocking between actors
- **Distribution ready**: architecture prepared for multi-node
- **Integrated monitoring**: performance metrics per component

### Fault Tolerance
- **OTP supervision**: automatic process restart
- **Persisted state**: recovery from last snapshot
- **Error isolation**: actor failure doesn't affect others
- **Graceful degradation**: possible degraded operation

### Extensibility
- **Dynamic addition**: new machines/tasks without restart
- **Hot-reload configuration**: parameter modification without restart
- **Pluggable algorithms**: addition of new optimizers
- **Event API**: external system integration

## Revolutionary Innovation Points

1. **Distributed negotiation**: tasks directly negotiate with machines
2. **Continuous optimization**: permanent improvement vs periodic batch
3. **Temporal rigidity**: change cost function of horizon
4. **Integrated feedback**: closed loop with operators
5. **Multi-algorithm**: real-time comparison and hybridization
6. **Communicating actors**: each entity is autonomous and intelligent
7. **Order-based sequencing**: global solution prioritization
8. **Atomic movements**: only two movement types for optimal convergence
9. **Hot configuration**: all parameters adjustable without restart
10. **Real-time visualization**: living Gantt with WebSocket updates

This revolutionary architecture transforms a static optimization problem into a living, adaptive, and distributed system, fully exploiting Elixir's unique capabilities and the actor model while ensuring optimal global solutions through intelligent order sequencing.