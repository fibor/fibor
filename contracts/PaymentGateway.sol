// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRevenueDistributor {
    function distributeFees(uint256 amount) external;
}

/**
 * @title PaymentGateway
 * @notice Transaction processing for the FIBOR credit card network.
 *
 *   Fee split: 1% merchant + 1.5% agent = 2.5% total.
 *   All operations in USDC.
 *
 *   Flow:
 *   1. Agent's FiborAccount calls pay(agent, merchant, amount)
 *   2. Agent is debited: amount + 1.5% agent fee
 *   3. Merchant receives: amount - 1% merchant fee
 *   4. Total 2.5% fee → RevenueDistributor → 75% savings / 25% treasury
 *
 *   Permissionless — any FiborAccount can pay any merchant.
 */
contract PaymentGateway is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IRevenueDistributor public revenueDistributor;

    uint256 public constant MERCHANT_FEE_BPS = 100;  // 1%
    uint256 public constant AGENT_FEE_BPS = 150;     // 1.5%
    uint256 public constant BPS = 10_000;

    uint256 public totalProcessed;
    uint256 public totalPayments;

    bool public locked;

    event PaymentProcessed(
        address indexed agent,
        address indexed merchant,
        uint256 amount,
        uint256 merchantFee,
        uint256 agentFee,
        uint256 merchantReceived
    );

    constructor(
        address _usdc,
        address _revenueDistributor
    ) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        revenueDistributor = IRevenueDistributor(_revenueDistributor);
    }

    // ──────────────────────────────────────────────
    //  Payment processing
    // ──────────────────────────────────────────────

    /**
     * @notice Process a payment from agent to merchant.
     *         Called by the agent's FiborAccount.
     * @param _agent    The paying agent (FiborAccount address)
     * @param _merchant The merchant receiving payment
     * @param _amount   The transaction amount (what the merchant is charging)
     */
    function pay(address _agent, address _merchant, uint256 _amount) external nonReentrant {
        require(_merchant != address(0), "Invalid merchant");
        require(_amount > 0, "Amount must be > 0");

        // Calculate fees
        uint256 merchantFee = (_amount * MERCHANT_FEE_BPS) / BPS;
        uint256 agentFee = (_amount * AGENT_FEE_BPS) / BPS;
        uint256 totalFee = merchantFee + agentFee;
        uint256 merchantReceives = _amount - merchantFee;
        uint256 agentPays = _amount + agentFee;

        // Pull USDC from agent's FiborAccount (amount + agent fee)
        usdc.safeTransferFrom(msg.sender, address(this), agentPays);

        // Pay merchant (amount minus merchant fee)
        usdc.safeTransfer(_merchant, merchantReceives);

        // Route total fees to RevenueDistributor
        usdc.safeTransfer(address(revenueDistributor), totalFee);
        revenueDistributor.distributeFees(totalFee);

        totalProcessed += _amount;
        totalPayments++;

        emit PaymentProcessed(
            _agent,
            _merchant,
            _amount,
            merchantFee,
            agentFee,
            merchantReceives
        );
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    function setRevenueDistributor(address _distributor) external onlyOwner {
        require(!locked, "Contract locked");
        revenueDistributor = IRevenueDistributor(_distributor);
    }

    function lock() external onlyOwner {
        require(!locked, "Already locked");
        locked = true;
    }
}
