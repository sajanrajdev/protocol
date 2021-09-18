// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../deps/@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IUniswapRouterV2 } from "../interfaces/uniswap/IUniswapRouterV2.sol";

//  ________  ___  ___  ________  ________  ________
// |\   __  \|\  \|\  \|\   __  \|\   ___ \|\   ____\
// \ \  \|\  \ \  \\\  \ \  \|\  \ \  \_|\ \ \  \___|_
//  \ \  \\\  \ \  \\\  \ \   __  \ \  \ \\ \ \_____  \
//   \ \  \\\  \ \  \\\  \ \  \ \  \ \  \_\\ \|____|\  \
//    \ \_____  \ \_______\ \__\ \__\ \_______\____\_\  \
//     \|___| \__\|_______|\|__|\|__|\|_______|\_________\
//           \|__|                            \|_________|
//
//   Quads Finance: Quads.sol
//
//   Docs: https://docs.quads.finance/
//
//
//   MIT License
//   ===========
//
//   Copyright (c) 2021 Quads Finance
//
//   Permission is hereby granted, free of charge, to any person obtaining a copy
//   of this software and associated documentation files (the "Software"), to deal
//   in the Software without restriction, including without limitation the rights
//   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//   copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all
//   copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

contract Quad is PausableUpgradeable, ERC20Upgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  /* ========== STATE VARIABLES ========== */

  ///@dev initialized state variables
  address public governance;
  address public manager;
  address[] public tokens;
  uint256[] public weights;
  address[] public inputs;

  address public constant BASE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant PANGOLIN_ROUTER =
    0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
  uint256 public sl;
  uint256 public constant MAX_BPS = 10000;

  /* ========== CONSTRUCTOR ========== */

  function initialize(
    address _governance,
    address _manager,
    address[3] memory _tokensConfig,
    uint256[3] memory _weightsConfig,
    address[3] memory _inputsConfig
  ) public initializer whenNotPaused {
    __Pausable_init();
    /// @dev Add config here
    governance = _governance;
    manager = _manager;
    tokens = _tokensConfig;
    weights = _weightsConfig;
    inputs = _inputsConfig;

    // Set default slippage value
    sl = 10;

    /// @dev do one off approvals here
    IERC20Upgradeable(tokens[0]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(tokens[1]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(tokens[2]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(inputs[0]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(inputs[1]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(inputs[2]).safeApprove(
      PANGOLIN_ROUTER,
      type(uint256).max
    );
    IERC20Upgradeable(BASE).safeApprove(PANGOLIN_ROUTER, type(uint256).max);
  }

  /* ========== VIEWS ========== */

  /// @dev Specify the name of the strategy
  function getName() external pure virtual returns (string memory) {
    return "Blue-Chip-Quad";
  }

  /// @dev Specify the version of the Quad, for upgrades
  function version() external pure returns (string memory) {
    return "1.1";
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function mint(address _token, uint256 _amount) public {
    require(_amount > 0, "Input amount cannot be zero.");
    require(
      _token == inputs[0] || _token == inputs[1] || _token == inputs[2],
      "Input only DAI, USDC or USDT."
    );

    // Collect one of three possible stablecoins
    IERC20Upgradeable(_token).safeTransferFrom(
      msg.sender,
      address(this),
      _amount
    );

    // Turn it into the underlyings with respective weights
    inputToUnderlying(_token, _amount);

    // mint user same dollar amount in token
    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = _amount;
    } else {
      shares = _amount;
    }
    _mint(msg.sender, shares);
  }

  function burn() public {}

  /* ========== RESTRICTED FUNCTIONS ========== */

  function updateWeights() external {}

  function rebalance() external {}

  /* ========== INTERNAL FUNCTIONS ========== */

  function inputToUnderlying(address _token, uint256 _amount) internal {
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 _quantity = _amount.mul(weights[i]).div(MAX_BPS);

      address[] memory path = new address[](3);
      path[0] = _token;
      path[1] = BASE;
      path[2] = tokens[i];

      IUniswapRouterV2(PANGOLIN_ROUTER).swapExactTokensForTokens(
        _quantity,
        0,
        path,
        address(this),
        now
      );
    }
  }

  /* ========== MODIFIERS ========== */

  /* ========== EVENTS ========== */
}
