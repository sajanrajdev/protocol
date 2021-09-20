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
import "../interfaces/erc20/IERC20Detailed.sol";

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

  // Roles
  address public governance;
  address public manager;

  // Accounting
  address[] public tokens;
  uint256[] public weights;
  address[] public inputs;

  // Constants
  address public constant BASE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant PANGOLIN_ROUTER =
    0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
  uint256 public sl;
  uint256 public constant MAX_BPS = 10000;

  // Security
  mapping(address => uint256) public blockLock;

  // Token
  string internal constant _defaultNamePrefix = "Quad ";
  string internal constant _symbolSymbolPrefix = "x";

  /* ========== CONSTRUCTOR ========== */

  function initialize(
    address _governance,
    address _manager,
    address[3] memory _tokensConfig,
    uint256[3] memory _weightsConfig,
    address[3] memory _inputsConfig,
    bool _overrideTokenName,
    string memory _namePrefix,
    string memory _symbolPrefix
  ) public initializer whenNotPaused {
    /// @dev From config, add Roles and Accounting params
    governance = _governance;
    manager = _manager;
    tokens = _tokensConfig;
    weights = _weightsConfig;
    inputs = _inputsConfig;

    /// @dev Add token params

    string memory tokenName = "AVAX Blue Chip";
    string memory tokenSymbol = "QUAD";

    string memory name;
    string memory symbol;

    if (_overrideTokenName) {
      name = string(abi.encodePacked(_namePrefix, tokenName));
      symbol = string(abi.encodePacked(_symbolPrefix, tokenSymbol));
    } else {
      name = string(abi.encodePacked(_defaultNamePrefix, tokenName));
      symbol = string(abi.encodePacked(_symbolSymbolPrefix, tokenSymbol));
    }

    __ERC20_init(name, symbol);

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

    /// @dev Pause on launch.
    _pause();
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

  function mint(address _token, uint256 _amount) public whenNotPaused {
    /// @dev Security implementations
    _blockLocked();
    _lockForBlock(msg.sender);

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

  function burn(uint256 _shares) public whenNotPaused {
    /// @dev Security implementations
    _blockLocked();
    _lockForBlock(msg.sender);

    // Calculate user's weight in the vault (in fixed point form)
    uint256 ratio = _shares.mul(MAX_BPS).div(totalSupply()).div(MAX_BPS);
    // Burn
    _burn(msg.sender, _shares);

    // Loop through transfers
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 tokenBalance = IERC20Upgradeable(tokens[i]).balanceOf(
        address(this)
      );
      IERC20Upgradeable(tokens[i]).safeTransfer(
        msg.sender,
        ratio.mul(tokenBalance)
      );
    }
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function updateWeights() external {
    _onlyGovernance();
    // Call rebalance
    rebalance();
  }

  function rebalance() external {
    _onlyGovernance();
    _onlyManager();
    // Get current portfolio weights
    // Get target portfolio weights
    // Calculate surplus and location
    // Convert any surplus into BASE
    // Loop through rebalancing array path swaps
  }

  function pause() external {
    _onlyAuthorizedPausers();
    _pause();
  }

  function unpause() external {
    _onlyGovernance();
    _unpause();
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _lockForBlock(address account) internal {
    blockLock[account] = block.number;
  }

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

  function _onlyAuthorizedPausers() internal view {
    require(msg.sender == manager || msg.sender == governance, "onlyPausers");
  }

  function _onlyGovernance() internal view {
    require(msg.sender == governance, "onlyGovernance");
  }

  function _onlyManager() internal view {
    require(msg.sender == manager, "onlyGovernance");
  }

  function _blockLocked() internal view {
    require(blockLock[msg.sender] < block.number, "blockLocked");
  }

  /* ========== ERC20 OVERRIDES ========== */

  /// @dev Add blockLock to transfers, users cannot transfer tokens in the same block as a deposit or withdrawal.
  function transfer(address recipient, uint256 amount)
    public
    virtual
    override
    whenNotPaused
    returns (bool)
  {
    _blockLocked();
    return super.transfer(recipient, amount);
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public virtual override whenNotPaused returns (bool) {
    _blockLocked();
    return super.transferFrom(sender, recipient, amount);
  }

  /* ========== EVENTS ========== */
}
