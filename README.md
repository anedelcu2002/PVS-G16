# PVS-G16: Design and Analysis of a Grid-tied PV-Battery System for a Data Center

A workflow for the design and performance analysis of a PV-battery system used to cover the critical load of a data center during weekly grid blackouts over a period of three years. The optimization problem formulation used for preliminary system sizing is built in MATLAB-YALMIP and solved with the Gurobi solver. The performance analysis used to verify the operation of the system is built in Simulink. For the full methodology, please see [Designing a Behind-the-Meter PV-Battery System for a Data Center](Designing%20a%20Behind-the-Meter%20PV-Battery%20System%20for%20a%20Data%20Center.pdf).

## Prerequisites

- **MATLAB R2024b and Simulink**
- **[YALMIP](https://yalmip.github.io/)**
- **[Gurobi](https://www.gurobi.com/) solver**

- ## Contributors

- PV generation profiles: Ali Eren
- Optimization problem and performance analysis: Alex Nedelcu
- Performance analysis: Alex Nedelcu, Per van der Klauw
