/*
    Copyright 2021 Index Cooperative
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    SPDX-License-Identifier: Apache License, Version 2.0
*/
pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../../deps/@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../../deps/@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import { AddressUpgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { IERC20Upgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { IUniswapV2Factory } from "../../interfaces/uniswap/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "../../interfaces/uniswap/IUniswapV2Router02.sol";

import { MathUpgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import { SafeERC20Upgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import { SafeMathUpgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "../../deps/@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IWETH } from "../../interfaces/erc20/IWETH.sol";
import { PreciseUnitMath } from "../../lib/PreciseUnitMath.sol";
import { UniSushiV2Library } from "../../external/UniSushiV2Library.sol";

/**
 * @title ExchangeIssuance
 * @author Index Coop
 *
 * Contract for issuing and redeeming any SetToken using ETH or an ERC20 as the paying/receiving currency.
 * All swaps are done using the best price found on Uniswap or Sushiswap.
 *
 */
abstract contract ExchangeIssuanceV2 is
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using AddressUpgradeable for address payable;
  using SafeMathUpgradeable for uint256;
  using PreciseUnitMath for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /* ============ Enums ============ */

  enum Exchange {
    Uniswap,
    Sushiswap,
    None
  }

  /* ============ Constants ============= */

  address[] public tokens;

  uint256 private constant MAX_UINT96 = 2**96 - 1;
  address public constant ETH_ADDRESS =
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /* ============ State Variables ============ */

  address public WETH;

  IUniswapV2Router02 public uniRouter;
  IUniswapV2Router02 public sushiRouter;

  address public uniFactory;
  address public sushiFactory;

  /* ============ Events ============ */

  //   event ExchangeIssue(
  //     address indexed _recipient, // The recipient address of the issued SetTokens
  //     ISetToken indexed _setToken, // The issued SetToken
  //     IERC20 indexed _inputToken, // The address of the input asset(ERC20/ETH) used to issue the SetTokens
  //     uint256 _amountInputToken, // The amount of input tokens used for issuance
  //     uint256 _amountSetIssued // The amount of SetTokens received by the recipient
  //   );

  //   event ExchangeRedeem(
  //     address indexed _recipient, // The recipient address which redeemed the SetTokens
  //     ISetToken indexed _setToken, // The redeemed SetToken
  //     IERC20 indexed _outputToken, // The address of output asset(ERC20/ETH) received by the recipient
  //     uint256 _amountSetRedeemed, // The amount of SetTokens redeemed for output tokens
  //     uint256 _amountOutputToken // The amount of output tokens received by the recipient
  //   );

  //   event Refund(
  //     address indexed _recipient, // The recipient address which redeemed the SetTokens
  //     uint256 _refundAmount // The amount of ETH redunded to the recipient
  //   );

  /* ============ Modifiers ============ */

  //   modifier isSetToken(ISetToken _setToken) {
  //     require(
  //       setController.isSet(address(_setToken)),
  //       "ExchangeIssuance: INVALID SET"
  //     );
  //     _;
  //   }

  /* ============ Constructor ============ */

  function __ExchangeIssuanceV2_init(address[5] memory _tokensConfig)
    public
    initializer
    whenNotPaused
  {
    __Pausable_init();
    tokens = _tokensConfig;

    uniRouter = IUniswapV2Router02(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
    sushiRouter = IUniswapV2Router02(
      0x60aE616a2155Ee3d9A68541Ba4544862310933d4
    );

    uniFactory = 0xefa94DE7a4656D787667C749f7E1223D71E9FD88;
    sushiFactory = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;

    WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    IERC20Upgradeable(WETH).safeApprove(
      0xefa94DE7a4656D787667C749f7E1223D71E9FD88,
      type(uint256).max
    );
    IERC20Upgradeable(WETH).safeApprove(
      0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10,
      type(uint256).max
    );
  }

  /* ============ Public Functions ============ */

  /**
   * Runs all the necessary approval functions required for a given ERC20 token.
   * This function can be called when a new token is added to a SetToken during a
   * rebalance.
   *
   * @param _token    Address of the token which needs approval
   */
  function approveToken(address _token) public {
    _safeApprove(_token, address(uniRouter), type(uint256).max);
    _safeApprove(_token, address(sushiRouter), type(uint256).max);
    // _safeApprove(_token, address(basicIssuanceModule), MAX_UINT96);
  }

  /* ============ External Functions ============ */

  /**
   * Runs all the necessary approval functions required for a list of ERC20 tokens.
   *
   * @param _tokens    Addresses of the tokens which need approval
   */
  function approveTokens(address[] calldata _tokens) external {
    for (uint256 i = 0; i < _tokens.length; i++) {
      approveToken(_tokens[i]);
    }
  }

  /**
   * Issues SetTokens for an exact amount of input ERC20 tokens.
   * The ERC20 token must be approved by the sender to this contract.
   *
   * @param _inputToken       Address of input token
   * @param _amountInput      Amount of the input token / ether to spend
   * @param _minSetReceive    Minimum amount of SetTokens to receive. Prevents unnecessary slippage.
   *
   * @return setTokenAmount   Amount of SetTokens issued to the caller
   */
  function issueSetForExactToken(
    address _inputToken,
    uint256 _amountInput,
    uint256 _minSetReceive
  ) external nonReentrant returns (uint256) {
    require(_amountInput > 0, "ExchangeIssuance: INVALID INPUTS");

    IERC20Upgradeable(_inputToken).safeTransferFrom(
      msg.sender,
      address(this),
      _amountInput
    );

    uint256 amountEth = address(_inputToken) == WETH
      ? _amountInput
      : _swapTokenForWETH(_inputToken, _amountInput);

    uint256 setTokenAmount = _issueSetForExactWETH(_minSetReceive, amountEth);

    // emit ExchangeIssue(
    //   msg.sender,
    //   _setToken,
    //   _inputToken,
    //   _amountInput,
    //   setTokenAmount
    // );
    return setTokenAmount;
  }

  /**
   * Issues an exact amount of SetTokens for given amount of input ERC20 tokens.
   * The excess amount of tokens is returned in an equivalent amount of ether.
   *
   * @param _inputToken            Address of the input token
   * @param _amountSetToken        Amount of SetTokens to issue
   * @param _maxAmountInputToken   Maximum amount of input tokens to be used to issue SetTokens. The unused
   *                               input tokens are returned as ether.
   *
   * @return amountEthReturn       Amount of ether returned to the caller
   */
  function issueExactSetFromToken(
    address _inputToken,
    uint256 _amountSetToken,
    uint256 _maxAmountInputToken
  ) external nonReentrant returns (uint256) {
    require(
      _amountSetToken > 0 && _maxAmountInputToken > 0,
      "ExchangeIssuance: INVALID INPUTS"
    );

    IERC20Upgradeable(_inputToken).safeTransferFrom(
      msg.sender,
      address(this),
      _maxAmountInputToken
    );

    uint256 initETHAmount = address(_inputToken) == WETH
      ? _maxAmountInputToken
      : _swapTokenForWETH(_inputToken, _maxAmountInputToken);

    uint256 amountEthSpent = _issueExactSetFromWETH(
      _amountSetToken,
      initETHAmount
    );

    uint256 amountEthReturn = initETHAmount.sub(amountEthSpent);
    if (amountEthReturn > 0) {
      IERC20Upgradeable(WETH).safeTransfer(msg.sender, amountEthReturn);
    }

    // emit Refund(msg.sender, amountEthReturn);
    // emit ExchangeIssue(
    //   msg.sender,
    //   _setToken,
    //   _inputToken,
    //   _maxAmountInputToken,
    //   _amountSetToken
    // );
    return amountEthReturn;
  }

  /**
   * Returns an estimated amount of SetToken that can be issued given an amount of input ERC20 token.
   *
   * @param _amountInput      Amount of the input token to spend
   * @param _inputToken       Address of input token.
   *
   * @return                  Estimated amount of SetTokens that will be received
   */
  function getEstimatedIssueSetAmount(address _inputToken, uint256 _amountInput)
    external
    view
    returns (uint256)
  {
    require(_amountInput > 0, "ExchangeIssuance: INVALID INPUTS");

    uint256 amountEth;
    if (address(_inputToken) != WETH) {
      // get max amount of WETH for the `_amountInput` amount of input tokens
      (amountEth, , ) = _getMaxTokenForExactToken(
        _amountInput,
        address(_inputToken),
        WETH
      );
    } else {
      amountEth = _amountInput;
    }

    address[] memory components = tokens;
    (uint256 setIssueAmount, , ) = _getSetIssueAmountForETH(
      components,
      amountEth
    );
    return setIssueAmount;
  }

  /**
   * Returns the amount of input ERC20 tokens required to issue an exact amount of SetTokens.
   *
   * @param _amountSetToken    Amount of SetTokens to issue
   *
   * @return                   Amount of tokens needed to issue specified amount of SetTokens
   */
  function getAmountInToIssueExactSet(
    address _inputToken,
    uint256 _amountSetToken
  ) external view returns (uint256) {
    require(_amountSetToken > 0, "ExchangeIssuance: INVALID INPUTS");

    address[] memory components = tokens;
    (uint256 totalEth, , , , ) = _getAmountETHForIssuance(
      components,
      _amountSetToken
    );

    if (address(_inputToken) == WETH) {
      return totalEth;
    }

    (uint256 tokenAmount, , ) = _getMinTokenForExactToken(
      totalEth,
      address(_inputToken),
      address(WETH)
    );
    return tokenAmount;
  }

  /* ============ Internal Functions ============ */

  /**
   * Sets a max approval limit for an ERC20 token, provided the current allowance
   * is less than the required allownce.
   *
   * @param _token    Token to approve
   * @param _spender  Spender address to approve
   */
  function _safeApprove(
    address _token,
    address _spender,
    uint256 _requiredAllowance
  ) internal {
    uint256 allowance = IERC20Upgradeable(_token).allowance(
      address(this),
      _spender
    );
    if (allowance < _requiredAllowance) {
      IERC20Upgradeable(_token).safeIncreaseAllowance(
        _spender,
        type(uint256).max - allowance
      );
    }
  }

  /**
   * Issues SetTokens for an exact amount of input WETH.
   *
   * @param _minSetReceive    Minimum amount of index to receive
   * @param _totalEthAmount   Total amount of WETH to be used to purchase the SetToken components
   *
   * @return setTokenAmount   Amount of SetTokens issued
   */
  function _issueSetForExactWETH(
    uint256 _minSetReceive,
    uint256 _totalEthAmount
  ) internal returns (uint256) {
    address[] memory components = tokens;
    (
      uint256 setIssueAmount,
      uint256[] memory amountEthIn,
      Exchange[] memory exchanges
    ) = _getSetIssueAmountForETH(components, _totalEthAmount);

    require(
      setIssueAmount > _minSetReceive,
      "ExchangeIssuance: INSUFFICIENT_OUTPUT_AMOUNT"
    );

    for (uint256 i = 0; i < components.length; i++) {
      _swapExactTokensForTokens(
        exchanges[i],
        WETH,
        components[i],
        amountEthIn[i]
      );
    }

    // basicIssuanceModule.issue(setIssueAmount, msg.sender);
    return setIssueAmount;
  }

  /**
   * Issues an exact amount of SetTokens using WETH.
   * Acquires SetToken components at the best price accross uniswap and sushiswap.
   * Uses the acquired components to issue the SetTokens.
   *
   * @param _amountSetToken    Amount of SetTokens to be issued
   * @param _maxEther          Max amount of ether that can be used to acquire the SetToken components
   *
   * @return totalEth          Total amount of ether used to acquire the SetToken components
   */
  function _issueExactSetFromWETH(uint256 _amountSetToken, uint256 _maxEther)
    internal
    returns (uint256)
  {
    address[] memory components = tokens;
    (
      uint256 sumEth,
      ,
      Exchange[] memory exchanges,
      uint256[] memory amountComponents,

    ) = _getAmountETHForIssuance(components, _amountSetToken);

    require(sumEth <= _maxEther, "ExchangeIssuance: INSUFFICIENT_INPUT_AMOUNT");

    uint256 totalEth = 0;
    for (uint256 i = 0; i < components.length; i++) {
      uint256 amountEth = _swapTokensForExactTokens(
        exchanges[i],
        WETH,
        components[i],
        amountComponents[i]
      );
      totalEth = totalEth.add(amountEth);
    }
    // basicIssuanceModule.issue(_amountSetToken, msg.sender);
    return totalEth;
  }

  /**
   * Redeems a given amount of SetToken.
   *
   * @param _amount       Amount of SetToken to be redeemed
   */
  //   function _redeemExactSet(uint256 _amount) internal returns (uint256) {
  //     _setToken.safeTransferFrom(msg.sender, address(this), _amount);
  //     basicIssuanceModule.redeem(_setToken, _amount, address(this));
  //   }

  /**
   * Liquidates a given list of SetToken components for WETH.
   *
   * @param _components           An array containing the address of SetToken components
   * @param _amountComponents     An array containing the amount of each SetToken component
   * @param _exchanges            An array containing the exchange on which to liquidate the SetToken component
   *
   * @return                      Total amount of WETH received after liquidating all SetToken components
   */
  function _liquidateComponentsForWETH(
    address[] memory _components,
    uint256[] memory _amountComponents,
    Exchange[] memory _exchanges
  ) internal returns (uint256) {
    uint256 sumEth = 0;
    for (uint256 i = 0; i < _components.length; i++) {
      sumEth = _exchanges[i] == Exchange.None
        ? sumEth.add(_amountComponents[i])
        : sumEth.add(
          _swapExactTokensForTokens(
            _exchanges[i],
            _components[i],
            WETH,
            _amountComponents[i]
          )
        );
    }
    return sumEth;
  }

  /**
   * Gets the total amount of ether required for purchasing each component in a SetToken,
   * to enable the issuance of a given amount of SetTokens.
   *
   * @param _components           An array containing the addresses of the SetToken components
   * @param _amountSetToken       Amount of SetToken to be issued
   *
   * @return sumEth               The total amount of Ether reuired to issue the set
   * @return amountEthIn          An array containing the amount of ether to purchase each component of the SetToken
   * @return exchanges            An array containing the exchange on which to perform the purchase
   * @return amountComponents     An array containing the amount of each SetToken component required for issuing the given
   *                              amount of SetToken
   * @return pairAddresses        An array containing the pair addresses of ETH/component exchange pool
   */
  function _getAmountETHForIssuance(
    address[] memory _components,
    uint256 _amountSetToken
  )
    internal
    view
    returns (
      uint256 sumEth,
      uint256[] memory amountEthIn,
      Exchange[] memory exchanges,
      uint256[] memory amountComponents,
      address[] memory pairAddresses
    )
  {
    sumEth = 0;
    amountEthIn = new uint256[](_components.length);
    amountComponents = new uint256[](_components.length);
    exchanges = new Exchange[](_components.length);
    pairAddresses = new address[](_components.length);

    for (uint256 i = 0; i < _components.length; i++) {
      // Check that the component does not have external positions
      //   require(
      //     _setToken.getExternalPositionModules(_components[i]).length == 0,
      //     "ExchangeIssuance: EXTERNAL_POSITIONS_NOT_ALLOWED"
      //   );

      // Get minimum amount of ETH to be spent to acquire the required amount of SetToken component
      uint256 unit = uint256(tokens[i]);
      amountComponents[i] = uint256(unit).preciseMulCeil(_amountSetToken);

      (
        amountEthIn[i],
        exchanges[i],
        pairAddresses[i]
      ) = _getMinTokenForExactToken(amountComponents[i], WETH, _components[i]);
      sumEth = sumEth.add(amountEthIn[i]);
    }
    return (sumEth, amountEthIn, exchanges, amountComponents, pairAddresses);
  }

  /**
   * Gets the total amount of ether returned from liquidating each component in a SetToken.
   *
   * @param _components           An array containing the addresses of the SetToken components
   * @param _amountSetToken       Amount of SetToken to be redeemed
   *
   * @return sumEth               The total amount of Ether that would be obtained from liquidating the SetTokens
   * @return amountComponents     An array containing the amount of SetToken component to be liquidated
   * @return exchanges            An array containing the exchange on which to liquidate the SetToken components
   */
  function _getAmountETHForRedemption(
    address[] memory _components,
    uint256 _amountSetToken
  )
    internal
    view
    returns (
      uint256,
      uint256[] memory,
      Exchange[] memory
    )
  {
    uint256 sumEth = 0;
    uint256 amountEth = 0;

    uint256[] memory amountComponents = new uint256[](_components.length);
    Exchange[] memory exchanges = new Exchange[](_components.length);

    for (uint256 i = 0; i < _components.length; i++) {
      // Check that the component does not have external positions
      //   require(
      //     _setToken.getExternalPositionModules(_components[i]).length == 0,
      //     "ExchangeIssuance: EXTERNAL_POSITIONS_NOT_ALLOWED"
      //   );

      uint256 unit = uint256(tokens[i]);
      amountComponents[i] = unit.preciseMul(_amountSetToken);

      // get maximum amount of ETH received for a given amount of SetToken component
      (amountEth, exchanges[i], ) = _getMaxTokenForExactToken(
        amountComponents[i],
        _components[i],
        WETH
      );
      sumEth = sumEth.add(amountEth);
    }
    return (sumEth, amountComponents, exchanges);
  }

  /**
   * Returns an estimated amount of SetToken that can be issued given an amount of input ERC20 token.
   *
   * @param _components           An array containing the addresses of the SetToken components
   * @param _amountEth            Total amount of ether available for the purchase of SetToken components
   *
   * @return setIssueAmount       The max amount of SetTokens that can be issued
   * @return amountEthIn          An array containing the amount ether required to purchase each SetToken component
   * @return exchanges            An array containing the exchange on which to purchase the SetToken components
   */
  function _getSetIssueAmountForETH(
    address[] memory _components,
    uint256 _amountEth
  )
    internal
    view
    returns (
      uint256 setIssueAmount,
      uint256[] memory amountEthIn,
      Exchange[] memory exchanges
    )
  {
    uint256 sumEth;
    uint256[] memory unitAmountEthIn;
    uint256[] memory unitAmountComponents;
    address[] memory pairAddresses;
    (
      sumEth,
      unitAmountEthIn,
      exchanges,
      unitAmountComponents,
      pairAddresses
    ) = _getAmountETHForIssuance(_components, PreciseUnitMath.preciseUnit());

    setIssueAmount = type(uint256).max;
    amountEthIn = new uint256[](_components.length);

    for (uint256 i = 0; i < _components.length; i++) {
      amountEthIn[i] = unitAmountEthIn[i].mul(_amountEth).div(sumEth);

      uint256 amountComponent;
      if (exchanges[i] == Exchange.None) {
        amountComponent = amountEthIn[i];
      } else {
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
      }
      setIssueAmount = MathUpgradeable.min(
        amountComponent.preciseDiv(unitAmountComponents[i]),
        setIssueAmount
      );
    }
    return (setIssueAmount, amountEthIn, exchanges);
  }

  /**
   * Swaps a given amount of an ERC20 token for WETH for the best price on Uniswap/Sushiswap.
   *
   * @param _token    Address of the ERC20 token to be swapped for WETH
   * @param _amount   Amount of ERC20 token to be swapped
   *
   * @return          Amount of WETH received after the swap
   */
  function _swapTokenForWETH(address _token, uint256 _amount)
    internal
    returns (uint256)
  {
    (, Exchange exchange, ) = _getMaxTokenForExactToken(
      _amount,
      address(_token),
      WETH
    );
    IUniswapV2Router02 router = _getRouter(exchange);
    _safeApprove(_token, address(router), _amount);
    return _swapExactTokensForTokens(exchange, address(_token), WETH, _amount);
  }

  /**
   * Swap exact tokens for another token on a given DEX.
   *
   * @param _exchange     The exchange on which to peform the swap
   * @param _tokenIn      The address of the input token
   * @param _tokenOut     The address of the output token
   * @param _amountIn     The amount of input token to be spent
   *
   * @return              The amount of output tokens
   */
  function _swapExactTokensForTokens(
    Exchange _exchange,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn
  ) internal returns (uint256) {
    if (_tokenIn == _tokenOut) {
      return _amountIn;
    }
    address[] memory path = new address[](2);
    path[0] = _tokenIn;
    path[1] = _tokenOut;
    return
      _getRouter(_exchange).swapExactTokensForTokens(
        _amountIn,
        0,
        path,
        address(this),
        block.timestamp
      )[1];
  }

  /**
   * Swap tokens for exact amount of output tokens on a given DEX.
   *
   * @param _exchange     The exchange on which to peform the swap
   * @param _tokenIn      The address of the input token
   * @param _tokenOut     The address of the output token
   * @param _amountOut    The amount of output token required
   *
   * @return              The amount of input tokens spent
   */
  function _swapTokensForExactTokens(
    Exchange _exchange,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountOut
  ) internal returns (uint256) {
    if (_tokenIn == _tokenOut) {
      return _amountOut;
    }
    address[] memory path = new address[](2);
    path[0] = _tokenIn;
    path[1] = _tokenOut;
    return
      _getRouter(_exchange).swapTokensForExactTokens(
        _amountOut,
        type(uint256).max,
        path,
        address(this),
        block.timestamp
      )[0];
  }

  /**
   * Compares the amount of token required for an exact amount of another token across both exchanges,
   * and returns the min amount.
   *
   * @param _amountOut    The amount of output token
   * @param _tokenA       The address of tokenA
   * @param _tokenB       The address of tokenB
   *
   * @return              The min amount of tokenA required across both exchanges
   * @return              The Exchange on which minimum amount of tokenA is required
   * @return              The pair address of the uniswap/sushiswap pool containing _tokenA and _tokenB
   */
  function _getMinTokenForExactToken(
    uint256 _amountOut,
    address _tokenA,
    address _tokenB
  )
    internal
    view
    returns (
      uint256,
      Exchange,
      address
    )
  {
    if (_tokenA == _tokenB) {
      return (_amountOut, Exchange.None, ETH_ADDRESS);
    }

    uint256 maxIn = type(uint256).max;
    uint256 uniTokenIn = maxIn;
    uint256 sushiTokenIn = maxIn;

    address uniswapPair = _getPair(uniFactory, _tokenA, _tokenB);
    if (uniswapPair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        uniswapPair,
        _tokenA,
        _tokenB
      );
      // Prevent subtraction overflow by making sure pool reserves are greater than swap amount
      if (reserveOut > _amountOut) {
        uniTokenIn = UniSushiV2Library.getAmountIn(
          _amountOut,
          reserveIn,
          reserveOut
        );
      }
    }

    address sushiswapPair = _getPair(sushiFactory, _tokenA, _tokenB);
    if (sushiswapPair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        sushiswapPair,
        _tokenA,
        _tokenB
      );
      // Prevent subtraction overflow by making sure pool reserves are greater than swap amount
      if (reserveOut > _amountOut) {
        sushiTokenIn = UniSushiV2Library.getAmountIn(
          _amountOut,
          reserveIn,
          reserveOut
        );
      }
    }

    // Fails if both the values are maxIn
    require(
      !(uniTokenIn == maxIn && sushiTokenIn == maxIn),
      "ExchangeIssuance: ILLIQUID_SET_COMPONENT"
    );
    return (uniTokenIn, Exchange.Uniswap, uniswapPair);
  }

  /**
   * Compares the amount of token received for an exact amount of another token across both exchanges,
   * and returns the max amount.
   *
   * @param _amountIn     The amount of input token
   * @param _tokenA       The address of tokenA
   * @param _tokenB       The address of tokenB
   *
   * @return              The max amount of tokens that can be received across both exchanges
   * @return              The Exchange on which maximum amount of token can be received
   * @return              The pair address of the uniswap/sushiswap pool containing _tokenA and _tokenB
   */
  function _getMaxTokenForExactToken(
    uint256 _amountIn,
    address _tokenA,
    address _tokenB
  )
    internal
    view
    returns (
      uint256,
      Exchange,
      address
    )
  {
    if (_tokenA == _tokenB) {
      return (_amountIn, Exchange.None, ETH_ADDRESS);
    }

    uint256 uniTokenOut = 0;
    uint256 sushiTokenOut = 0;

    address uniswapPair = _getPair(uniFactory, _tokenA, _tokenB);
    if (uniswapPair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        uniswapPair,
        _tokenA,
        _tokenB
      );
      uniTokenOut = UniSushiV2Library.getAmountOut(
        _amountIn,
        reserveIn,
        reserveOut
      );
    }

    address sushiswapPair = _getPair(sushiFactory, _tokenA, _tokenB);
    if (sushiswapPair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        sushiswapPair,
        _tokenA,
        _tokenB
      );
      sushiTokenOut = UniSushiV2Library.getAmountOut(
        _amountIn,
        reserveIn,
        reserveOut
      );
    }

    // Fails if both the values are 0
    require(
      !(uniTokenOut == 0 && sushiTokenOut == 0),
      "ExchangeIssuance: ILLIQUID_SET_COMPONENT"
    );
    return (uniTokenOut, Exchange.Uniswap, uniswapPair);
  }

  /**
   * Returns the pair address for on a given DEX.
   *
   * @param _factory   The factory to address
   * @param _tokenA    The address of tokenA
   * @param _tokenB    The address of tokenB
   *
   * @return           The pair address (Note: address(0) is returned by default if the pair is not available on that DEX)
   */
  function _getPair(
    address _factory,
    address _tokenA,
    address _tokenB
  ) internal view returns (address) {
    return IUniswapV2Factory(_factory).getPair(_tokenA, _tokenB);
  }

  /**
   * Returns the router address of a given exchange.
   *
   * @param _exchange     The Exchange whose router address is needed
   *
   * @return              IUniswapV2Router02 router of the given exchange
   */
  function _getRouter(Exchange _exchange)
    internal
    view
    returns (IUniswapV2Router02)
  {
    return (_exchange == Exchange.Uniswap) ? uniRouter : sushiRouter;
  }
}
