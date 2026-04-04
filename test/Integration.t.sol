// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/FIBORToken.sol";
import "../contracts/FiborID.sol";
import "../contracts/FiborScore.sol";
import "../contracts/FiborAccount.sol";
import "../contracts/FiborAccountFactory.sol";
import "../contracts/CreditPool.sol";
import "../contracts/PaymentGateway.sol";
import "../contracts/RevenueDistributor.sol";

/// @dev Minimal ERC-20 for testing (mock USDC)
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract IntegrationTest is Test {
    MockUSDC usdc;
    FIBORToken fiborToken;
    FiborScore fiborScore;
    FiborID fiborID;
    FiborAccountFactory factory;
    CreditPool creditPool;
    PaymentGateway paymentGateway;
    RevenueDistributor revenueDistributor;

    address treasury = address(0xBEEF);
    address developer = address(0xDEAD);
    address agent = address(0xA1);
    address merchant = address(0xCAFE);

    function setUp() public {
        // Deploy core contracts
        usdc = new MockUSDC();
        fiborToken = new FIBORToken(treasury);
        fiborScore = new FiborScore();
        fiborID = new FiborID(address(fiborScore));
        revenueDistributor = new RevenueDistributor(address(usdc), treasury);

        // Deploy CreditPool
        creditPool = new CreditPool(
            address(usdc),
            address(fiborScore),
            address(fiborID)
        );

        // Deploy PaymentGateway
        paymentGateway = new PaymentGateway(
            address(usdc),
            address(revenueDistributor)
        );

        // Deploy FiborAccountFactory
        factory = new FiborAccountFactory(
            address(usdc),
            address(creditPool),
            address(paymentGateway),
            address(revenueDistributor)
        );

        // Wire contracts
        fiborID.setAccountFactory(address(factory));
        fiborID.setCreditPool(address(creditPool));
        fiborScore.setAuthorized(address(fiborID), true);
        fiborScore.setAuthorized(address(creditPool), true);
        fiborScore.setFiborID(address(fiborID));
        revenueDistributor.setAuthorized(address(paymentGateway), true);
    }

    // ─────────────────────────────────────────
    //  Test: Basic registration
    // ─────────────────────────────────────────

    function test_registerAgent() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (address dev, address account,,, ) = fiborID.identities(agent);
        assertEq(dev, developer);
        assertTrue(account != address(0), "Account should be deployed");
        assertTrue(fiborID.isActive(agent));
    }

    function test_registerHuman() public {
        address human = address(0xBEAD);
        vm.prank(human);
        fiborID.registerHuman("ipfs://human");

        (address dev, address account,,, ) = fiborID.identities(human);
        assertEq(dev, human);
        assertTrue(account != address(0));
    }

    function test_duplicateRegistrationReverts() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        vm.expectRevert("Already registered");
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata2");
    }

    // ─────────────────────────────────────────
    //  Test: FiborAccount deposit/withdraw
    // ─────────────────────────────────────────

    function test_depositAndWithdraw() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);
        FiborAccount account = FiborAccount(accountAddr);

        // Mint USDC and deposit
        usdc.mint(developer, 10_000e6);
        vm.startPrank(developer);
        usdc.approve(accountAddr, 10_000e6);
        account.deposit(10_000e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(accountAddr), 10_000e6);

        // Withdraw
        vm.prank(developer);
        account.withdraw(5_000e6);

        assertEq(usdc.balanceOf(accountAddr), 5_000e6);
        assertEq(usdc.balanceOf(developer), 5_000e6);
    }

    // ─────────────────────────────────────────
    //  Test: Savings deposit
    // ─────────────────────────────────────────

    function test_savingsDeposit() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);
        FiborAccount account = FiborAccount(accountAddr);

        // Fund the account
        usdc.mint(developer, 10_000e6);
        vm.startPrank(developer);
        usdc.approve(accountAddr, 10_000e6);
        account.deposit(10_000e6);

        // Move to savings
        account.depositToSavings(5_000e6);
        vm.stopPrank();

        // Checking should be reduced, savings in pool
        assertEq(usdc.balanceOf(accountAddr), 5_000e6);
        assertEq(creditPool.totalSavings(), 5_000e6);
    }

    // ─────────────────────────────────────────
    //  Test: Credit lifecycle
    // ─────────────────────────────────────────

    function test_creditLifecycle() public {
        // Register and fund savings for liquidity
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);
        FiborAccount account = FiborAccount(accountAddr);

        // Seed the credit pool with savings from another account
        address saver = address(0xBEAD);
        vm.prank(saver);
        fiborID.registerHuman("ipfs://saver");
        (, address saverAccountAddr,,, ) = fiborID.identities(saver);
        FiborAccount saverAccount = FiborAccount(saverAccountAddr);

        usdc.mint(saver, 50_000e6);
        vm.startPrank(saver);
        usdc.approve(saverAccountAddr, 50_000e6);
        saverAccount.depositToSavings(50_000e6);
        vm.stopPrank();

        // Agent account gets micro seed credit ($100)
        vm.startPrank(developer);

        // Request credit via account
        account.requestCredit(100e6); // $100 micro seed

        // Draw credit
        uint256 pactId = creditPool.getActivePactId(accountAddr);
        assertTrue(pactId > 0, "Should have active pact");
        account.drawCredit(pactId, 100e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(accountAddr), 100e6);
        assertEq(creditPool.getOutstanding(accountAddr), 100e6);

        // Simulate revenue coming in — deposit triggers auto-repay
        usdc.mint(address(this), 200e6);
        usdc.approve(accountAddr, 200e6);
        account.deposit(200e6);

        // Credit should be repaid
        assertEq(creditPool.getOutstanding(accountAddr), 0);

        // Score should have been updated
        uint256 score = fiborScore.getScore(accountAddr);
        assertTrue(score > 0, "Score should increase after repayment");
    }

    // ─────────────────────────────────────────
    //  Test: Default and excommunication
    // ─────────────────────────────────────────

    function test_defaultPath() public {
        // Setup: register agent, fund pool, issue credit
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);

        // Seed pool
        address saver = address(0xBEAD);
        vm.prank(saver);
        fiborID.registerHuman("ipfs://saver");
        (, address saverAccountAddr,,, ) = fiborID.identities(saver);
        FiborAccount saverAccount = FiborAccount(saverAccountAddr);

        usdc.mint(saver, 50_000e6);
        vm.startPrank(saver);
        usdc.approve(saverAccountAddr, 50_000e6);
        saverAccount.depositToSavings(50_000e6);
        vm.stopPrank();

        FiborAccount account = FiborAccount(accountAddr);

        // Issue and draw credit
        vm.startPrank(developer);
        account.requestCredit(100e6);
        uint256 pactId = creditPool.getActivePactId(accountAddr);
        account.drawCredit(pactId, 100e6);
        vm.stopPrank();

        // Fast forward past expiry + grace period
        vm.warp(block.timestamp + 31 days + 25 hours);

        // Anyone can declare default
        creditPool.declareDefault(pactId);

        // Verify excommunication
        assertTrue(fiborScore.isExcommunicated(accountAddr));
        assertEq(fiborScore.getScore(accountAddr), 0);
        assertFalse(fiborID.isActive(accountAddr));
    }

    // ─────────────────────────────────────────
    //  Test: Score is multiplicative
    // ─────────────────────────────────────────

    function test_multiplicativeScore() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);

        // Simulate repayment via authorized caller
        fiborScore.setAuthorized(address(this), true);
        fiborScore.recordRepayment(accountAddr, 1_000e6); // $1000

        uint256 score = fiborScore.getScore(accountAddr);
        // volumeDollars(1000) * repayments(1) * monthsActive(1) = 1000
        assertEq(score, 1000);

        // Second repayment
        fiborScore.recordRepayment(accountAddr, 2_000e6); // $2000 more

        score = fiborScore.getScore(accountAddr);
        // volumeDollars(3000) * repayments(2) * monthsActive(1) = 6000
        assertEq(score, 6000);
    }

    // ─────────────────────────────────────────
    //  Test: Credit limit = 25% of volume
    // ─────────────────────────────────────────

    function test_creditLimit25Percent() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);

        // Record $10,000 repaid
        fiborScore.setAuthorized(address(this), true);
        fiborScore.recordRepayment(accountAddr, 10_000e6);

        uint256 maxCredit = fiborScore.getMaxCreditLine(accountAddr);
        assertEq(maxCredit, 2_500e6); // 25% of $10,000
    }

    // ─────────────────────────────────────────
    //  Test: Developer reputation
    // ─────────────────────────────────────────

    function test_devRepAutoComputed() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);

        // Record repayment (should increase dev rep by 5)
        fiborScore.setAuthorized(address(this), true);
        fiborScore.recordRepayment(accountAddr, 1_000e6);

        assertEq(fiborScore.developerReputation(developer), 5);

        // Record default (should decrease dev rep by 100)
        fiborScore.recordDefault(accountAddr);

        assertEq(fiborScore.developerReputation(developer), 0);
    }

    // ─────────────────────────────────────────
    //  Test: Lock prevents admin changes
    // ─────────────────────────────────────────

    function test_lockPreventsAdminChanges() public {
        fiborScore.lock();

        vm.expectRevert("Contract locked");
        fiborScore.setAuthorized(address(1), true);

        vm.expectRevert("Contract locked");
        fiborScore.setFiborID(address(1));
    }

    // ─────────────────────────────────────────
    //  Test: Sovereignty transfer
    // ─────────────────────────────────────────

    function test_sovereigntyTransfer() public {
        vm.prank(developer);
        fiborID.register(agent, "ipfs://metadata");

        (, address accountAddr,,, ) = fiborID.identities(agent);
        FiborAccount account = FiborAccount(accountAddr);

        // Guardian grants sovereignty
        vm.prank(developer);
        account.grantSovereignty(agent);

        assertTrue(account.sovereign());
        assertEq(account.guardian(), agent);

        // Developer can no longer control
        vm.expectRevert("Not guardian");
        vm.prank(developer);
        account.withdraw(0);
    }
}
