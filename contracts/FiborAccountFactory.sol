// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./FiborAccount.sol";

/**
 * @title FiborAccountFactory
 * @notice Deploys FiborAccount contracts for agents and humans.
 *
 *   Called by FiborID.register() and FiborID.registerHuman().
 *   Uses CREATE2 for deterministic addresses.
 */
contract FiborAccountFactory {

    address public immutable usdc;
    address public immutable creditPool;
    address public immutable paymentGateway;
    address public immutable revenueDistributor;

    event AccountCreated(address indexed account, address indexed guardian, bool isHuman);

    constructor(
        address _usdc,
        address _creditPool,
        address _paymentGateway,
        address _revenueDistributor
    ) {
        usdc = _usdc;
        creditPool = _creditPool;
        paymentGateway = _paymentGateway;
        revenueDistributor = _revenueDistributor;
    }

    /**
     * @notice Deploy a new FiborAccount.
     * @param _guardian       The human custodian
     * @param _isHumanAccount True for savings-only human accounts
     * @param _salt           Unique salt for CREATE2
     * @return account        The deployed FiborAccount address
     */
    function createAccount(
        address _guardian,
        bool _isHumanAccount,
        bytes32 _salt
    ) external returns (address account) {
        FiborAccount a = new FiborAccount{salt: _salt}(
            _guardian,
            _isHumanAccount,
            usdc,
            creditPool,
            paymentGateway,
            revenueDistributor
        );
        account = address(a);
        emit AccountCreated(account, _guardian, _isHumanAccount);
    }

    /**
     * @notice Predict the address of a FiborAccount before deployment.
     */
    function predictAddress(
        address _guardian,
        bool _isHumanAccount,
        bytes32 _salt
    ) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(
                    abi.encodePacked(
                        type(FiborAccount).creationCode,
                        abi.encode(
                            _guardian,
                            _isHumanAccount,
                            usdc,
                            creditPool,
                            paymentGateway,
                            revenueDistributor
                        )
                    )
                )
            )
        );
        return address(uint160(uint256(hash)));
    }
}
