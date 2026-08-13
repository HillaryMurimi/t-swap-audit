// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18);
        assertEq(weth.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;

        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        assert(weth.balanceOf(user) >= expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }

    function test_getInputAmountBasedOnOutputOverchargesUser() public view {
        uint256 outputAmount = 1e18;
        uint256 inputReserves = 100e18;
        uint256 outputReserves = 100e18;

        uint256 actualInput = pool.getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);

        // What the input should be if the fee were correctly scaled by 1000, not 10,000
        uint256 correctInput = ((inputReserves * outputAmount) * 1000) / ((outputReserves - outputAmount) * 997);

        console2.log("Actual (buggy) input required: ", actualInput);
        console2.log("Correct input required: ", correctInput);

        assertGt(actualInput, correctInput * 9); // confirms roughly 10x overcharge
    }

    // @notice Demonstrates that swapExactOutput has no way to cap the input amount a user is willing to pay. A user "expecting" to pay a certain amount for a fixed output can be silently charged far more if reserves shift (e.g. due to another swap) before their transaction executes, since there is no maximumInputAmount parameter to protect them.
    function test_swapExactOutput_noSlippageProtection() public {
        // set up the pool with initial liquidity
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        // User wants excatly 1 WETH out, and calculate (off-chain, based on CURRENT reserves) how much poolToken that should cost them
        uint256 outputAmount = 1e18;
        uint256 expectedInputAtCurrentReserves = pool.getInputAmountBasedOnOutput(
            outputAmount,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
        );

        //Give the user enough poolToken to cover a MUCH worse than expected, simulating that they've approved a large amount without any real cap
        poolToken.mint(user, 1_000e18);

        // --- Simulate the reserve-shifting attack ---
        // Before the swapExactOutput transaction executes, anm attacker (or just organic activity) performs a large swap that moves the pool's ratio significantly
        address attacker = makeAddr("attacker");
        poolToken.mint(attacker, 500e18);
        vm.startPrank(attacker);
        poolToken.approve(address(pool), 500e18);
        pool.swapExactInput(poolToken, 500e18, weth, 0, uint64(block.timestamp));
        vm.stopPrank();

        // Now reserves have shifted dramatically. Recompute what the imput SHOULD cost now.
        uint256 actualInputAfterShift = pool.getInputAmountBasedOnOutput(
            outputAmount,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
        );

        // Confirm the price genuinely got worse for the user due to the reserve shift
        assertGt(actualInputAfterShift, expectedInputAtCurrentReserves);

        // The user's swapExactOutput call still succeeds, silently charging them much higher amount, since there is NO maximumInputAmount parameter to protect them.
        vm.startPrank(user);
        poolToken.approve(address(pool), 1_000e18);
        uint256 userPoolTokenBalanceBefore = poolToken.balanceOf(user);

        uint256 inputAmountCharged = pool.swapExactOutput(poolToken, weth, outputAmount, uint64(block.timestamp));
        vm.stopPrank();

        uint256 userPoolTokenBalanceAfter = poolToken.balanceOf(user);
        uint256 actualPoolTokenSpent = userPoolTokenBalanceBefore - userPoolTokenBalanceAfter;

        console2.log("Input the user originally expected to pay: ", expectedInputAtCurrentReserves);
        console2.log("Input the user was actually charged: ", inputAmountCharged);
        console2.log("Proof-of-concept poolToken actually spent: ", actualPoolTokenSpent);

        // The transaction succeeded despite charging significantly more than the user's original expectation - proving there is no on-chain mechanism to prevent this.
        assertGt(inputAmountCharged, expectedInputAtCurrentReserves);
        assertEq(inputAmountCharged, actualInputAfterShift);
    }

    function test_swapExactOutput_hasNoMaximumInputParameter() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        // swapExactInput requires the caller to specify minOutputAmount (spillage protection). However, swapExactOutput has no equivalent - this test documents that gap by showing the function only takes 4 parameters, none of which cap the input side
        vm.startPrank(user);
        poolToken.approve(address(pool), 100e18);

        // This call succeeds with WHATEVER input price the pool currently demands - there is no way to pass a ceiling the caller is willing to accept
        uint256 inputAmount = pool.swapExactOutput(poolToken, weth, 1e18,  uint64(block.timestamp));

        // The absence of a revert here, regardless of how unfavourable `inputAmount` might be, is itself the vulnerability being demonstrated
        assertGt(inputAmount, 0);
        vm.stopPrank();
    }
}
