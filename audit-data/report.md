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

### [H-#] `TSwapPool::deposit` is missing deadline validation, causing transactions to execute even after their deadline has passed

**Description:** The `deposit` function accepts a `deadline` parameter, but it is never actually checked anywhere inside the function body:

```javascript
function deposit(
    uint256 wethToDeposit,
    uint256 minimumLiquidityTokensToMint,
    uint256 maximumPoolTokensToDeposit,
@>  uint64 deadline
)
    external
    revertIfZero(wethToDeposit)
    returns (uint256 liquidityTokensToMint)
{
    if (wethToDeposit < MINIMUM_WETH_LIQUIDITY) {
        revert TSwapPool__WethDepositAmountTooLow(
            MINIMUM_WETH_LIQUIDITY,
            wethToDeposit
        );
    }
    // ... rest of function never references `deadline`
```

Every other state-changing function in the codebase that accepts a `deadline` parameter (`swapExactInput`, `swapExactOutput`, `withdraw`) applies the `revertIfDeadlinePassed(deadline)` modifier to enforce it:

```javascript
modifier revertIfDeadlinePassed(uint64 deadline) {
    if (deadline < uint64(block.timestamp)) {
        revert TSwapPool__DeadlineHasPassed(deadline);
    }
    _;
}
```

`deposit` is conspicuously missing this modifier, despite accepting the same `deadline` parameter and clearly being intended to support the same protection.

**Impact:** A user submitting a `deposit` transaction with a specific deadline in mind (e.g., "only execute this within the next block or two, otherwise the market may have moved") has no actual guarantee that their transaction will be rejected after that point. If the transaction sits in the mempool and is mined much later — whether due to network congestion, a miner/validator deliberately delaying it, or simple bad luck — it will still execute using whatever pool reserves exist at that later time, even though the user's intended deadline has long since passed.

This exposes depositors to unexpected slippage and MEV-style manipulation: a malicious actor (or miner) can hold a pending deposit transaction and strategically time its inclusion to a block where the pool's reserve ratio is less favorable to the depositor, since there is no on-chain mechanism forcing the deposit to be rejected once the user's intended time window has elapsed. While `minimumLiquidityTokensToMint` and `maximumPoolTokensToDeposit` do offer some slippage protection, they don't address the core issue that the transaction can be executed at an arbitrary, unbounded point in the future.

**Proof of Concept:**

1. A user calls `deposit(wethAmount, minLpTokens, maxPoolTokens, deadline)`, setting `deadline` to a timestamp representing "the next block or two."
2. Due to network conditions (or deliberate action by a block producer), the transaction is not mined until significantly later — well past `deadline`.
3. The transaction still executes successfully, since `deadline` is never checked, potentially depositing at a much less favorable pool ratio than the user intended when they signed the transaction.

**Recommended Mitigation:** Apply the existing `revertIfDeadlinePassed` modifier to `deposit`, consistent with every other state-changing function in the contract:

```diff
    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint,
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline
    )
        external
        revertIfZero(wethToDeposit)
+       revertIfDeadlinePassed(deadline)
        returns (uint256 liquidityTokensToMint)
    {
```

### [H-#] `TSwapPool::getInputAmountBasedOnOutput` uses an incorrect scaling constant, causing users to be overcharged on every `swapExactOutput` and `sellPoolTokens` call

**Description:** `getInputAmountBasedOnOutput` calculates how much input a user must supply to receive a desired output amount, applying the protocol's 0.3% swap fee in the process:

```javascript
function getInputAmountBasedOnOutput(
    uint256 outputAmount,
    uint256 inputReserves,
    uint256 outputReserves
)
    public
    pure
    revertIfZero(outputAmount)
    revertIfZero(outputReserves)
    returns (uint256 inputAmount)
{
    return
        ((inputReserves * outputAmount) * 10000) /
@>      ((outputReserves - outputAmount) * 997);
}
```

Compare this to the sibling pricing function, `getOutputAmountBasedOnInput`, which correctly applies the same 0.3% fee using a `997/1000` scaling factor:

```javascript
function getOutputAmountBasedOnInput(
    uint256 inputAmount,
    uint256 inputReserves,
    uint256 outputReserves
)
    public
    pure
    ...
{
    uint256 inputAmountMinusFee = inputAmount * 997;
    uint256 numerator = inputAmountMinusFee * outputReserves;
    uint256 denominator = (inputReserves * 1000) + inputAmountMinusFee;
    return numerator / denominator;
}
```

`getInputAmountBasedOnOutput` uses `10000` instead of the correct `1000` as its scaling denominator. This is not a stylistic inconsistency — it's a mathematical error that changes the effective fee charged from the intended 0.3% to a dramatically higher, incorrect rate.

**Impact:** Every user who calls `swapExactOutput` (and, by extension, `sellPoolTokens`, which wraps `swapExactOutput`) is charged significantly more input tokens than the protocol's advertised 0.3% fee actually requires. Instead of paying `input * 1000/997` (≈0.3009% effective fee) to receive their desired output, users are forced to pay `input * 10000/997` — roughly **10x** the correct amount relative to the intended fee structure.

This is a direct, silent overcharge on every single `swapExactOutput` transaction. Depending on the specific reserve ratios involved, this can result in users paying dramatically more than expected for a given output, and represents a significant and consistent value leak away from users and toward whichever side of the pool benefits from the miscalculated ratio.

**Proof of Concept:**

Consider a pool with `inputReserves = 100e18` and `outputReserves = 100e18`, and a user wants `outputAmount = 1e18`:

- **Correct formula (mirroring `getOutputAmountBasedOnInput`'s fee logic, using `1000` instead of `10000`):**
  `inputAmount = (100e18 * 1e18 * 1000) / ((100e18 - 1e18) * 997) ≈ 1.0107e18`

- **Actual (buggy) formula, as currently implemented:**
  `inputAmount = (100e18 * 1e18 * 10000) / ((100e18 - 1e18) * 997) ≈ 10.107e18`

The buggy version demands roughly **10x** the input tokens the correctly-scaled fee formula would require for the same output.

<details>
<summary>PoC</summary>

```javascript
function test_getInputAmountBasedOnOutputOverchargesUser() public view {
    uint256 outputAmount = 1e18;
    uint256 inputReserves = 100e18;
    uint256 outputReserves = 100e18;

    uint256 actualInput = pool.getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);

    // What the input SHOULD be if the fee were correctly scaled by 1000, not 10000
    uint256 correctInput = ((inputReserves * outputAmount) * 1000) / ((outputReserves - outputAmount) * 997);

    console2.log("Actual (buggy) input required: ", actualInput);
    console2.log("Correct input required: ", correctInput);

    assertGt(actualInput, correctInput * 9); // confirms roughly 10x overcharge
}
```

Run:
```bash
forge test --mt test_getInputAmountBasedOnOutputOverchargesUser -vv
```

</details>

**Recommended Mitigation:** Correct the scaling constant to `1000`, matching the fee logic used in `getOutputAmountBasedOnInput`:

```diff
    function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
        return
-           ((inputReserves * outputAmount) * 10000) /
+           ((inputReserves * outputAmount) * 1000) /
            ((outputReserves - outputAmount) * 997);
    }
```