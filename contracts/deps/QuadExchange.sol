// SPDX-License-Identifier: MIT
pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../../deps/@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../../deps/@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "../../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "../../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { IWETH } from "../../interfaces/erc20/IWETH.sol";

import { UniSushiV2Library } from "../../external/UniSushiV2Library.sol";
import { IUniswapV2Factory } from "../../interfaces/uniswap/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "../../interfaces/uniswap/IUniswapV2Router02.sol";

contract QuadExchange is PausableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  /* ========== STATE VARIABLES ========== */

  address[] public quadTokens;
  uint256[] public quadWeights;
  uint256[] public quadUnits;
  address[] public quadInputs;

  address public constant WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant ROUTER = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
  address public constant FACTORY = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;

  /* ============ Constructor ============ */

  function initialize(
    address[5] memory _tokensConfig,
    uint256[5] memory _weightsConfig,
    uint256[5] memory _unitsConfig,
    address[3] memory _inputsConfig
  ) public initializer whenNotPaused {
    __Pausable_init();
    quadTokens = _tokensConfig;
    quadWeights = _weightsConfig;
    quadUnits = _unitsConfig;
    quadInputs = _inputsConfig;

    // uniRouter = IUniswapV2Router02(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
    // sushiRouter = IUniswapV2Router02(
    //   0x60aE616a2155Ee3d9A68541Ba4544862310933d4
    // );

    IERC20Upgradeable(quadTokens[0]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadTokens[1]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadTokens[2]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadTokens[3]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadTokens[4]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadInputs[0]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadInputs[1]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(quadInputs[2]).safeApprove(ROUTER, type(uint256).max);

    IERC20Upgradeable(WETH).safeApprove(FACTORY, type(uint256).max);
  }

  /* ========== FUNCTIONS ========== */

  function issueQuadForExactToken() external {}

  /* ========== EXTERNAL READ FUNCTIONS ========== */

  function getEstimatedQuadGivenAmount(
    address _inputToken,
    uint256 _amountInput
  ) external view returns (uint256) {
    require(_amountInput > 0, "QuadExchange: INVALID INPUTS");
    uint256 amountEth;
    if (_inputToken != WETH) {
      // get max amount of WETH for the `_amountInput` amount of input tokens
      (amountEth, ) = _getMaxTokenForExactToken(
        _amountInput,
        _inputToken,
        WETH
      );
    } else {
      amountEth = _amountInput;
    }
    address[] memory components = quadTokens;
    (uint256 setIssueAmount, ) = _getSetIssueAmountForETH(
      components,
      amountEth
    );
    return setIssueAmount;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _getMaxTokenForExactToken(
    uint256 _amountIn,
    address _tokenA,
    address _tokenB
  ) internal view returns (uint256, address) {
    // If _tokenA == _tokenB then throw
    uint256 tokenOut;

    address joePair = _getPair(FACTORY, _tokenA, _tokenB);
    if (joePair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        joePair,
        _tokenA,
        _tokenB
      );
      tokenOut = UniSushiV2Library.getAmountOut(
        _amountIn,
        reserveIn,
        reserveOut
      );
    }

    return (tokenOut, joePair);
  }

  function _getSetIssueAmountForETH(
    address[] memory _components,
    uint256 _amountEth
  )
    internal
    view
    returns (uint256 setIssueAmount, uint256[] memory amountEthIn)
  {
    uint256 sumEth;
    uint256[] memory unitAmountEthIn;
    uint256[] memory unitAmountComponents;
    address[] memory pairAddresses;
    (
      sumEth,
      unitAmountEthIn,
      unitAmountComponents,
      pairAddresses
    ) = _getAmountETHForIssuance(_components, 10**18);

    setIssueAmount = type(uint256).max;
    amountEthIn = new uint256[](_components.length);

    for (uint256 i = 0; i < _components.length; i++) {
      amountEthIn[i] = unitAmountEthIn[i].mul(_amountEth).div(sumEth);

      uint256 amountComponent;

      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        pairAddresses[i],
        WETH,
        _components[i]
      );

      amountComponent = UniSushiV2Library.getAmountOut(
        amountEthIn[i],
        reserveIn,
        reserveOut
      );

      setIssueAmount = MathUpgradeable.min(
        amountComponent.div(unitAmountComponents[i]),
        setIssueAmount
      );
    }
    return (setIssueAmount, amountEthIn);
  }

  function _getAmountETHForIssuance(
    address[] memory _components,
    uint256 _amountSetToken
  )
    internal
    view
    returns (
      uint256 sumEth,
      uint256[] memory amountEthIn,
      uint256[] memory amountComponents,
      address[] memory pairAddresses
    )
  {
    sumEth = 0;
    amountEthIn = new uint256[](_components.length);
    amountComponents = new uint256[](_components.length);
    pairAddresses = new address[](_components.length);

    for (uint256 i = 0; i < _components.length; i++) {
      // Check that the component does not have external positions
      //   require(
      //     _setToken.getExternalPositionModules(_components[i]).length == 0,
      //     "ExchangeIssuance: EXTERNAL_POSITIONS_NOT_ALLOWED"
      //   );

      // Get minimum amount of ETH to be spent to acquire the required amount of SetToken component
      uint256 unit = uint256(quadUnits[i]);
      amountComponents[i] = uint256(unit).mul(_amountSetToken);

      (amountEthIn[i], pairAddresses[i]) = _getMinTokenForExactToken(
        amountComponents[i],
        WETH,
        _components[i]
      );
      sumEth = sumEth.add(amountEthIn[i]);
    }
    return (sumEth, amountEthIn, amountComponents, pairAddresses);
  }

  function _getMinTokenForExactToken(
    uint256 _amountOut,
    address _tokenA,
    address _tokenB
  ) internal view returns (uint256, address) {
    // if _tokenA == _tokenB throw

    uint256 maxIn = type(uint256).max;
    uint256 tokenIn = maxIn;

    address joePair = _getPair(FACTORY, _tokenA, _tokenB);
    if (joePair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        joePair,
        _tokenA,
        _tokenB
      );
      // Prevent subtraction overflow by making sure pool reserves are greater than swap amount
      if (reserveOut > _amountOut) {
        tokenIn = UniSushiV2Library.getAmountIn(
          _amountOut,
          reserveIn,
          reserveOut
        );
      }
    }

    // Fails if both the values are maxIn
    return (tokenIn, joePair);
  }

  function _getPair(
    address _factory,
    address _tokenA,
    address _tokenB
  ) internal view returns (address) {
    return IUniswapV2Factory(_factory).getPair(_tokenA, _tokenB);
  }
}
