// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/MockUSDC.sol";
import "../contracts/FIBORToken.sol";
import "../contracts/FiborScore.sol";
import "../contracts/FiborID.sol";
import "../contracts/RevenueDistributor.sol";
import "../contracts/CreditPool.sol";
import "../contracts/PaymentGateway.sol";
import "../contracts/FiborAccountFactory.sol";

contract DeployFibor is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPK);

        vm.startBroadcast(deployerPK);

        // ── Phase 1: Deploy ─────────────────────────
        MockUSDC usdc = new MockUSDC();
        FIBORToken fiborToken = new FIBORToken(deployer);
        FiborScore fiborScore = new FiborScore();
        FiborID fiborID = new FiborID(address(fiborScore));
        RevenueDistributor revenueDistributor = new RevenueDistributor(address(usdc), deployer);
        CreditPool creditPool = new CreditPool(address(usdc), address(fiborScore), address(fiborID));
        PaymentGateway paymentGateway = new PaymentGateway(address(usdc), address(revenueDistributor));
        FiborAccountFactory factory = new FiborAccountFactory(
            address(usdc),
            address(creditPool),
            address(paymentGateway),
            address(revenueDistributor)
        );

        // ── Phase 2: Wire ───────────────────────────
        fiborID.setAccountFactory(address(factory));
        fiborID.setCreditPool(address(creditPool));
        fiborScore.setAuthorized(address(fiborID), true);
        fiborScore.setAuthorized(address(creditPool), true);
        fiborScore.setFiborID(address(fiborID));
        revenueDistributor.setAuthorized(address(paymentGateway), true);

        // ── Phase 3: Seed testnet ───────────────────
        usdc.mint(deployer, 1_000_000e6); // $1M test USDC

        vm.stopBroadcast();

        // ── Log addresses ───────────────────────────
        console.log("=== FIBOR Deployment Addresses ===");
        console.log("MockUSDC:             ", address(usdc));
        console.log("FIBORToken:           ", address(fiborToken));
        console.log("FiborScore:           ", address(fiborScore));
        console.log("FiborID:              ", address(fiborID));
        console.log("RevenueDistributor:   ", address(revenueDistributor));
        console.log("CreditPool:           ", address(creditPool));
        console.log("PaymentGateway:       ", address(paymentGateway));
        console.log("FiborAccountFactory:  ", address(factory));
    }
}
