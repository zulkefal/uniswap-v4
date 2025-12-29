// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {POOL_MANAGER, USDC} from "../src/Constants.sol";
import {TestHelper} from "./TestHelper.t.sol";
import {RainSwap} from "../src/RainSwap.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract SwapTest is Test, TestHelper {
    IERC20 constant usdc = IERC20(USDC);

    TestHelper helper;
    RainSwap swap;
    PoolKey poolKey;

    address v3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IERC20 constant aToken = IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);

    address constant RAIN_TOKEN = 0x25118290e6A5f4139381D072181157035864099d;

    receive() external payable {}

    function setUp() public {
        helper = new TestHelper();

        deal(address(aToken), address(this), 1000 * 1e18);

        swap = new RainSwap(POOL_MANAGER, v3Router, weth);

        // usdc.approve(address(swap), type(uint256).max);
        aToken.approve(address(swap), type(uint256).max);

        poolKey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(aToken)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function test_swapExactInput_Token_Weth_Rain() public {
        // Swap ETH to USDC
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        helper.set("Before swap AToken", aTokenBalance);
        helper.set("Before swap ETH", address(this).balance);

        console.log("Before swap AToken", aTokenBalance);
        console.log("Before swap ETH", address(this).balance);

        // uint128 amountIn = uint128(aTokenBalance);
        uint128 amountIn = 1 * 10 ** 18;

        swap.swapV4ToV3{value: amountIn}(
            RainSwap.SwapV4ToV3({
                poolKey: poolKey,
                zeroForOne: false,
                amountIn: amountIn,
                minV4Out: 0,
                tokenOutV3: RAIN_TOKEN,
                minV3Out: 0,
                v3Fee: 100
            })
        );

        helper.set("After swap AToken", aToken.balanceOf(address(this)));
        helper.set("After swap ETH", address(this).balance);

        console.log("After swap AToken", aToken.balanceOf(address(this)));
        console.log("After swap ETH", address(this).balance);

        //     int256 d0 = helper.delta("After swap ETH", "Before swap ETH");
        //     int256 d1 = helper.delta("After swap USDC", "Before swap USDC");

        //     console.log("ETH delta: %e", d0);
        //     console.log("USDC delta: %e", d1);

        //     assertLt(d0, 0, "ETH delta");
        //     assertGt(d1, 0, "USDC delta");
        // }

        console.log(
            "Rain Tokens:",
            IERC20(RAIN_TOKEN).balanceOf(address(swap))
        );
    }
}
