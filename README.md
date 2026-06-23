# Fishery Escrow Smart Contract

> Supporting artefacts for:
> **"From Dispute to Valorization: Smart Contract Escrow Governance and Circular Value Creation in Fishery Supply Chains"**
> Submitted to *Supply Chain Management: An International Journal* (Emerald)
> Special Issue: *Digital Technologies as Catalysts for Value Creation in Circular Economy Systems*
> Guest Editors: Umair Tanveer & Stefan Seuring

---

## Overview

This repository contains the Solidity smart contract source code and complete transaction-level execution dataset supporting the techno-economic evaluation reported in the paper. The artefacts implement a four-component escrow governance architecture that couples quality-based Service Level Agreement (SLA) enforcement with deterministic circular routing logic for rejected fishery batches.

The system addresses the "Enforcement Gap" in fishery supply chains — the structural disconnect between quality evidence and financial settlement — by executing payment release, proportional penalty, or circular re-routing to pre-registered valorization partners (fishmeal processors, biogas facilities) within a single on-chain governance transaction.

This repository is provided for research review, reproducibility verification, and independent on-chain validation of the reported results.

---

## Repository Structure

fishery-escrow-smart-contract/

├── contracts/

│   └── CircularEscrowFishery.sol       # Four-component governance contract

├── data/
│   └── execution_results_1985tx.csv    # Full execution dataset (1,985 transactions)

├── docs/
│   └── deployment_info.md              # Sepolia contract address & verification links

└── README.md

---

## Smart Contract

The contract file is located at:

contracts/CircularEscrowFishery.sol

It implements four interdependent governance components as described in Section 3.4 of the paper:

| Paper Component | Solidity Function | Description |
|-----------------|-------------------|-------------|
| **LotRegistry** | `recordActivity()` | Records immutable event logs — vessel identifiers, catch timestamps, GPS coordinates, and custody handoffs — establishing the provenance chain against which quality assessments are made |
| **Custody** | `updateLocation()` | Manages role-checked stakeholder transfers, ensuring each change of possession generates a verifiable on-chain record |
| **QualitySLA** | `createOrder()` | Computes a deterministic Quality Index: `QI = 100 − α·minutesAbove − β·excessDeg` (α = 2, β = 3), where a batch exceeding temperature by 5°C for 10 minutes receives QI = 65, triggering FAIL |
| **EscrowSettlement** | `evaluateAndSettle()` | Executes the financial consequence: PASS (QI ≥ 85) releases full escrow; PARTIAL (70 ≤ QI < 85) deducts a proportional penalty; FAIL (QI < 70) withholds primary payment and activates circular routing to pre-registered valorization partners |

### Settlement Logic

The three-path governance decision structure:

QI ≥ 85  →  PASS     →  Full escrow release to seller
70 ≤ QI < 85  →  PARTIAL  →  Proportional payment (penalty deducted from QI score)
QI < 70  →  FAIL     →  Primary payment withheld + salvage release + circular routing
├── Fishmeal processor (histamine < 200 ppm)
└── Biogas facility (alternative valorization path)

### Hard-Stop Boundary Condition

Expert validation (V1, fishmeal plant manager) identified a hard-stop threshold: batches with histamine exceeding 400 ppm are routed to disposal rather than valorization. This dual-threshold design (200 ppm acceptance threshold / 400 ppm hard-stop) is reflected in the contract's FAIL-routing logic.

---

## Execution Dataset

The full transaction-level dataset is located at:

data/execution_results_1985tx.csv

### Dataset Description

| Field | Description |
|-------|-------------|
| `tx_hash` | Sepolia transaction hash (independently verifiable on-chain) |
| `function` | Governance function called (`recordActivity` / `updateLocation` / `createOrder` / `evaluateAndSettle`) |
| `gas_used` | Gas consumed per transaction (raw units) |
| `settlement_time_s` | Confirmation latency in seconds |
| `qi_score` | Quality Index score (for `evaluateAndSettle` transactions) |
| `outcome` | Settlement outcome: PASS / PARTIAL / FAIL-fishmeal / FAIL-biogas |
| `projected_cost_usd` | USD-equivalent at conservative Q2 2024 mainnet conditions |

### Scenario Distribution

| Governance Function | N | Avg. Latency | Projected Cost (USD) |
|--------------------|---|--------------|----------------------|
| `recordActivity` | 609 | 14.71s | $2.81 |
| `updateLocation` | 400 | 15.60s | $2.53 |
| `createOrder` | 400 | 15.40s | $2.67 |
| `evaluateAndSettle` | 576 | 15.41s | $2.57 |
| **Total confirmed** | **1,985** | **15.23s (avg)** | **~$2.65 (avg)** |

Settlement outcomes within `evaluateAndSettle` (n = 576):

| Outcome | N | % |
|---------|---|---|
| PASS (QI ≥ 85) | 337 | ~59% |
| PARTIAL (70 ≤ QI < 85) | 180 | ~31% |
| FAIL → Fishmeal routing | 29 | ~5% |
| FAIL → Biogas routing | 30 | ~5% |

### Cost Methodology Note

All projected USD cost figures use declared mainnet assumptions under conservative Q2 2024 ETH market conditions. The Sepolia public testnet carries no real-world transaction value; cost figures are forward-looking projections, not actual expenditures. Gas units are empirically measured from confirmed testnet transactions.

---

## Deployment Information

Full deployment details including contract address and Sepolia Etherscan verification link are available in:
"From Dispute to Valorization: Smart Contract Escrow Governance and Circular Value Creation in Fishery Supply Chains"
Supply Chain Management: An International Journal (under review)

---

## License

Released for academic reproducibility and research review under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

---

## Status

Research artefact — functional validation on Ethereum Sepolia public testnet.
Provided for peer review reproducibility and independent on-chain verification.
