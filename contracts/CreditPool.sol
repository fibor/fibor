// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IFiborScore {
    function getScore(address agent) external view returns (uint256);
    function getMaxCreditLine(address agent) external view returns (uint256);
    function recordDefault(address agent) external;
    function recordRepayment(address agent, uint256 amount) external;
}

interface IFiborID {
    function isActive(address agent) external view returns (bool);
    function excommunicate(address agent) external;
}

interface IFiborAccountClawback {
    function freeze() external;
    function clawback(uint256 amount) external;
}

/**
 * @title CreditPool
 * @notice The credit facility that backs agent credit lines.
 *
 *   Capital comes from savings deposits by FiborAccount holders
 *   (both agents and humans). No external stakers.
 *
 *   Flow
 *   ----
 *   1. FiborAccounts deposit savings → USDC enters pool.
 *   2. Agent with active FIBOR ID + qualifying score self-issues a pact.
 *   3. Agent draws USDC up to the approved limit.
 *   4. Agent repays USDC within the pact window. No interest.
 *   5. On default: FiborAccount is frozen, USDC clawed back, agent excommunicated.
 *
 *   Credit limits = 25% of total volume repaid (from FiborScore).
 *   New agents get micro seed ($100-$500) based on developer reputation.
 *   Repayment window: 30 days for all pacts.
 */
