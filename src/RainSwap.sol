// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "./Constants.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import {console} from "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract RainSwap is IUnlockCallback, Ownable {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using SafeCast for uint256;
    using CurrencyLibrary for address;
    using SafeERC20 for IERC20;

    struct V4Hop {
        PoolKey poolKey;
        bool zeroForOne;
    }

    struct SwapV4ToV3 {
        uint128 amountIn;
        uint128 minV3Out;
    }

    IPoolManager public immutable poolManager;
    ISwapRouter public immutable v3Router;
    address public immutable WETH;

    address constant FINAL_TOKEN = 0x25118290e6A5f4139381D072181157035864099d;
    uint24 constant V3_FEE = 100;

    mapping(address => V4Hop[]) public v4Routes;

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(
        address _poolManager,
        address _v3Router,
        address _weth
    ) Ownable(msg.sender) {
        poolManager = IPoolManager(_poolManager);
        v3Router = ISwapRouter(_v3Router);
        WETH = _weth;
    }

    receive() external payable {}

    /** @notice Set a V4 swap route for a token */
    function setV4Route(
        address tokenIn,
        V4Hop[] calldata route
    ) external onlyOwner {
        delete v4Routes[tokenIn];
        for (uint256 i = 0; i < route.length; i++) {
            v4Routes[tokenIn].push(route[i]);
        }
    }

    /** @notice Initiate a swap from a token to final token via V4 and V3 */
    function swapTokenToV3(
        address tokenIn,
        SwapV4ToV3 calldata params
    ) external payable {
        // Pull tokens from sender
        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Unlock via pool manager (triggers unlockCallback)
        poolManager.unlock(abi.encode(tokenIn, params));

        // Refund any leftover tokens
        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        if (bal > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, bal);
        }
    }

    /** @notice Callback triggered by pool manager during unlock */
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        (address tokenIn, SwapV4ToV3 memory params) = abi.decode(
            data,
            (address, SwapV4ToV3)
        );

        V4Hop[] memory route = v4Routes[tokenIn];
        require(route.length > 0, "no route");

        Currency current = Currency.wrap(tokenIn);
        uint256 currentAmount = params.amountIn;

        console.log("Amount in", currentAmount);
        console.log("tokenIn::", tokenIn);

        // --- Execute V4 hops ---
        for (uint256 i = 0; i < route.length; i++) {
            V4Hop memory hop = route[i];

            BalanceDelta delta = poolManager.swap({
                key: hop.poolKey,
                params: IPoolManager.SwapParams({
                    zeroForOne: hop.zeroForOne,
                    amountSpecified: -int256(currentAmount),
                    sqrtPriceLimitX96: hop.zeroForOne
                        ? MIN_SQRT_PRICE + 1
                        : MAX_SQRT_PRICE - 1
                }),
                hookData: ""
            });

            // Settle input immediately
            poolManager.sync(current);
            if (CurrencyLibrary.isAddressZero(current)) {
                poolManager.settle{value: currentAmount}();
            } else {
                IERC20(Currency.unwrap(current)).safeTransfer(
                    address(poolManager),
                    currentAmount
                );
                poolManager.settle();
            }

            // Prepare next hop
            Currency outCurrency = hop.zeroForOne
                ? hop.poolKey.currency1
                : hop.poolKey.currency0;
            currentAmount = hop.zeroForOne
                ? delta.amount1().toUint256()
                : delta.amount0().toUint256();
            current = outCurrency;

            console.log("Amount Out:::", currentAmount);

            poolManager.take({
                currency: current,
                to: address(this),
                amount: currentAmount
            });
        }

        // // --- Final hop: must output ETH ---
        // require(
        //     CurrencyLibrary.isAddressZero(current),
        //     "final hop must output ETH"
        // );

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: currentAmount}();
        IERC20(WETH).approve(address(v3Router), currentAmount);

        // Swap WETH -> FINAL_TOKEN on V3
        v3Router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: FINAL_TOKEN,
                fee: V3_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: currentAmount,
                amountOutMinimum: params.minV3Out,
                sqrtPriceLimitX96: 0
            })
        );

        return "";
    }

    function swapTokenAgain(
        address tokenIn,
        SwapV4ToV3 calldata params
    ) external payable {
        // Pull tokens from sender
        IERC20(tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        // Unlock via pool manager (triggers unlockCallback)
        poolManager.unlock(abi.encode(tokenIn, params));

        // Refund any leftover tokens
        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        if (bal > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, bal);
        }
    }
}
