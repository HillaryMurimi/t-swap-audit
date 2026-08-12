/**
 * /-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\
 * |                                     |
 * \ _____    ____                       /
 * -|_   _|  / ___|_      ____ _ _ __    -
 * /  | |____\___ \ \ /\ / / _` | '_ \   \
 * |  | |_____|__) \ V  V / (_| | |_) |  |
 * \  |_|    |____/ \_/\_/ \__,_| .__/   /
 * -                            |_|      -
 * /                                     \
 * |                                     |
 * \-/|\-/|\-/|\-/|\-/|\-/|\-/|\-/|\-/|\-/
 */
// SPDX-License-Identifier: GNU General Public License v3.0
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TSwapPool is ERC20 { // The TSwapPool contract is an ERC20 token that represents a liquidity pool for swapping between a specific ERC20 token and WETH. It allows users to add and remove liquidity, as well as swap tokens within the pool. The contract maintains the invariant that the ratio of WETH, PoolTokens, and LiquidityTokens remains constant before and after transactions, ensuring fair pricing and liquidity management.
    error TSwapPool__DeadlineHasPassed(uint64 deadline); // Custom error that is thrown when a transaction is attempted after the specified deadline has passed. This is used to enforce time limits on transactions, ensuring that they are executed within a certain timeframe. @q Why? Because the user may have set a deadline for the transaction to be completed, and if that deadline has passed, the transaction should not be executed. This helps prevent unexpected outcomes or losses due to changes in market conditions or other factors that may have occurred since the transaction was initiated.
    error TSwapPool__MaxPoolTokenDepositTooHigh(
        uint256 maximumPoolTokensToDeposit,
        uint256 poolTokensToDeposit
    ); // Custom error that is thrown when the maximum amount of pool tokens a user is willing to deposit is less than the calculated amount of pool tokens required for the transaction. This ensures that users are aware of the amount of pool tokens they need to deposit and prevents them from accidentally depositing more than they intended. @q Why? Because the user may have set a maximum amount of pool tokens they are willing to deposit, and if the calculated amount of pool tokens required for the transaction exceeds that maximum, the transaction should not be executed. This helps prevent unexpected outcomes or losses due to changes in market conditions or other factors that may have occurred since the transaction was initiated.
    error TSwapPool__MinLiquidityTokensToMintTooLow(
        uint256 minimumLiquidityTokensToMint,
        uint256 liquidityTokensToMint
    ); // Custom error that is thrown when the minimum amount of liquidity tokens a user expects to mint is higher than the calculated amount of liquidity tokens to mint. This ensures that users are aware of the amount of liquidity tokens they will receive and prevents them from accidentally receiving fewer tokens than they intended. @q Why? Because the user may have set a minimum amount of liquidity tokens they expect to mint, and if the calculated amount of liquidity tokens to mint is less than that minimum, the transaction should not be executed. This helps prevent unexpected outcomes or losses due to changes in market conditions or other factors that may have occurred since the transaction was initiated.
    error TSwapPool__WethDepositAmountTooLow(
        uint256 minimumWethDeposit,
        uint256 wethToDeposit
    ); // Custom error that is thrown when the amount of WETH a user is attempting to deposit is lower than the minimum required amount. This ensures that users are aware of the minimum WETH deposit requirement and prevents them from accidentally depositing less than the required amount. @q Why? Because the pool needs a minimum amount of WETH to maintain liquidity and the invariant of the pool, and if the user attempts to deposit less than this minimum, the transaction should not be executed. This helps maintain the stability and proper functioning of the pool.
    error TSwapPool__InvalidToken();
    error TSwapPool__OutputTooLow(uint256 actual, uint256 min);// Custom error that is thrown when the actual output of a swap is lower than the minimum expected output. This ensures that users are aware of the minimum output requirement and prevents them from receiving less than they expected. @q Why? Because the user may have set a minimum acceptable output for the swap, and if the actual output is lower than this minimum, the transaction should not be executed. This helps prevent unexpected outcomes or losses due to changes in market conditions or other factors that may have occurred since the transaction was initiated.
    error TSwapPool__MustBeMoreThanZero();

    using SafeERC20 for IERC20; // The SafeERC20 library is used to safely interact with ERC20 tokens, ensuring that token transfers and approvals are handled correctly and preventing potential issues such as failed transactions or unexpected behavior. This is important for the TSwapPool contract, as it needs to securely manage token transfers when users add or remove liquidity and perform swaps within the pool.

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 private immutable i_wethToken; // Immutable variable that stores the address of the WETH token. This is used when creating new pools to facilitate swaps involving WETH. The WETH token is a wrapped version of Ether (ETH) that conforms to the ERC20 standard, allowing it to be used in smart contracts and decentralized applications that require ERC20 tokens. By storing the WETH token address as an immutable variable, the TSwapPool contract ensures that it can always reference the correct WETH token for swaps and liquidity management, maintaining consistency and reliability in its operations.
    IERC20 private immutable i_poolToken; // Immutable variable that stores the address of the pool token. This is used when creating new pools to facilitate swaps involving the specific ERC20 token that the pool manages. By storing the pool token address as an immutable variable, the TSwapPool contract ensures that it can always reference the correct pool token for swaps and liquidity management, maintaining consistency and reliability in its operations.
    uint256 private constant MINIMUM_WETH_LIQUIDITY = 1_000_000_000;
    uint256 private swap_count = 0; // State variable that keeps track of the number of swaps that have occurred in the pool. This is used to implement a reward mechanism, where every 10 swaps, the caller receives an extra token as an incentive to continue trading on T-Swap. By maintaining a swap count, the TSwapPool contract can provide additional incentives for users to engage in trading activities, promoting liquidity and activity within the pool.
    uint256 private constant SWAP_COUNT_MAX = 10; // Constant that defines the maximum number of swaps before the reward mechanism is triggered. When the swap count reaches this value, the caller receives an extra token as an incentive to continue trading on T-Swap. By setting a maximum swap count, the TSwapPool contract can encourage users to engage in trading activities and maintain liquidity within the pool, while also providing a clear threshold for when rewards will be distributed.

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event LiquidityAdded(
        address indexed liquidityProvider, // The address of the user who provided liquidity to the pool. This is indexed to allow for efficient filtering and searching of events related to specific liquidity providers. Indexing this parameter enables users and external systems to easily track and analyze the liquidity contributions of individual users, promoting transparency and accountability within the T-Swap ecosystem.
        uint256 wethDeposited, // The amount of WETH that was deposited into the pool by the liquidity provider. This value is included in the event to provide information about the liquidity contribution made by the user, allowing for better tracking and analysis of liquidity provision within the T-Swap ecosystem. By including this parameter in the event, users and external systems can monitor the flow of WETH into the pool and assess the overall liquidity available for trading.
        uint256 poolTokensDeposited // The amount of pool tokens that was deposited into the pool by the liquidity provider. This value is included in the event to provide information about the liquidity contribution made by the user, allowing for better tracking and analysis of liquidity provision within the T-Swap ecosystem. By including this parameter in the event, users and external systems can monitor the flow of pool tokens into the pool and assess the overall liquidity available for trading.
    );
    event LiquidityRemoved(
        address indexed liquidityProvider,
        uint256 wethWithdrawn,
        uint256 poolTokensWithdrawn
    );

    // @audit-info - 3 events should be indexed if there are more than 3 parameters
    event Swap(
        address indexed swapper, // The address of the user who initiated the swap. This is indexed to allow for efficient filtering and searching of events related to specific swappers. Indexing this parameter enables users and external systems to easily track and analyze the trading activities of individual users, promoting transparency and accountability within the T-Swap ecosystem.
        IERC20 tokenIn,
        uint256 amountTokenIn,
        IERC20 tokenOut,
        uint256 amountTokenOut
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier revertIfDeadlinePassed(uint64 deadline) {
        if (deadline < uint64(block.timestamp)) { // Check if the provided deadline has passed by comparing it to the current block timestamp. If the deadline is less than the current timestamp, it means that the transaction is being attempted after the specified deadline, and the modifier will revert the transaction to prevent it from being executed.
            revert TSwapPool__DeadlineHasPassed(deadline); // revert is followed by the custom error TSwapPool__DeadlineHasPassed, which includes the provided deadline as an argument. This allows users and external systems to understand why the transaction was reverted and take appropriate action, such as adjusting the deadline or re-submitting the transaction within the allowed timeframe.
        }
        _;
    }

    modifier revertIfZero(uint256 amount) {
        if (amount == 0) {
            revert TSwapPool__MustBeMoreThanZero();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address poolToken,
        address wethToken,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) ERC20(liquidityTokenName, liquidityTokenSymbol) {
        i_wethToken = IERC20(wethToken);
        i_poolToken = IERC20(poolToken);
    } // Constructor that initializes the TSwapPool contract with the specified pool token, WETH token, liquidity token name, and liquidity token symbol. The constructor also calls the ERC20 constructor to set the name and symbol of the liquidity token. By initializing these parameters, the TSwapPool contract is set up to manage liquidity and facilitate swaps between the specified pool token and WETH, while also providing a unique identifier for the liquidity tokens that represent shares in the pool.

    /*//////////////////////////////////////////////////////////////
                        ADD AND REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to the pool
    /// @dev The invariant of this function is that the ratio of WETH, PoolTokens, and LiquidityTokens is the same
    /// before and after the transaction
    /// @param wethToDeposit Amount of WETH the user is going to deposit
    /// @param minimumLiquidityTokensToMint We derive the amount of liquidity tokens to mint from the amount of WETH the
    /// user is going to deposit, but set a minimum so they know approx what they will accept
    /// @param maximumPoolTokensToDeposit The maximum amount of pool tokens the user is willing to deposit, again it's
    /// derived from the amount of WETH the user is going to deposit
    /// @param deadline The deadline for the transaction to be completed by
    function deposit(
        uint256 wethToDeposit,
        uint256 minimumLiquidityTokensToMint, // minting here ensures that the user receives at least this amount of liquidity tokens for their deposit, providing a safeguard against unfavorable slippage. The minting is done by the TSwapPool contract itself, which manages the liquidity and facilitates swaps between the specified pool token and WETH. By setting a minimum amount of liquidity tokens to mint, users can have confidence that they will receive a fair share of the pool's liquidity in exchange for their deposit, even if market conditions change during the transaction.
        uint256 maximumPoolTokensToDeposit,
        uint64 deadline // @audit-high! deadline not being used. If someone sets a deadline, let's say next block they couold still deposit
        // IMPACT: HIGH! A userwho expects a deposit to fail, will go through. Severe disruption of functionality.
        // Likelihood: HIGH
    )
        external
        revertIfZero(wethToDeposit)
        returns (uint256 liquidityTokensToMint)
    {
        if (wethToDeposit < MINIMUM_WETH_LIQUIDITY) {
            // @audit-info MINIMUM_WETH_LIQUIDITY is a constant and therefore not required to be emitted
            revert TSwapPool__WethDepositAmountTooLow(
                MINIMUM_WETH_LIQUIDITY,
                wethToDeposit
            );
        }
        if (totalLiquidityTokenSupply() > 0) {
            uint256 wethReserves = i_wethToken.balanceOf(address(this));
            uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));
            // Our invariant says weth, poolTokens, and liquidity tokens must always have the same ratio after the
            // initial deposit
            // poolTokens / constant(k) = weth
            // weth / constant(k) = liquidityTokens
            // aka...
            // weth / poolTokens = constant(k)
            // To make sure this holds, we can make sure the new balance will match the old balance
            // (wethReserves + wethToDeposit) / (poolTokenReserves + poolTokensToDeposit) = constant(k)
            // (wethReserves + wethToDeposit) / (poolTokenReserves + poolTokensToDeposit) =
            // (wethReserves / poolTokenReserves)
            //
            // So we can do some elementary math now to figure out poolTokensToDeposit...
            // (wethReserves + wethToDeposit) = (poolTokenReserves + poolTokensToDeposit) * (wethReserves / poolTokenReserves)
            // wethReserves + wethToDeposit  = poolTokenReserves * (wethReserves / poolTokenReserves) + poolTokensToDeposit * (wethReserves / poolTokenReserves)
            // wethReserves + wethToDeposit = wethReserves + poolTokensToDeposit * (wethReserves / poolTokenReserves)
            // wethToDeposit / (wethReserves / poolTokenReserves) = poolTokensToDeposit
            // (wethToDeposit * poolTokenReserves) / wethReserves = poolTokensToDeposit
            uint256 poolTokensToDeposit = getPoolTokensToDepositBasedOnWeth(
                wethToDeposit
            ); // Calculate the amount of pool tokens to deposit based on the amount of WETH the user is depositing. This is done using the getPoolTokensToDepositBasedOnWeth function, which ensures that the ratio of WETH to pool tokens remains consistent with the pool's invariant. By calculating the required amount of pool tokens to deposit, the TSwapPool contract can maintain the proper balance of assets within the pool and ensure fair pricing for swaps and liquidity provision.
            if (maximumPoolTokensToDeposit < poolTokensToDeposit) {
                revert TSwapPool__MaxPoolTokenDepositTooHigh(
                    maximumPoolTokensToDeposit,
                    poolTokensToDeposit
                );
            } // Check if the calculated amount of pool tokens to deposit exceeds the maximum amount specified by the user. If it does, revert the transaction with a custom error TSwapPool__MaxPoolTokenDepositTooHigh, which includes both the maximum amount and the calculated amount as arguments. This ensures that users are aware of the required amount of pool tokens to deposit and prevents them from accidentally depositing more than they intended, maintaining fairness and transparency in the liquidity provision process.

            // We do the same thing for liquidity tokens. Similar math.
            liquidityTokensToMint =
                (wethToDeposit * totalLiquidityTokenSupply()) /
                wethReserves; // Calculate the amount of liquidity tokens to mint based on the amount of WETH the user is depositing. This is done by maintaining the ratio of WETH to liquidity tokens consistent with the pool's invariant. By calculating the required amount of liquidity tokens to mint, the TSwapPool contract can ensure that users receive a fair share of the pool's liquidity in exchange for their deposit, while also maintaining the proper balance of assets within the pool for swaps and liquidity provision.
            if (liquidityTokensToMint < minimumLiquidityTokensToMint) {
                revert TSwapPool__MinLiquidityTokensToMintTooLow(
                    minimumLiquidityTokensToMint,
                    liquidityTokensToMint
                );
            }
            _addLiquidityMintAndTransfer(
                wethToDeposit,
                poolTokensToDeposit,
                liquidityTokensToMint
            ); // 
        } else {
            // This will be the "initial" funding of the protocol. We are starting from blank here!
            // We just have them send the tokens in, and we mint liquidity tokens based on the weth
            _addLiquidityMintAndTransfer(
                wethToDeposit,
                maximumPoolTokensToDeposit,
                wethToDeposit
            );

            // @audit-info - it would be better if this was before the `addLiquidityMintAndTransfer` call to follow CEI
            liquidityTokensToMint = wethToDeposit;
        }
    }

    /// @dev This is a sensitive function, and should only be called by addLiquidity
    /// @param wethToDeposit The amount of WETH the user is going to deposit
    /// @param poolTokensToDeposit The amount of pool tokens the user is going to deposit
    /// @param liquidityTokensToMint The amount of liquidity tokens the user is going to mint
    function _addLiquidityMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
        _mint(msg.sender, liquidityTokensToMint); // Mint the calculated amount of liquidity tokens to the user's address. This represents the user's share of the liquidity pool and allows them to participate in swaps and earn fees based on their contribution. By minting liquidity tokens, the TSwapPool contract ensures that users receive a fair representation of their stake in the pool, while also maintaining the proper balance of assets for swaps and liquidity provision.
        emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit); // @audit-low - this is backwards! It should be `(msg.sender, wethToDeposit, poolTokensToDeposit)`

        // Interactions
        i_wethToken.safeTransferFrom(msg.sender, address(this), wethToDeposit); // Transfer the specified amount of WETH from the user's address to the TSwapPool contract. This is done using the safeTransferFrom function from the SafeERC20 library, which ensures that the transfer is executed correctly and prevents potential issues such as failed transactions or unexpected behavior. By transferring WETH to the pool, the TSwapPool contract can maintain the proper balance of assets for swaps and liquidity provision, while also ensuring that users' contributions are securely managed.
        i_poolToken.safeTransferFrom(
            msg.sender,
            address(this),
            poolTokensToDeposit
        ); // 
    }

    /// @notice Removes liquidity from the pool
    /// @param liquidityTokensToBurn The number of liquidity tokens the user wants to burn
    /// @param minWethToWithdraw The minimum amount of WETH the user wants to withdraw
    /// @param minPoolTokensToWithdraw The minimum amount of pool tokens the user wants to withdraw
    /// @param deadline The deadline for the transaction to be completed by
    function withdraw(
        uint256 liquidityTokensToBurn,
        uint256 minWethToWithdraw,
        uint256 minPoolTokensToWithdraw,
        uint64 deadline
    ) // these params are set by the user, and are used to ensure that the user gets at least what they expect, or the transaction reverts. This is important because the user may have set a minimum amount of WETH and pool tokens they expect to receive when withdrawing liquidity, and if the actual amounts are lower than these minimums, the transaction should not be executed. By enforcing these minimums, the TSwapPool contract helps protect users from unexpected outcomes or losses due to changes in market conditions or other factors that may have occurred since the transaction was initiated.
        external
        revertIfDeadlinePassed(deadline)
        revertIfZero(liquidityTokensToBurn)
        revertIfZero(minWethToWithdraw)
        revertIfZero(minPoolTokensToWithdraw)
    {
        // We do the same math as above
        uint256 wethToWithdraw = (liquidityTokensToBurn *
            i_wethToken.balanceOf(address(this))) / totalLiquidityTokenSupply(); // Calculate the amount of WETH to withdraw based on the number of liquidity tokens the user wants to burn. This is done by maintaining the ratio of WETH to liquidity tokens consistent with the pool's invariant. By calculating the required amount of WETH to withdraw, the TSwapPool contract can ensure that users receive a fair share of the pool's assets in exchange for burning their liquidity tokens, while also maintaining the proper balance of assets within the pool for swaps and liquidity provision. Burning their liquidity tokens reduces the user's share of the pool, and the corresponding amount of WETH and pool tokens are returned to them based on their contribution to the pool's liquidity.
        uint256 poolTokensToWithdraw = (liquidityTokensToBurn *
            i_poolToken.balanceOf(address(this))) / totalLiquidityTokenSupply(); // Calculate the amount of pool tokens to withdraw based on the number of liquidity tokens the user wants to burn. This is done by maintaining the ratio of pool tokens to liquidity tokens consistent with the pool's invariant. By calculating the required amount of pool tokens to withdraw, the TSwapPool contract can ensure that users receive a fair share of the pool's assets in exchange for burning their liquidity tokens, while also maintaining the proper balance of assets within the pool for swaps and liquidity provision. Burning their liquidity tokens reduces the user's share of the pool, and the corresponding amount of WETH and pool tokens are returned to them based on their contribution to the pool's liquidity.

        if (wethToWithdraw < minWethToWithdraw) {
            revert TSwapPool__OutputTooLow(wethToWithdraw, minWethToWithdraw);
        }
        if (poolTokensToWithdraw < minPoolTokensToWithdraw) {
            revert TSwapPool__OutputTooLow(
                poolTokensToWithdraw,
                minPoolTokensToWithdraw
            );
        }

        _burn(msg.sender, liquidityTokensToBurn); // Burn the specified amount of liquidity tokens from the user's address. This reduces the user's share of the liquidity pool and allows them to withdraw their corresponding share of WETH and pool tokens. By burning liquidity tokens, the TSwapPool contract ensures that users' contributions are accurately reflected in their share of the pool's assets, while also maintaining the proper balance of assets for swaps and liquidity provision.
        emit LiquidityRemoved(msg.sender, wethToWithdraw, poolTokensToWithdraw);

        i_wethToken.safeTransfer(msg.sender, wethToWithdraw);
        i_poolToken.safeTransfer(msg.sender, poolTokensToWithdraw);
    }

    /*//////////////////////////////////////////////////////////////
                              GET PRICING
    //////////////////////////////////////////////////////////////*/

    function getOutputAmountBasedOnInput(
        uint256 inputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(inputAmount)
        revertIfZero(outputReserves)
        returns (uint256 outputAmount)
    {
        // x * y = k
        // numberOfWeth * numberOfPoolTokens = constant k
        // k must not change during a transaction (invariant)
        // with this math, we want to figure out how many PoolTokens to deposit
        // since weth * poolTokens = k, we can rearrange to get:
        // (currentWeth + wethToDeposit) * (currentPoolTokens + poolTokensToDeposit) = k
        // **************************
        // ****** MATH TIME!!! ******
        // **************************
        // FOIL it (or ChatGPT): https://en.wikipedia.org/wiki/FOIL_method
        // (totalWethOfPool * totalPoolTokensOfPool) + (totalWethOfPool * poolTokensToDeposit) + (wethToDeposit *
        // totalPoolTokensOfPool) + (wethToDeposit * poolTokensToDeposit) = k
        // (totalWethOfPool * totalPoolTokensOfPool) + (wethToDeposit * totalPoolTokensOfPool) = k - (totalWethOfPool *
        // poolTokensToDeposit) - (wethToDeposit * poolTokensToDeposit)
        // @audit-info magic numbers
        uint256 inputAmountMinusFee = inputAmount * 997; 
        uint256 numerator = inputAmountMinusFee * outputReserves;
        uint256 denominator = (inputReserves * 1000) + inputAmountMinusFee;
        return numerator / denominator;
    } // Returns the amount of output tokens that can be received for a given amount of input tokens, considering the pool's reserves and fees.

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
            ((outputReserves - outputAmount) * 997); // @audit-high
    } // Returns the amount of input tokens required to receive a specific amount of output tokens, considering the pool's reserves and fees.

    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 minOutputAmount,
        uint64 deadline
    )
        public
        revertIfZero(inputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 output)  // @audit-low, IMPACT:  LOW - protocol is giving the wrong return
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        uint256 outputAmount = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );

        if (outputAmount < minOutputAmount) {
            revert TSwapPool__OutputTooLow(outputAmount, minOutputAmount);
        }

        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    /*
     * @notice figures out how much you need to input based on how much
     * output you want to receive.
     *
     * Example: You say "I want 10 output WETH, and my input is DAI"
     * The function will figure out how much DAI you need to input to get 10 WETH
     * And then execute the swap
     * @param inputToken ERC20 token to pull from caller
     * @param outputToken ERC20 token to send to caller
     * @param outputAmount The exact amount of tokens to send to caller
     */
    function swapExactOutput( // cei pattern✅: Checks, Effects, Interactions. This function first checks if the output amount is greater than zero and if the deadline has not passed. Then it calculates the input amount of tokens required to receive the desired output amount. Finally, it performs the swap by calling the _swap function, which handles the token transfers and emits the Swap event. By following the CEI pattern, the TSwapPool contract minimizes the risk of reentrancy attacks and ensures that state changes are made before external calls are executed.
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount,
        uint64 deadline
    )
        public
        revertIfZero(outputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 inputAmount)
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        inputAmount = getInputAmountBasedOnOutput(
            outputAmount,
            inputReserves,
            outputReserves
        );

        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    /**
     * @notice wrapper function to facilitate users selling pool tokens in exchange of WETH
     * @param poolTokenAmount amount of pool tokens to sell
     * @return wethAmount amount of WETH received by caller
     */
    function sellPoolTokens( // CEI pattern✅: Checks, Effects, Interactions. This function first checks if the poolTokenAmount is greater than zero and if the deadline has not passed. Then it calculates the input amount of pool tokens required to receive the desired output amount of WETH. Finally, it performs the swap by calling the _swap function, which handles the token transfers and emits the Swap event. By following the CEI pattern, the TSwapPool contract minimizes the risk of reentrancy attacks and ensures that state changes are made before external calls are executed.
        uint256 poolTokenAmount
    ) external returns (uint256 wethAmount) {
        return
            swapExactOutput(
                i_poolToken,
                i_wethToken,
                poolTokenAmount,
                uint64(block.timestamp)
            );
    }

    /**
     * @notice Swaps a given amount of input for a given amount of output tokens.
     * @dev Every 10 swaps, we give the caller an extra token as an extra incentive to keep trading on T-Swap.
     * @param inputToken ERC20 token to pull from caller
     * @param inputAmount Amount of tokens to pull from caller
     * @param outputToken ERC20 token to send to caller
     * @param outputAmount Amount of tokens to send to caller
     */
    function _swap( // CEI pattern✅: Checks, Effects, Interactions. This function first checks if the input and output tokens are valid and not the same, then updates the swap count and emits a Swap event, and finally performs the token transfers. By following the CEI pattern, the TSwapPool contract minimizes the risk of reentrancy attacks and ensures that state changes are made before external calls are executed.
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        if (
            _isUnknown(inputToken) ||
            _isUnknown(outputToken) ||
            inputToken == outputToken
        ) {
            revert TSwapPool__InvalidToken();
        }

        // @audit  - breaks protocol invariant !!!!
        swap_count++;
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
        } // here, we check if the swap_count has reached the SWAP_COUNT_MAX threshold. If it has, we reset the swap_count to 0 and transfer an extra token (1e18, which is 1 token with 18 decimals) to the caller as an incentive for trading on T-Swap. This reward mechanism encourages users to engage in trading activities within the pool, promoting liquidity and activity.
        emit Swap(
            msg.sender,
            inputToken,
            inputAmount,
            outputToken,
            outputAmount
        );

        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);
        outputToken.safeTransfer(msg.sender, outputAmount);
    }

    function _isUnknown(IERC20 token) private view returns (bool) {
        if (token != i_wethToken && token != i_poolToken) {
            return true;
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getPoolTokensToDepositBasedOnWeth( 
        uint256 wethToDeposit
    ) public view returns (uint256) {
        uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));
        uint256 wethReserves = i_wethToken.balanceOf(address(this));
        return (wethToDeposit * poolTokenReserves) / wethReserves;
    } // Calculates the amount of pool tokens to deposit based on the amount of WETH the user is depositing. This is done by maintaining the ratio of WETH to pool tokens consistent with the pool's invariant. By calculating the required amount of pool tokens to deposit, the TSwapPool contract can ensure that users maintain the proper balance of assets within the pool and facilitate fair pricing for swaps and liquidity provision.

    /// @notice a more verbose way of getting the total supply of liquidity tokens
    function totalLiquidityTokenSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getPoolToken() external view returns (address) {
        return address(i_poolToken);
    }

    function getWeth() external view returns (address) {
        return address(i_wethToken);
    }

    function getMinimumWethDepositAmount() external pure returns (uint256) {
        return MINIMUM_WETH_LIQUIDITY;
    }

    function getPriceOfOneWethInPoolTokens() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_wethToken.balanceOf(address(this)),
                i_poolToken.balanceOf(address(this))
            );
    }

    function getPriceOfOnePoolTokenInWeth() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_poolToken.balanceOf(address(this)),
                i_wethToken.balanceOf(address(this))
            );
    }
}
