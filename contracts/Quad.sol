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

import { UniSushiV2Library } from "../external/UniSushiV2Library.sol";
import { IUniswapV2Factory } from "../interfaces/uniswap/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "../interfaces/uniswap/IUniswapV2Router02.sol";
import { IWETH } from "../interfaces/erc20/IWETH.sol";

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

/**
 * @title Quads
 * @author Quads Finance Team
 *
 * Upgradable contract for minting and burning index fund tokens (quads), using any ERC-20 token
 * as the paying currency.
 *
 */

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
  uint256[] public units;
  address[] public inputs;

  // Constants
  address public constant BASE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address public constant ROUTER = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
  address public constant FACTORY = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;

  uint256 private constant MAX_UINT96 = 2**96 - 1;
  uint256 public sl;
  uint256 public constant MAX_BPS = 10000;

  // Defense
  mapping(address => uint256) public blockLock;

  // Token
  string internal constant _defaultName = "AVAX Blue Chip Quad";
  string internal constant _defaultSymbol = "DEFI5";

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
    string memory _symbolPrefix
  ) public initializer whenNotPaused {
    __Pausable_init();
    governance = _governance;
    manager = _manager;
    tokens = _tokensConfig;
    weights = _weightsConfig;
    units = _unitsConfig;
    inputs = _inputsConfig;

    // Token
    string memory name;
    string memory symbol;

    if (_overrideTokenName) {
      name = string(abi.encodePacked(_namePrefix));
      symbol = string(abi.encodePacked(_symbolPrefix));
    } else {
      name = string(abi.encodePacked(_defaultName));
      symbol = string(abi.encodePacked(_defaultSymbol));
    }

    // Token Init
    __ERC20_init(name, symbol);

    // Set default slippage value
    sl = 10;

    /// @dev do one off approvals here
    IERC20Upgradeable(inputs[0]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(inputs[1]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(inputs[2]).safeApprove(ROUTER, type(uint256).max);
    IERC20Upgradeable(BASE).safeApprove(ROUTER, type(uint256).max);

    /// @dev Pause on launch.
    _pause();
  }

  /* ========== VIEWS ========== */

  /**
   * Specifies the version of the Quad for future upgrades.
   *
   * @return    String containing version of the Quad deployment.
   */
  function version() external pure returns (string memory) {
    return "0.1.0";
  }

  /**
   * Returns an estimated amount of QuadTokens that can be issued given an amount of input ERC20 token.
   *
   * @param _inputToken       Address of input token.
   * @param _amountInput      Amount of the input token to spend
   *
   * @return                  Estimated amount of QuadTokens that will be received
   */
  function getEstimatedQuadsGivenInput(
    address _inputToken,
    uint256 _amountInput
  ) external view returns (uint256) {
    require(_amountInput > 0, "Quad: INVALID INPUTS");
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
    address[] memory components = tokens;
    // get min amount of ETH to be spent to acquire the required amount of each Quad components
    // amountEthIn is an array containing the amoutn of weth required to purchase each componenet in Quad.
    uint256 sumEth = 0;
    uint256[] memory amountEthIn = new uint256[](components.length);
    address[] memory pairAddresses = new address[](components.length);

    for (uint256 i = 0; i < components.length; i++) {
      (amountEthIn[i], pairAddresses[i]) = _getMinTokenForExactToken(
        units[i],
        WETH,
        tokens[i]
      );
      sumEth = sumEth.add(amountEthIn[i]);
    }
    // return (sumEth, amountEthIn, pairAddresses);
    uint256[] memory budgetPerComponent = new uint256[](components.length);
    for (uint256 i = 0; i < components.length; i++) {
      // Needs to account for weight in portfolio
      budgetPerComponent[i] = amountEth.mul(weights[i]).div(MAX_BPS);
    }

    uint256[] memory divisors = new uint256[](components.length);
    for (uint256 i = 0; i < components.length; i++) {
      divisors[i] = budgetPerComponent[i].div(amountEthIn[i]);
    }

    uint256 quadIssueAmount = type(uint256).max;

    for (uint256 i = 0; i < components.length; i++) {
      quadIssueAmount = MathUpgradeable.min(divisors[i], quadIssueAmount);
    }
    return quadIssueAmount;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * Issues QuadTokens for an exact amount of input ERC20 tokens.
   * The ERC20 token must be approved by the sender to this contract.
   * This method does not return any data.
   *
   * @param _token       Address of input token
   * @param _amount      Amount of the input token / ether to spend
   * @param _quantity    Minimum amount of SetTokens to receive. Prevents unnecessary slippage.
   */
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
    uint256 targetShares = _calculateQuadForExactToken(
      _token,
      _amount,
      _quantity
    );

    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = targetShares;
    } else {
      shares = targetShares;
    }
    _mint(msg.sender, shares);
  }

  /**
   * Burns the QuadToken's positions and sends the components of the given
   * quantity to the caller.
   * This method does not return any data.
   *
   * @param _shares             Quantity of the QuadToken to burn and redeem
   */

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

  /**
   * Changes the tokens array, can only be called by governance.
   * The tokens state contains the list of ERC-20 constituting each Quad.
   * Tokens should not be altered in v0.1.0.
   *
   * @param _tokens             Array of token addresses updating the `tokens` state.
   */
  function setTokens(address[] memory _tokens) external whenNotPaused {
    _onlyGovernance();
    tokens = _tokens;
  }

  /**
   * Changes the weights array, can only be called by governance.
   * The weights state dictates the "weight" of each token in the tokens list in our Quad contract.
   * Weights should not be altered in v0.1.0.
   *
   * @param _weights             Array of uint256 weights updating the `weights` state.
   */
  function setWeights(uint256[] memory _weights) external whenNotPaused {
    _onlyGovernance();
    weights = _weights;
  }

  /**
   * Changes the units array, can only be called by governance.
   * The units state defines (in uint256) the amount of each token in tokens, needed to issue a single share.
   * Units should not be altered in v0.1.0.
   *
   * @param _units             Array of uint256 units updating the `units` state.
   */
  function setUnits(uint256[] memory _units) external whenNotPaused {
    _onlyGovernance();
    units = _units;
  }

  /**
   * Changes the inputs array, can only be called by governance.
   * The inputs state restricts the type of tokens that can be used to purchase a share.
   * Currently, in v0.1.0, only DAI, USDT and USDC are supported. However, this contract can support any token in the router.
   * Inputs should not be altered in v0.1.0.
   *
   * @param _inputs             Array of token addresses updating the `inputs` state.
   */
  function setInputs(address[] memory _inputs) external whenNotPaused {
    _onlyGovernance();
    inputs = _inputs;
  }

  /**
   * Allows governance or manager to pause the contract.
   * When paused, methods with whenNotPaused, will revert upon call.
   */
  function pause() external {
    _onlyAuthorizedPausers();
    _pause();
  }

  /**
   * Only allows governance to unpause the contract.
   * When unpaused, methods with whenNotPaused, will not revert upon call.
   */
  function unpause() external {
    _onlyGovernance();
    _unpause();
  }

  /**
   * Allows governance to rescue any ERC-20 token sent accidentally to this contract.
   * Method does not allow governance to withdraw any token in the tokens state.
   * Recovered tokens are always sent to the governance multisig.
   *
   * @param tokenAddress             Address of token being recovered.
   * @param tokenAmount              Amount (in uint256) being recovered.
   */
  function recoverERC20(address tokenAddress, uint256 tokenAmount) external {
    _onlyGovernance();
    for (uint256 i = 0; i < tokens.length; i++) {
      require(tokenAddress != tokens[i], "Asset is protected");
    }
    IERC20Upgradeable(tokenAddress).safeTransfer(governance, tokenAmount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * Sets a max approval limit for an ERC20 token, provided the current allowance
   * is less than the required allowance.
   *
   * @param _token    Token to approve
   * @param _spender  Spender address to approve
   * @param _requiredAllowance  Allowance necessary for transaction
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
        MAX_UINT96 - allowance
      );
    }
  }

  /**
   * Returns number of QuadTokens to mint, given an exact amount of input ERC20 tokens.
   * The ERC20 token must be approved by the sender to this contract.
   * This method also swaps the input ERC20 for each component in the Quad tokens state.
   *
   * @param _inputToken       Address of input token
   * @param _amountInput      Amount of the input token / ether to spend
   * @param _minQuadReceive   Minimum amount of QuadTokens to receive. Prevents unnecessary slippage.
   *
   * @return quadIssueAmount  Amount of SetTokens issued to the caller
   */
  function _calculateQuadForExactToken(
    address _inputToken,
    uint256 _amountInput,
    uint256 _minQuadReceive
  ) internal returns (uint256) {
    require(_amountInput > 0, "Quad: INVALID INPUTS");
    IERC20Upgradeable(_inputToken).safeTransferFrom(
      msg.sender,
      address(this),
      _amountInput
    );

    uint256 amountEth = _inputToken == WETH
      ? _amountInput
      : _swapTokenForWETH(_inputToken, _amountInput);

    address[] memory components = tokens;
    uint256 sumEth = 0;
    uint256[] memory amountEthIn = new uint256[](components.length);
    address[] memory pairAddresses = new address[](components.length);
    for (uint256 i = 0; i < components.length; i++) {
      (amountEthIn[i], pairAddresses[i]) = _getMinTokenForExactToken(
        units[i],
        WETH,
        tokens[i]
      );
      sumEth = sumEth.add(amountEthIn[i]);
    }
    uint256[] memory budgetPerComponent = new uint256[](components.length);
    for (uint256 i = 0; i < components.length; i++) {
      // Needs to account for weight in portfolio
      budgetPerComponent[i] = amountEth.mul(weights[i]).div(MAX_BPS);
    }
    uint256[] memory divisors = new uint256[](components.length);
    for (uint256 i = 0; i < components.length; i++) {
      divisors[i] = budgetPerComponent[i].div(amountEthIn[i]);
    }

    for (uint256 i = 0; i < components.length; i++) {
      _swapExactTokensForTokens(
        WETH,
        components[i],
        amountEthIn[i].mul(divisors[i])
      );
    }
    uint256 quadIssueAmount = type(uint256).max;

    for (uint256 i = 0; i < components.length; i++) {
      quadIssueAmount = MathUpgradeable.min(divisors[i], quadIssueAmount);
    }
    return quadIssueAmount;
  }

  function _getMinTokenForExactToken(
    uint256 _amountOut,
    address _tokenA,
    address _tokenB
  ) internal view returns (uint256, address) {
    uint256 maxIn = type(uint256).max;
    uint256 tokenIn = maxIn;
    address pair = _getPair(FACTORY, _tokenA, _tokenB);
    if (pair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        pair,
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
    return (tokenIn, pair);
  }

  function _getMaxTokenForExactToken(
    uint256 _amountIn,
    address _tokenA,
    address _tokenB
  ) internal view returns (uint256, address) {
    uint256 tokenOut;
    address pair = _getPair(FACTORY, _tokenA, _tokenB);
    if (pair != address(0)) {
      (uint256 reserveIn, uint256 reserveOut) = UniSushiV2Library.getReserves(
        pair,
        _tokenA,
        _tokenB
      );
      tokenOut = UniSushiV2Library.getAmountOut(
        _amountIn,
        reserveIn,
        reserveOut
      );
    }
    return (tokenOut, pair);
  }

  function _swapTokenForWETH(address _token, uint256 _amount)
    internal
    returns (uint256)
  {
    _safeApprove(_token, ROUTER, _amount);
    return _swapExactTokensForTokens(_token, WETH, _amount);
  }

  function _swapExactTokensForTokens(
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
      IUniswapRouterV2(ROUTER).swapExactTokensForTokens(
        _amountIn,
        0,
        path,
        address(this),
        now
      )[1];
  }

  function _getPair(
    address _factory,
    address _tokenA,
    address _tokenB
  ) internal view returns (address) {
    return IUniswapV2Factory(_factory).getPair(_tokenA, _tokenB);
  }

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
