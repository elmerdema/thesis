# Predicting Quality of Experience (QoE) in the Data Plane using Machine Learning

## Overview

This repository contains the research, code, and source documents for my thesis exploring in-network video Quality of Experience (QoE) prediction. With video streaming, particularly UHD and 4K, comprising the vast majority of global IP traffic, network operators need efficient tools to manage network resources while satisfying user demands. Traditional Video Quality Assessment (VQA) methods, whether subjective or objective, can often be too slow, expensive, or impractical for real-time applications at scale.

This thesis attempts to tackle these obstacles and demonstrates the feasibility and performance of predicting video QoE directly from encrypted traffic within the data plane. By extracting network-layer telemetry and estimating buffering-related events (such as stalling and depletion), we apply Machine Learning (ML) techniques to forecast application-level performance without requiring application-layer inspection or creating privacy concerns.

## Acknowledgements

I would like to express my sincere gratitude to my supervisor, **Professor Andreas Kassler**, for his invaluable guidance and support throughout this thesis.

I am also deeply thankful to my lab partner, **Juled Zaganjori**, and research scientist **Lukas Froschauer** for their close collaboration.

Finally, special thanks to **Jonathan Langlet** and the **Pforest team** for providing the foundational initial translator, reporter code, and pforest architecture, which were instrumental in the successful completion of this work.

---
*Elmer Dema*

## Methodology & Benchmarking

The core of this work consists of translating high-level Machine Learning models into low-level data plane programming for P4-programmable switches (specifically, the Tofino 2 architecture). By utilizing MARINA telemetry, we demonstrate that Random Forest models can perform line-rate, in-network inferences at terabit speeds.

## Repository Structure

The project is organized into the following main directories:

*   **`benchmarks/`**: Output data, evaluation metrics, and hardware allocation logs generated from experimental runs.
*   **`code/`**: Python scripts for Machine Learning model training, automated benchmarking pipelines, and data visualization.
*   **`data/`**: Datasets and parsed network telemetry used for model training and evaluation.
*   **`p4/`**: P4 source code representing the data plane implementation.
*   **`scripts/`**: Utility scripts for environment management and automation.
*   **`templates/`**: Configuration templates utilized by the code generation pipeline.
*   **`typst/`**: Typst source files and templates used to typeset the thesis document. The main compiled thesis document can be found at: **[`typst/0.1.4/template/main.pdf`](typst/0.1.4/template/main.pdf)**.

Our experiments illustrate the multi-dimensional trade-offs between improving ML metrics (test accuracy, F1 Score) and combating the strict hardware limitations of modern programmable switches (SRAM, TCAM, VLIW instructions, and the 20-stage pipeline limit). The thesis concludes that through principled hyperparameter scaling and intelligent feature selection based on Gini importance, robust ML models can be successfully fitted and executed entirely within the network infrastructure.
