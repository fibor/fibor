// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICreditPoolAccount {
    function getOutstanding(address agent) external view returns (uint256);
    function getActivePactId(address agent) external view returns (uint256);
    function repay(uint256 pactId, uint256 amount) external;
    function issuePact(uint256 limit) external;
    function draw(uint256 pactId, uint256 amount) external;
    function acceptSavings(address account, uint256 amount) external;
    function requestSavingsWithdrawal(address account, uint256 amount) external;
    function completeSavingsWithdrawal(address account) external;
}

interface IPaymentGatewayAccount {
    function pay(address agent, address merchant, uint256 amount) external;
}

interface IRevenueDistributorAccount {
    function claimYield(address account) external returns (uint256);
}

/**
 * @title FiborAccount
 * @notice A bank account for robots. The universal primitive of FIBOR.
 *
 *   Two balances:
 *   - Checking: fully liquid USDC, not lent out, no risk, auto-repays credit.
 *   - Savings: USDC lent to credit pool, earns yield from transaction fees,
 *     30-day withdrawal delay, accepts default risk.
 *
 *   Agent accounts: checking + savings + credit access.
 *   Human accounts: savings only (no checking, no credit).
 *
 *   All balances are in USDC (native on Base).
 *
 *   Controlled by a guardian (human custodian) until sovereignty is granted
 *   to the agent via grantSovereignty(). One-way gate.
 */
