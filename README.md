# EURACE Housing Market Model

Version: December 2021

This is the source code of a housing market model based on the [EURACE@Unibi](http://www.wiwi.uni-bielefeld.de/lehrbereiche/vwl/etace/Eurace_Unibi/) model, a large-scale agent-based macroeconomic model. The model has been extended by incoorperating a housing, rental and mortgage market in order to analyze the effect of macroprudential policy measures.

## Getting Started

These instructions will allow you to run the model on your system.

### System Requirements and Installation

To run the code you need to install **[Julia](https://julialang.org/)** (v1.7.2). Additionally, the following packages need to be installed:

* [Agents](https://juliadynamics.github.io/Agents.jl/stable/) - Version 5.4.0
* [ArgParse](https://argparsejl.readthedocs.io/en/latest/argparse.html) - Version 1.1.4
* [CSV](https://csv.juliadata.org/stable/) - Version 0.8.4
* [DataFrames](https://juliadata.github.io/) - Version 0.22.7
* [DataStructures](https://juliacollections.github.io/DataStructures.jl/latest/) - Version 0.18.9
* [Distributions](https://github.com/JuliaStats/Distributions.jl) - Version 0.24.16
* [GLM](https://github.com/JuliaStats/GLM.jl) - Version 1.4.1
* [Plots](http://docs.juliaplots.org/) - Version 1.15.3
* [StatsBase](https://juliastats.org/StatsBase.jl/stable/) - Version 0.33.5
* [StatsPlots](https://github.com/JuliaPlots/StatsPlots.jl) - Version 0.14.19

In order to install a package, start *julia* and execute the following command:

```
using Pkg; Pkg.add("<package name>")
```

### Running The Model

The model implementation is located in the *model/* folder. In order to run the model, the initial state has to be set-up. Our baselinite initialization is specified in the *experiments/baseline_init.jl* file. By default, the subset of data stored during a simulation run is defined in the *experiments/data_collection_full.jl* file.

To run a single simulation, use the command:

```
julia main.jl <no_of_iterations>
```

After the simulation has finished, the program will automatically create a snaphsot of the last state and produce plots which will be stored in the *data/* folder. Snaphsots can be used to continue the simulation from a certain state and may be used as the initial state for a set of experiments. For an example on how to start from a snaphsot, see the *experiments/baseline_init_from_snapshot.jl* file.

To conduct different experiments and execute several runs of the model (batches) in parallel, execute *run_exp.jl*. This requires to set-up the experiment(s) in a configuration file, see *experiments/experiments_paper.jl* as an example. In order to execute an experiment, use the following command:

```
julia -p <no_cpus> run_exp.jl <config-file> [--chunk <i>] [--no_chunks <n>]
```

The julia parameter *-p <no_cpus>* specifies how many cpu cores will be used in parallel. The *--chunk* and *--no_chunk* parameters are optional and can be used to break up the experiment into several chunks, e.g. to distribute execution among different machines.

Plots from experiments can be created by using the following command:

```
julia plot_exp.jl <config-file>
```

By default, data and plots will be stored in the *data/* folder.


## Replication

To reproduce the results from the paper by re-simulating the model, use the following command:

```
julia -p <no_cpus> run_exp.jl experiments/experiments_paper.jl
```

The resulting data will be stored in *data/experiments_paper/*, which by default contains the data used to create the plots in the paper. 

In order to recreate all plots from the paper, run:

```
julia plots_paper.jl experiments/experiments_paper.jl
```

## Author

Dirk Kohlweyer

## Further Links

* [ETACE](http://www.wiwi.uni-bielefeld.de/lehrbereiche/vwl/etace/) - Chair for Economic Theory and Computational Economics
* [EURACE@Unibi](http://www.wiwi.uni-bielefeld.de/lehrbereiche/vwl/etace/Eurace_Unibi/) - description of the EURACE@Unibi model
* [Dawid et al. 2019](https://pub.uni-bielefeld.de/record/2915598) - Dawid, H., Harting, P., van der Hoog, S., & Neugart, M. (2019). Macroeconomics with heterogeneous agent models: Fostering transparency, reproducibility and replication. Journal of Evolutionary Economics.