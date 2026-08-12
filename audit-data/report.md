### [H-#] The swap-count reward mechanism in `TSwapPool::_swap` gives away free tokens outside the constant-product formula, breaking the core `x * y = k` invariant and draining pool reserves

**Description:** Every 10th call to `_swap` awards the caller an extra 1e18 tokens as a loyalty incentive:

```javascript
    swap_count++;
    if (swap_count >= SWAP_COUNT_MAX) {
        swap_count = 0;
        outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
    }
```

This transfer happens completely outside of, and unaccounted for by, the constant-product formula (`getOutputAmountBasedOnInput`/`getInputAmountBasedOnOutput`). The pool's reserves decrease by more than the swap's actual priced output, silently breaking the `weth * poolTokens = k` invariant the entire protocol depends on fair, manipulation-resistant pricing.

**Impact:** Every 10th swap permanently drains 1 full token (1e18) from the pool's reserves, with no corresponding payment. This value comes directly out of LP's pooled assets. An attacker can trigger this deliberately and predictably - perfoming 9 minimal swaps to advance the conter, then executing the 10th swap themselves to collect the free token - repeatedly draining the pool over time.

**Proof of Concept:** Demonstrated via invariant fuzz testing. A 10-call sequence of `swapPoolTokenForWethBasedOnOutputWeth` was found (via `forge test --mt invariant_constantProductFormulaStaysTheSameY -vvvv`) where the actual WETH reserve change (`-1000000001000000003`) diverged from the formula-predicted change (`-1000000003`) by exactly `1000000000000000000` (1e18) - precisely matching the hardcoded bonus payout, on the 10th swap in the sequence.

Run:
```bash
forge test --mt invariant_constantProductFormulaStaysTheSameY -vvvv
```

**Recommended Mitigation:** Remove the swap-count reward mechanism entirely, since it structurally conflicts with the protocol's core pricing invariant. If a loyalty/incentive mechanism is desired, fund it from a separate, dedicated rewards pool - never from the swap reserves that back the constant-product formula.