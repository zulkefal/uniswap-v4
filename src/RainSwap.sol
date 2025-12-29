// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// import {console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {MIN_SQRT_PRICE, MAX_SQRT_PRICE, RAIN_TOKEN} from "./Constants.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract RainSwap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLibrary for address;

    IPoolManager public immutable poolManager;
    ISwapRouter public immutable v3Router;
    address public immutable WETH;

    struct SwapV4ToV3 {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 minV4Out;
        address tokenOutV3;
        uint128 minV3Out;
        uint24 v3Fee;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager, address _v3Router, address _weth) {
        poolManager = IPoolManager(_poolManager);
        v3Router = ISwapRouter(_v3Router);
        WETH = _weth;
    }

    receive() external payable {}

    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        (address msgSender, SwapV4ToV3 memory params) = abi.decode(
            data,
            (address, SwapV4ToV3)
        );

        BalanceDelta delta = poolManager.swap({
            key: params.poolKey,
            params: IPoolManager.SwapParams({
                zeroForOne: params.zeroForOne,
                // amountSpecified < 0 = amount in
                // amountSpecified > 0 = amount out
                amountSpecified: -(params.amountIn.toInt256()),
                // price = Currency 1 / currency 0
                // 0 for 1 = price decreases
                // 1 for 0 = price increases
                sqrtPriceLimitX96: params.zeroForOne
                    ? MIN_SQRT_PRICE + 1
                    : MAX_SQRT_PRICE - 1
            }),
            hookData: ""
        });

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        (
            Currency currencyIn,
            Currency currencyOut,
            uint256 amountIn,
            uint256 amountOut
        ) = params.zeroForOne
                ? (
                    params.poolKey.currency0,
                    params.poolKey.currency1,
                    (-amount0).toUint256(),
                    amount1.toUint256()
                )
                : (
                    params.poolKey.currency1,
                    params.poolKey.currency0,
                    (-amount1).toUint256(),
                    amount0.toUint256()
                );

        poolManager.take({
            currency: currencyOut,
            to: msgSender,
            amount: amountOut
        });

        poolManager.sync(currencyIn);

        if (CurrencyLibrary.isAddressZero(currencyIn)) {
            poolManager.settle{value: amountIn}();
        } else {
            (currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }

        // if (currencyIn == address(0)) {
        //     // poolManager.settle{value: amountIn}();
        // } else {
        //     // IERC20(currencyIn).transfer(address(poolManager), amountIn);
        //     // poolManager.settle();
        //     IERC20(currencyIn).transfer(address(this), amountIn);
        //     IERC20(currencyIn).approve(address(v3Router), amountIn);
        // }

        IWETH(WETH).deposit{value: amountIn}();
        IERC20(WETH).approve(address(v3Router), amountIn);

        // require(amountOut >= params.minV4Out, "v4 slippage");

        // IERC20(WETH).approve(address(v3Router), amountOut);

        v3Router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: params.tokenOutV3,
                fee: params.v3Fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        return "";
    }

    function swapV4ToV3(SwapV4ToV3 calldata params) external payable {
        Currency currencyIn = params.zeroForOne
            ? params.poolKey.currency0
            : params.poolKey.currency1;

        IERC20(Currency.unwrap(currencyIn)).transferFrom(
            msg.sender,
            address(this),
            uint256(params.amountIn)
        );
        // (currencyIn).transfer(msg.sender, uint256(params.amountIn));

        poolManager.unlock(abi.encode(msg.sender, params));

        // refund dust
        uint256 bal = currencyIn.balanceOf(address(this));
        if (bal > 0) {
            currencyIn.transfer(msg.sender, bal);
        }
    }
}