contract CreditPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    enum PactStatus { Active, Repaid, Defaulted }

    struct CreditPact {
        address agent;
        uint256 limit;
        uint256 drawn;
        uint256 repaid;
        uint256 issuedAt;
        uint256 expiresAt;
        PactStatus status;
    }

    struct SavingsInfo {
        uint256 balance;
        uint256 withdrawalRequest;
        uint256 withdrawalTime;
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    IERC20 public immutable usdc;
    IFiborScore public fiborScore;
    IFiborID public fiborID;

    uint256 public totalSavings;        // total USDC from savings deposits
    uint256 public totalLent;           // USDC currently out as credit

    uint256 public nextPactId = 1;
    mapping(uint256 => CreditPact) public pacts;
    mapping(address => uint256[]) public agentPacts;
    mapping(address => bool) public hasActivePact;

    /// @notice Per-account savings tracking
    mapping(address => SavingsInfo) public savings;

    uint256 public constant GRACE_PERIOD = 24 hours;
    uint256 public constant SAVINGS_COOLDOWN = 30 days;
    uint256 public constant PACT_DURATION = 30 days;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event SavingsAccepted(address indexed account, uint256 amount);
    event SavingsWithdrawalRequested(address indexed account, uint256 amount);
    event SavingsWithdrawalCompleted(address indexed account, uint256 amount);
    event PactCreated(uint256 indexed pactId, address indexed agent, uint256 limit, uint256 expiresAt);
    event CreditDrawn(uint256 indexed pactId, uint256 amount);
    event CreditRepaid(uint256 indexed pactId, uint256 amount);
    event PactClosed(uint256 indexed pactId, PactStatus status);
    event DefaultDeclared(uint256 indexed pactId, address indexed agent, uint256 recovered);

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _usdc,
        address _fiborScore,
        address _fiborID
    ) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        fiborScore = IFiborScore(_fiborScore);
        fiborID = IFiborID(_fiborID);
    }

    // ──────────────────────────────────────────────
    //  Savings (replaces StakingPool)
    // ──────────────────────────────────────────────

    /**
     * @notice Accept savings deposit from a FiborAccount.
     *         USDC is lent to the credit pool. Depositor earns yield.
     */
    function acceptSavings(address _account, uint256 _amount) external nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        savings[_account].balance += _amount;
        totalSavings += _amount;
        emit SavingsAccepted(_account, _amount);
    }

    /**
     * @notice Request savings withdrawal. 30-day delay.
     */
    function requestSavingsWithdrawal(address _account, uint256 _amount) external nonReentrant {
        require(msg.sender == _account, "Not account owner");
        SavingsInfo storage info = savings[_account];
        require(_amount <= info.balance, "Exceeds savings");
        require(info.withdrawalRequest == 0, "Pending withdrawal exists");

        info.withdrawalRequest = _amount;
        info.withdrawalTime = block.timestamp;
        emit SavingsWithdrawalRequested(_account, _amount);
    }

    /**
     * @notice Complete savings withdrawal after 30-day delay.
     */
    function completeSavingsWithdrawal(address _account) external nonReentrant {
        require(msg.sender == _account, "Not account owner");
        SavingsInfo storage info = savings[_account];
        require(info.withdrawalRequest > 0, "No pending withdrawal");
        require(
            block.timestamp >= info.withdrawalTime + SAVINGS_COOLDOWN,
            "Cooldown not elapsed"
        );

        uint256 amount = info.withdrawalRequest;
        require(amount <= availableLiquidity(), "Insufficient liquidity");

        info.balance -= amount;
        info.withdrawalRequest = 0;
        info.withdrawalTime = 0;
        totalSavings -= amount;

        usdc.safeTransfer(_account, amount);
        emit SavingsWithdrawalCompleted(_account, amount);
    }

    // ──────────────────────────────────────────────
    //  Credit issuance (self-service, permissionless)
    // ──────────────────────────────────────────────

    /**
     * @notice Request a credit pact. Called by FiborAccount.
     *         Credit limit = 25% of total volume repaid (from FiborScore).
     *         New agents get micro seed based on developer reputation.
     */
    function issuePact(uint256 _limit) external nonReentrant {
        address agent = msg.sender;
        require(fiborID.isActive(agent), "No active FIBOR ID");
        require(!hasActivePact[agent], "Active pact exists");

        uint256 maxLimit = fiborScore.getMaxCreditLine(agent);
        require(maxLimit > 0, "No credit available");
        require(_limit <= maxLimit, "Exceeds max credit line");
        require(_limit <= availableLiquidity(), "Insufficient liquidity");

        uint256 pactId = nextPactId++;
        pacts[pactId] = CreditPact({
            agent: agent,
            limit: _limit,
            drawn: 0,
            repaid: 0,
            issuedAt: block.timestamp,
            expiresAt: block.timestamp + PACT_DURATION,
            status: PactStatus.Active
        });
        agentPacts[agent].push(pactId);
        hasActivePact[agent] = true;

        emit PactCreated(pactId, agent, _limit, block.timestamp + PACT_DURATION);
    }

    /**
     * @notice Draw USDC from credit pact. Sent to the agent's FiborAccount.
     */
    function draw(uint256 _pactId, uint256 _amount) external nonReentrant {
        CreditPact storage pact = pacts[_pactId];
        require(msg.sender == pact.agent, "Not your pact");
        require(pact.status == PactStatus.Active, "Pact not active");
        require(block.timestamp < pact.expiresAt, "Pact expired");
        require(pact.drawn + _amount <= pact.limit, "Exceeds limit");
        require(_amount <= availableLiquidity(), "Insufficient liquidity");

        pact.drawn += _amount;
        totalLent += _amount;

        // Transfer USDC directly to agent's FiborAccount
        usdc.safeTransfer(pact.agent, _amount);

        emit CreditDrawn(_pactId, _amount);
    }

    /**
     * @notice Repay USDC. No interest — just the principal.
     *         Called by FiborAccount during auto-repay.
     */
    function repay(uint256 _pactId, uint256 _amount) external nonReentrant {
        CreditPact storage pact = pacts[_pactId];
        require(msg.sender == pact.agent, "Not your pact");
        require(pact.status == PactStatus.Active, "Pact not active");

        uint256 outstanding = pact.drawn - pact.repaid;
        uint256 payment = _amount > outstanding ? outstanding : _amount;

        // Transfer USDC from agent's FiborAccount to pool
        usdc.safeTransferFrom(pact.agent, address(this), payment);

        pact.repaid += payment;
        totalLent -= payment;

        if (pact.repaid >= pact.drawn) {
            pact.status = PactStatus.Repaid;
            hasActivePact[pact.agent] = false;
            fiborScore.recordRepayment(pact.agent, pact.drawn);
            emit PactClosed(_pactId, PactStatus.Repaid);
        }

        emit CreditRepaid(_pactId, payment);
    }

    // ──────────────────────────────────────────────
    //  Default enforcement
    // ──────────────────────────────────────────────

    /**
     * @notice Anyone can call after grace period. Freezes agent's FiborAccount,
     *         claws back USDC, excommunicates agent.
     */
    function declareDefault(uint256 _pactId) external nonReentrant {
        CreditPact storage pact = pacts[_pactId];
        require(pact.status == PactStatus.Active, "Pact not active");
        require(
            block.timestamp >= pact.expiresAt + GRACE_PERIOD,
            "Grace period not elapsed"
        );
        require(pact.repaid < pact.drawn, "Pact is repaid");

        pact.status = PactStatus.Defaulted;
        hasActivePact[pact.agent] = false;

        uint256 outstanding = pact.drawn - pact.repaid;

        // Clawback USDC from agent's FiborAccount
        IFiborAccountClawback account = IFiborAccountClawback(pact.agent);
        account.clawback(outstanding);
        uint256 recovered = usdc.balanceOf(address(this)) > totalSavings
            ? usdc.balanceOf(address(this)) - totalSavings + totalLent
            : 0;
        totalLent -= outstanding > recovered ? recovered : outstanding;

        // Freeze the account
        account.freeze();

        // Record default and excommunicate
        fiborScore.recordDefault(pact.agent);
        fiborID.excommunicate(pact.agent);

        emit DefaultDeclared(_pactId, pact.agent, recovered);
        emit PactClosed(_pactId, PactStatus.Defaulted);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function getOutstanding(address _agent) external view returns (uint256) {
        uint256[] storage pactIds = agentPacts[_agent];
        for (uint256 i = pactIds.length; i > 0; i--) {
            CreditPact storage pact = pacts[pactIds[i - 1]];
            if (pact.status == PactStatus.Active) {
                return pact.drawn - pact.repaid;
            }
        }
        return 0;
    }

    function getActivePactId(address _agent) external view returns (uint256) {
        uint256[] storage pactIds = agentPacts[_agent];
        for (uint256 i = pactIds.length; i > 0; i--) {
            if (pacts[pactIds[i - 1]].status == PactStatus.Active) {
                return pactIds[i - 1];
            }
        }
        return 0;
    }

    function availableLiquidity() public view returns (uint256) {
        return totalSavings - totalLent;
    }

    function getPact(uint256 _pactId) external view returns (CreditPact memory) {
        return pacts[_pactId];
    }

    function getAgentPacts(address _agent) external view returns (uint256[] memory) {
        return agentPacts[_agent];
    }

    function getSavings(address _account) external view returns (SavingsInfo memory) {
        return savings[_account];
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    bool public locked;

    function setFiborScore(address _fiborScore) external onlyOwner {
        require(!locked, "Contract locked");
        fiborScore = IFiborScore(_fiborScore);
    }

    function setFiborID(address _fiborID) external onlyOwner {
        require(!locked, "Contract locked");
        fiborID = IFiborID(_fiborID);
    }

    function lock() external onlyOwner {
        require(!locked, "Already locked");
        locked = true;
    }

}
