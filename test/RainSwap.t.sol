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
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract SwapTest is Test, TestHelper {
    IERC20 constant usdc = IERC20(USDC);

    TestHelper helper;
    RainSwap swap;
    PoolKey poolKey;

    PoolKey poolKeyUSDT;

    PoolKey poolKey_Pear_1;

    PoolKey poolKey_Pear_2;

    address v3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IERC20 constant aToken = IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);

    address constant RAIN_TOKEN = 0x25118290e6A5f4139381D072181157035864099d;

    IERC20 constant bToken = IERC20(0x45D9831d8751B2325f3DBf48db748723726e1C8c);

    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    address user = makeAddr("user");

    receive() external payable {}

    function setUp() public {
        helper = new TestHelper();

        deal(address(aToken), user, 1000 * 1e18);
        deal(address(bToken), user, 1000 * 1e18);

        vm.startPrank(user);

        swap = new RainSwap(POOL_MANAGER, v3Router, weth);

        // usdc.approve(address(swap), type(uint256).max);
        aToken.approve(address(swap), type(uint256).max);
        bToken.approve(address(swap), type(uint256).max);
        USDT.approve(address(swap), type(uint256).max);

        poolKey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(aToken)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        poolKeyUSDT = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(USDT)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        poolKey_Pear_1 = PoolKey({
            currency0: Currency.wrap(address(bToken)),
            currency1: Currency.wrap(address(USDT)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // 100, 300, 500,
        poolKey_Pear_2 = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(USDT)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // IPoolManager(address(POOL_MANAGER)).initialize(poolKeyUSDT, 4295128740);
    }

    function test_swapExactInput_Token_Weth_Rain() public {
        vm.startPrank(user);
        RainSwap.V4Hop[] memory v4 = new RainSwap.V4Hop[](1);
        v4[0] = RainSwap.V4Hop({poolKey: poolKey, zeroForOne: false});
        swap.setV4Route(address(aToken), v4);

        // Swap ETH to USDC

        console.log("Before swap AToken", aToken.balanceOf(address(user)));

        console.log(
            "Before Swap Rain Token:",
            IERC20(RAIN_TOKEN).balanceOf(address(swap))
        );

        // uint128 amountIn = uint128(aTokenBalance);
        uint128 amountIn = 1000 * 10 ** 18;

        swap.swapTokenToV3(
            address(aToken),
            RainSwap.SwapV4ToV3({amountIn: amountIn, minV3Out: 0})
        );

        console.log("After swap AToken", aToken.balanceOf(address(user)));

        console.log(
            "Rain Tokens:",
            IERC20(RAIN_TOKEN).balanceOf(address(swap))
        );
    }

    function test_USDT_TO_ANY_TOKEN() public {
        vm.startPrank(user);
        RainSwap.V4Hop[] memory v4 = new RainSwap.V4Hop[](1);
        v4[0] = RainSwap.V4Hop({poolKey: poolKeyUSDT, zeroForOne: false});

        swap.setV4Route(address(USDT), v4);

        // uint128 amountIn = uint128(aTokenBalance);
        uint128 amountIn = 1000 * 10 ** 6;

        swap.swapTokenToV3(
            address(USDT),
            RainSwap.SwapV4ToV3({amountIn: amountIn, minV3Out: 0})
        );
    }

    function test_swapMultiHop() public {
        vm.startPrank(user);
        RainSwap.V4Hop[] memory v4 = new RainSwap.V4Hop[](2);
        v4[0] = RainSwap.V4Hop({poolKey: poolKey_Pear_1, zeroForOne: true});
        v4[1] = RainSwap.V4Hop({poolKey: poolKey_Pear_2, zeroForOne: false});

        console.log("Before swap Btoken", bToken.balanceOf(user));

        swap.setV4Route(address(bToken), v4);

        // uint128 amountIn = uint128(aTokenBalance);
        uint128 amountIn = 1000 * 1e18;

        swap.swapTokenToV3(
            address(bToken),
            RainSwap.SwapV4ToV3({amountIn: amountIn, minV3Out: 0})
        );

        console.log("After swap BToken", bToken.balanceOf(user));

        console.log(
            "Rain Tokens:",
            IERC20(RAIN_TOKEN).balanceOf(address(swap))
        );
    }
}
