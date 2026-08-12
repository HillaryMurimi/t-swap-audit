**Invariant tested**: The constant-product ratio (weth/poolToken) is preserved across deposit, withdraw, and swap operations, matching the pool's own pricing formulas exactly.

*Result*: 1000 runs, 100,000 total calls (deposits, swaps, withdrawals) across randomized reserve sizes and amounts — 0 invariant violations, 0 unexpected reverts.

*Conclusion*: No evidence of rounding-error accumulation or ratio drift in TSwapPool's core deposit/withdraw/swap math under sustained fuzzing.