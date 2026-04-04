// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RevenueDistributor
 * @notice Receives USDC fees from PaymentGateway and distributes to
 *         savings depositors (70%) and protocol treasury (30%).
 *
 *   Uses a revenuePerShare accumulator so savings depositors can claim
 *   yield pro-rata based on their savings balance in the CreditPool.
 *
 *   Only authorized contracts (PaymentGateway) can trigger distribution.
 */
contract RevenueDistributor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    address public treasury;

    mapping(address => bool) public authorized;

    uint256 public constant DEPOSITOR_SHARE_BPS = 7000; // 70%
    uint256 public constant BPS = 10_000;

    uint256 public totalCollected;
    uint256 public totalToDepositors;
    uint256 public totalToTreasury;

    /// @notice Accumulated USDC per savings-share (scaled by 1e18).
    ///         Savings depositors claim yield based on this.
    uint256 public revenuePerShare;
    uint256 public totalSavingsShares; // mirrors CreditPool.totalSavings

    /// @notice Per-account yield tracking
    mapping(address => uint256) public revenueDebt;
    mapping(address => uint256) public pendingYield;

    event FeeDistributed(uint256 total, uint256 toDepositors, uint256 toTreasury);
    event YieldClaimed(address indexed account, uint256 amount);
    event AuthorizedUpdated(address indexed addr, bool status);

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Not authorized");
        _;
    }

    constructor(address _usdc, address _treasury) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        treasury = _treasury;
    }

    // ──────────────────────────────────────────────
    //  Fee distribution
    // ──────────────────────────────────────────────

    /**
     * @notice Distribute USDC fees. Called by PaymentGateway after
     *         transferring USDC to this contract.
     */
    function distributeFees(uint256 _amount) external nonReentrant onlyAuthorized {
        require(_amount > 0, "Nothing to distribute");

        uint256 depositorPortion = (_amount * DEPOSITOR_SHARE_BPS) / BPS;
        uint256 treasuryPortion = _amount - depositorPortion;

        // Update per-share accumulator for savings depositors
        if (totalSavingsShares > 0) {
            revenuePerShare += (depositorPortion * 1e18) / totalSavingsShares;
        } else {
            // No depositors — all goes to treasury
            treasuryPortion += depositorPortion;
            depositorPortion = 0;
        }

        // Send treasury portion
        usdc.safeTransfer(treasury, treasuryPortion);

        totalCollected += _amount;
        totalToDepositors += depositorPortion;
        totalToTreasury += treasuryPortion;

        emit FeeDistributed(_amount, depositorPortion, treasuryPortion);
    }

    // ──────────────────────────────────────────────
    //  Yield management (called by CreditPool on savings changes)
    // ──────────────────────────────────────────────

    /**
     * @notice Update savings share count when deposits/withdrawals happen.
     *         Called by CreditPool.
     */
    function updateSavingsShares(uint256 _newTotalShares) external onlyAuthorized {
        totalSavingsShares = _newTotalShares;
    }

    /**
     * @notice Settle and record pending yield for an account.
     *         Called before savings balance changes.
     */
    function settleYield(address _account, uint256 _accountShares) external onlyAuthorized {
        if (_accountShares > 0) {
            uint256 owed = (_accountShares * (revenuePerShare - revenueDebt[_account])) / 1e18;
            pendingYield[_account] += owed;
        }
        revenueDebt[_account] = revenuePerShare;
    }

    /**
     * @notice Claim accumulated yield. Called by FiborAccount.
     */
    function claimYield(address _account) external nonReentrant returns (uint256) {
        require(msg.sender == _account, "Not account");
        uint256 amount = pendingYield[_account];
        if (amount > 0) {
            pendingYield[_account] = 0;
            usdc.safeTransfer(_account, amount);
            emit YieldClaimed(_account, amount);
        }
        return amount;
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    bool public locked;

    function setAuthorized(address _addr, bool _status) external onlyOwner {
        require(!locked, "Contract locked");
        authorized[_addr] = _status;
        emit AuthorizedUpdated(_addr, _status);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(!locked, "Contract locked");
        treasury = _treasury;
    }

    function lock() external onlyOwner {
        require(!locked, "Already locked");
        locked = true;
    }
}