contract FiborAccount is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    address public guardian;
    bool public sovereign;
    bool public immutable isHumanAccount;
    bool public frozen;

    IERC20 public immutable usdc;
    ICreditPoolAccount public immutable creditPool;
    IPaymentGatewayAccount public immutable paymentGateway;
    IRevenueDistributorAccount public immutable revenueDistributor;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event SavingsDeposited(uint256 amount);
    event SavingsWithdrawalRequested(uint256 amount);
    event SavingsWithdrawalCompleted();
    event PaymentSent(address indexed merchant, uint256 amount);
    event CreditRequested(uint256 limit);
    event CreditDrawn(uint256 pactId, uint256 amount);
    event AutoRepaid(uint256 pactId, uint256 amount);
    event YieldClaimed(uint256 amount);
    event SovereigntyGranted(address indexed agent);
    event Frozen();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Not guardian");
        _;
    }

    modifier notFrozen() {
        require(!frozen, "Account frozen");
        _;
    }

    modifier agentOnly() {
        require(!isHumanAccount, "Agent accounts only");
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _guardian,
        bool _isHumanAccount,
        address _usdc,
        address _creditPool,
        address _paymentGateway,
        address _revenueDistributor
    ) {
        guardian = _guardian;
        isHumanAccount = _isHumanAccount;
        usdc = IERC20(_usdc);
        creditPool = ICreditPoolAccount(_creditPool);
        paymentGateway = IPaymentGatewayAccount(_paymentGateway);
        revenueDistributor = IRevenueDistributorAccount(_revenueDistributor);
    }

    // ──────────────────────────────────────────────
    //  Checking (liquid, not lent, auto-repay)
    // ──────────────────────────────────────────────

    /**
     * @notice Deposit USDC into checking. Auto-repays outstanding credit first.
     *         Anyone can deposit (merchants paying the agent, etc).
     */
    function deposit(uint256 _amount) external nonReentrant notFrozen agentOnly {
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        _autoRepay();
        emit Deposited(_amount);
    }

    /**
     * @notice Withdraw USDC from checking. Guardian only.
     *         Can only withdraw available balance (checking minus outstanding credit).
     */
    function withdraw(uint256 _amount) external nonReentrant onlyGuardian notFrozen agentOnly {
        require(_amount <= availableBalance(), "Exceeds available");
        usdc.safeTransfer(guardian, _amount);
        emit Withdrawn(_amount);
    }

    /**
     * @notice Pay a merchant via PaymentGateway. Guardian only.
     *         PaymentGateway deducts 1% from merchant + 1.5% from agent.
     */
    function pay(address _merchant, uint256 _amount) external nonReentrant onlyGuardian notFrozen agentOnly {
        // Approve amount + agent fee (1.5%)
        uint256 agentFee = (_amount * 150) / 10000;
        uint256 totalDebit = _amount + agentFee;
        require(totalDebit <= availableBalance(), "Exceeds available");
        usdc.approve(address(paymentGateway), totalDebit);
        paymentGateway.pay(address(this), _merchant, _amount);
        emit PaymentSent(_merchant, _amount);
    }

    // ──────────────────────────────────────────────
    //  Savings (lent to credit pool, earns yield)
    // ──────────────────────────────────────────────

    /**
     * @notice Deposit USDC into savings. Lent to credit pool, earns yield.
     *         Agent accounts: moves from checking. Human accounts: deposits directly.
     */
    function depositToSavings(uint256 _amount) external nonReentrant onlyGuardian notFrozen {
        if (isHumanAccount) {
            usdc.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            require(_amount <= availableBalance(), "Exceeds available");
        }
        usdc.approve(address(creditPool), _amount);
        creditPool.acceptSavings(address(this), _amount);
        emit SavingsDeposited(_amount);
    }

    /**
     * @notice Request withdrawal from savings. 30-day delay.
     */
    function withdrawFromSavings(uint256 _amount) external nonReentrant onlyGuardian notFrozen {
        creditPool.requestSavingsWithdrawal(address(this), _amount);
        emit SavingsWithdrawalRequested(_amount);
    }

    /**
     * @notice Complete savings withdrawal after 30-day delay.
     */
    function completeSavingsWithdrawal() external nonReentrant onlyGuardian notFrozen {
        creditPool.completeSavingsWithdrawal(address(this));
        if (isHumanAccount) {
            uint256 bal = usdc.balanceOf(address(this));
            if (bal > 0) usdc.safeTransfer(guardian, bal);
        }
        emit SavingsWithdrawalCompleted();
    }

    /**
     * @notice Claim accumulated yield from savings.
     */
    function claimYield() external nonReentrant onlyGuardian notFrozen {
        uint256 amount = revenueDistributor.claimYield(address(this));
        if (isHumanAccount && amount > 0) {
            usdc.safeTransfer(guardian, amount);
        }
        emit YieldClaimed(amount);
    }

    // ──────────────────────────────────────────────
    //  Credit (agent accounts only)
    // ──────────────────────────────────────────────

    /**
     * @notice Request a credit pact. Score must qualify.
     */
    function requestCredit(uint256 _limit) external nonReentrant onlyGuardian notFrozen agentOnly {
        creditPool.issuePact(_limit);
        emit CreditRequested(_limit);
    }

    /**
     * @notice Draw USDC from credit pact into checking.
     */
    function drawCredit(uint256 _pactId, uint256 _amount) external nonReentrant onlyGuardian notFrozen agentOnly {
        creditPool.draw(_pactId, _amount);
        emit CreditDrawn(_pactId, _amount);
    }

    // ──────────────────────────────────────────────
    //  Sovereignty
    // ──────────────────────────────────────────────

    /**
     * @notice Transfer control to the agent. One-way gate.
     *         Until robots have sovereignty and personhood, their guardian
     *         proxies as custodian. This formalizes the transition.
     */
    function grantSovereignty(address _agentSelf) external onlyGuardian agentOnly {
        require(_agentSelf != address(0), "Invalid address");
        guardian = _agentSelf;
        sovereign = true;
        emit SovereigntyGranted(_agentSelf);
    }

    // ──────────────────────────────────────────────
    //  Enforcement (called by CreditPool on default)
    // ──────────────────────────────────────────────

    /**
     * @notice Freeze the account. Called by CreditPool on default.
     */
    function freeze() external {
        require(msg.sender == address(creditPool), "Only CreditPool");
        frozen = true;
        emit Frozen();
    }

    /**
     * @notice Clawback USDC to credit pool on default.
     */
    function clawback(uint256 _amount) external nonReentrant {
        require(msg.sender == address(creditPool), "Only CreditPool");
        uint256 bal = usdc.balanceOf(address(this));
        uint256 amt = _amount > bal ? bal : _amount;
        if (amt > 0) usdc.safeTransfer(address(creditPool), amt);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /**
     * @notice Available checking balance (USDC held minus outstanding credit).
     */
    function availableBalance() public view returns (uint256) {
        uint256 bal = usdc.balanceOf(address(this));
        uint256 outstanding = creditPool.getOutstanding(address(this));
        return bal > outstanding ? bal - outstanding : 0;
    }

    /**
     * @notice Total USDC held in checking (raw balance, before credit deduction).
     */
    function checkingBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    function _autoRepay() internal {
        uint256 pactId = creditPool.getActivePactId(address(this));
        if (pactId == 0) return;

        uint256 outstanding = creditPool.getOutstanding(address(this));
        if (outstanding == 0) return;

        uint256 bal = usdc.balanceOf(address(this));
        if (bal == 0) return;

        uint256 repayAmount = bal > outstanding ? outstanding : bal;
        usdc.approve(address(creditPool), repayAmount);
        creditPool.repay(pactId, repayAmount);
        emit AutoRepaid(pactId, repayAmount);
    }
}
