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

import { TSwapPool } from "./TSwapPool.sol"; // Import the TSwapPool contract, which is used to create new liquidity pools for token swaps.
import { IERC20 } from "forge-std/interfaces/IERC20.sol"; // Import the IERC20 interface, which defines the standard functions for interacting with ERC20 tokens. This is used to retrieve token names when creating new pools. Therefore, the PoolFactory contract can create new liquidity pools for any ERC20 token by using the IERC20 interface to get the token's name and symbol. Reverse lookups are also supported, allowing users to find the token associated with a given pool and vice versa. Although the PoolFactory contract does not handle token transfers or swaps directly, it provides a way to create and manage liquidity pools for ERC20 tokens, enabling users to swap between different tokens in a decentralized manner.

contract PoolFactory {
    error PoolFactory__PoolAlreadyExists(address tokenAddress); // Custom error that is thrown when a pool for the specified token address already exists. This prevents the creation of duplicate pools for the same token.
    error PoolFactory__PoolDoesNotExist(address tokenAddress); // Custom error that is thrown when a pool for the specified token address does not exist. This is used to indicate that a requested pool cannot be found in the factory's records.

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address token => address pool) private s_pools; // Mapping that associates each token address with its corresponding pool address. This allows for quick retrieval of the pool associated with a specific token.
    mapping(address pool => address token) private s_tokens; // Mapping that associates each pool address with its corresponding token address. This allows for reverse lookup, enabling users to find the token associated with a given pool. Token address is the address of the token that is being swapped in the pool, while the pool address is the address of the TSwapPool contract that manages the liquidity and facilitates swaps for that token. The token address changes when the token is transferred to another wallet, but the pool address remains the same, allowing for consistent access to the pool regardless of token ownership changes. When the token is transfered to another wallet, reverse look ups are still possible, as the pool address remains the same and can be used to find the associated token address in this mapping.

    address private immutable i_wethToken; // Immutable variable that stores the address of the WETH token. This is used when creating new pools to facilitate swaps involving WETH.

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event PoolCreated(address tokenAddress, address poolAddress); // Event that is emitted when a new pool is created. It includes the token address for which the pool was created and the address of the newly created pool. This allows external systems to listen for and react to the creation of new pools.

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address wethToken) { // Constructor that initializes the PoolFactory contract with the address of the WETH token. This address is stored in the immutable variable i_wethToken and is used when creating new pools to facilitate swaps involving WETH.
        i_wethToken = wethToken;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function createPool(address tokenAddress) external returns (address) {  // External function that allows users to create a new liquidity pool for a specified token address. It checks if a pool already exists for the token, and if not, it creates a new TSwapPool contract, stores its address in the mappings, and emits an event to notify that a new pool has been created.
        if (s_pools[tokenAddress] != address(0)) { // Check if a pool already exists for the given token address by looking it up in the s_pools mapping. If the address is not zero, it means a pool already exists for that token.
            revert PoolFactory__PoolAlreadyExists(tokenAddress); // If a pool already exists for the specified token address, revert the transaction and throw the custom error PoolFactory__PoolAlreadyExists. This prevents the creation of duplicate pools for the same token.
        } 
        string memory liquidityTokenName = string.concat("T-Swap ", IERC20(tokenAddress).name()); // Create a new string for the liquidity token name by concatenating "T-Swap " with the name of the token retrieved using the IERC20 interface. This gives the liquidity token a unique name that indicates it is associated with the T-Swap pool for the specified token.
        string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).name()); // Create a new string for the liquidity token symbol by concatenating "ts" with the name of the token retrieved using the IERC20 interface. This gives the liquidity token a unique symbol that indicates it is associated with the T-Swap pool for the specified token.
        TSwapPool tPool = new TSwapPool(tokenAddress, i_wethToken, liquidityTokenName, liquidityTokenSymbol); // Create a new TSwapPool contract, passing in the token address, the WETH token address, and the liquidity token name and symbol. This initializes the new pool with the specified parameters, allowing users to swap between the specified token and WETH. The token address is used to identify the token being swapped, while the WETH token address is used to facilitate swaps involving WETH. The liquidity token name and symbol are used to create a unique identifier for the liquidity tokens that represent shares in the pool. The wallet that holds  all the assets in the pool is the address of the TSwapPool contract itself, which is created in this step. The TSwapPool contract will manage the liquidity and facilitate swaps between the specified token and WETH.
        s_pools[tokenAddress] = address(tPool); // Store the address of the newly created pool in the mapping, allowing for quick retrieval of the pool associated with the specified token address. This enables users to easily find the pool for a given token and interact with it for swaps and liquidity provision. The token address changes when the token is transferred to another wallet, but the pool address remains the same, allowing for consistent access to the pool regardless of token ownership changes. When the token is transfered to another wallet, reverse look ups are still possible, as the pool address remains the same and can be used to find the associated token address in the s_tokens mapping. This is achieved by storing the token address in the s_tokens mapping, which allows for reverse lookup of the token associated with a given pool address. This ensures that users can always find the correct token for a pool, even if the token has been transferred to a different wallet.
        s_tokens[address(tPool)] = tokenAddress; // Store the token address associated with the pool, allowing for reverse lookup. Reverse lookup are important in many ways, for example, if a user wants to find the token associated with a given pool, they can use the pool address to look up the token address in the s_tokens mapping. This is useful for users who want to interact with a specific pool and need to know which token is associated with it. Additionally, reverse lookup can be used for analytics and reporting purposes, allowing users to track the performance of specific tokens and their associated pools over time.
        emit PoolCreated(tokenAddress, address(tPool)); // Emit an event to notify that a new pool has been created
        return address(tPool); // Return the address of the newly created pool
    }

    /*//////////////////////////////////////////////////////////////
                   EXTERNAL AND PUBLIC VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getPool(address tokenAddress) external view returns (address) {
        return s_pools[tokenAddress];
    } // Returns the address of the pool associated with the given token address. If no pool exists for the token, it returns the zero address.

    function getToken(address pool) external view returns (address) {
        return s_tokens[pool];
    } // Returns the address of the token associated with the given pool address. If no token exists for the pool, it returns the zero address.

    function getWethToken() external view returns (address) {
        return i_wethToken;
    }// Returns the address of the WETH token used in the factory.
}
