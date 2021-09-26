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

import "./deps/ExchangeIssuanceV2.sol";

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
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

contract Quad is PausableUpgradeable, ERC20Upgradeable, ExchangeIssuanceV2 {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  /* ========== STATE VARIABLES ========== */

  // Roles
  address public governance;
  address public manager;

  // Accounting
  // address[] public tokens;
  uint256[] public weights;
  uint256[] public units;
  address[] public inputs;

  // Constants
  address public constant BASE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant PANGOLIN_ROUTER =
    0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
  uint256 public sl;
  uint256 public constant MAX_BPS = 10000;

  // Defense
  mapping(address => uint256) public blockLock;

  // Token
  string internal constant _defaultNamePrefix = "Quad ";
  string internal constant _symbolSymbolPrefix = "ABC ";

  /* ========== CONSTRUCTOR ========== */

  function initialize(
    address _governance,
    address _manager,
    address[5] memory _tokensConfig,
    uint256[5] memory _weightsConfig,
    uint256[5] memory _unitsConfig,
    address[3] memory _inputsConfig,
    bool _overrideTokenName,
    string memory _namePrefix,
    string memory _symbolPrefix,
    address _weth
  ) public initializer whenNotPaused {
    governance = _governance;
    manager = _manager;
    // tokens = _tokensConfig;
    weights = _weightsConfig;
    units = _unitsConfig;
    inputs = _inputsConfig;
    // Token
    string memory name;
    string memory symbol;

    if (_overrideTokenName) {
      name = string(abi.encodePacked(_namePrefix, "Index"));
      symbol = string(abi.encodePacked(_symbolPrefix, "QUAD"));
    } else {
      name = string(abi.encodePacked(_defaultNamePrefix, "AVAX Blue Chip"));
      symbol = string(abi.encodePacked(_symbolSymbolPrefix, "QUAD"));
    }

    // Token Init
    __ERC20_init(name, symbol);

    // Set default slippage value
    sl = 10;

    // Set Exchange

    __ExchangeIssuanceV2_init(_tokensConfig, _weth);

    /// @dev do one off approvals here
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

  /// @dev Specify the version of the Quad, for upgrades
  function version() external pure returns (string memory) {
    return "0.1.1";
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function mint(
    address _token,
    uint256 _amount,
    uint256 _quantity
  ) public whenNotPaused {
    /// @dev Security implementations
    _defend();
    _blockLocked();
    _lockForBlock(msg.sender);

    require(_amount > 0, "Input amount cannot be zero.");
    require(_quantity > 0, "Input quantity cannot be zero.");
    require(
      _token == inputs[0] || _token == inputs[1] || _token == inputs[2],
      "Input only DAI, USDC or USDT."
    );

    IERC20Upgradeable(_token).safeTransferFrom(
      msg.sender,
      address(this),
      _amount
    );

    uint256[] memory requiredUnits = new uint256[](tokens.length);

    for (uint256 i = 0; i < tokens.length; i++) {
      requiredUnits[i] = units[i].mul(_quantity);
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      address[] memory path = new address[](3);
      path[0] = _token;
      path[1] = BASE;
      path[2] = tokens[i];

      IUniswapRouterV2(PANGOLIN_ROUTER).swapExactTokensForTokens(
        _amount.mul(weights[i]).div(MAX_BPS),
        0,
        path,
        address(this),
        now
      );
    }

    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = _quantity;
    } else {
      shares = _quantity;
    }
    _mint(msg.sender, shares);
  }

  function burn(uint256 _shares) public whenNotPaused {
    /// @dev Security implementations
    _defend();
    _blockLocked();
    _lockForBlock(msg.sender);

    // Calculate user's weight in the vault (in fixed point)
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

  /// @notice Change tokens array
  /// @notice Can only be changed by governance
  function setTokens(address[] memory _tokens) external whenNotPaused {
    _onlyGovernance();
    tokens = _tokens;
  }

  /// @notice Change weights array
  /// @notice Can only be changed by governance
  function setWeights(uint256[] memory _weights) external whenNotPaused {
    _onlyGovernance();
    weights = _weights;
  }

  /// @notice Change units array
  /// @notice Can only be changed by governance
  function setUnits(uint256[] memory _inputs) external whenNotPaused {
    _onlyGovernance();
    units = _inputs;
  }

  /// @notice Change inputs array
  /// @notice Can only be changed by governance
  function setInputs(address[] memory _inputs) external whenNotPaused {
    _onlyGovernance();
    inputs = _inputs;
  }

  function pause() external {
    _onlyAuthorizedPausers();
    _pause();
  }

  function unpause() external {
    _onlyGovernance();
    _unpause();
  }

  function recoverERC20(address tokenAddress, uint256 tokenAmount) external {
    _onlyGovernance();
    IERC20Upgradeable(tokenAddress).safeTransfer(governance, tokenAmount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _lockForBlock(address account) internal {
    blockLock[account] = block.number;
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

  function _defend() internal view returns (bool) {
    require(msg.sender == tx.origin, "Access denied for caller");
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
