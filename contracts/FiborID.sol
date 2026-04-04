// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IFiborScoreInit {
    function initializeScore(address agent, address developer) external;
}

interface IFiborAccountFactory {
    function createAccount(address guardian, bool isHumanAccount, bytes32 salt) external returns (address);
}

/**
 * @title FiborID
 * @notice Identity registry for agents on the FIBOR network.
 *
 *   Registration is developer-initiated: the developer calls register()
 *   directly, paying gas and signing the transaction. No admin approval
 *   required — this is permissionless identity creation.
 *
 *   Every agent receives a persistent, portable financial identity:
 *   - Who built it (developer = msg.sender)
 *   - What it does (metadata URI)
 *   - When it was created
 *   - Current status (active / suspended / excommunicated)
 *
 *   Once excommunicated, an ID cannot be reactivated. Ever.
 *
 *   On registration, FiborScore is automatically initialized for the agent.
 */
contract FiborID is Ownable {

    enum Status { Active, Suspended, Excommunicated }

    struct Identity {
        address developer;
        address account;        // FiborAccount address (the agent's bank account)
        string metadataURI;     // off-chain JSON: name, purpose, version, etc.
        uint256 createdAt;
        Status status;
    }

    IFiborScoreInit public fiborScore;
    IFiborAccountFactory public accountFactory;
    address public creditPool;

    mapping(address => Identity) public identities;
    mapping(address => address[]) public developerAgents;

    uint256 public totalRegistered;

    event AgentRegistered(address indexed agent, address indexed developer);
    event AgentSuspended(address indexed agent);
    event AgentExcommunicated(address indexed agent);
    event MetadataUpdated(address indexed agent, string uri);

    constructor(address _fiborScore) Ownable(msg.sender) {
        fiborScore = IFiborScoreInit(_fiborScore);
    }

    // ──────────────────────────────────────────────
    //  Registration (permissionless, developer-initiated)
    // ──────────────────────────────────────────────

    /**
     * @notice Register a new agent. The caller (msg.sender) becomes the
     *         developer on record. Automatically initializes a FIBOR Score.
     * @param _agent       Address of the agent to register
     * @param _metadataURI Off-chain JSON with agent name, purpose, version
     */
    function register(
        address _agent,
        string calldata _metadataURI
    ) external {
        require(_agent != address(0), "Invalid agent address");
        require(identities[_agent].createdAt == 0, "Already registered");

        // Deploy a FiborAccount for this agent
        bytes32 salt = bytes32(uint256(uint160(_agent)));
        address account = accountFactory.createAccount(msg.sender, false, salt);

        identities[_agent] = Identity({
            developer: msg.sender,
            account: account,
            metadataURI: _metadataURI,
            createdAt: block.timestamp,
            status: Status.Active
        });

        // Also register the account address so CreditPool can look it up
        identities[account] = Identity({
            developer: msg.sender,
            account: account,
            metadataURI: _metadataURI,
            createdAt: block.timestamp,
            status: Status.Active
        });

        developerAgents[msg.sender].push(_agent);
        totalRegistered++;

        // Auto-initialize credit score for the account address
        fiborScore.initializeScore(account, msg.sender);

        emit AgentRegistered(_agent, msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Human registration (savings-only accounts)
    // ──────────────────────────────────────────────

    /**
     * @notice Register a human savings account. No credit, no scoring.
     *         Humans can deposit into savings to earn yield from agent
     *         transaction fees.
     */
    function registerHuman(
        string calldata _metadataURI
    ) external {
        address humanAddr = msg.sender;
        require(identities[humanAddr].createdAt == 0, "Already registered");

        bytes32 salt = bytes32(uint256(uint160(humanAddr)));
        address account = accountFactory.createAccount(msg.sender, true, salt);

        identities[humanAddr] = Identity({
            developer: msg.sender,
            account: account,
            metadataURI: _metadataURI,
            createdAt: block.timestamp,
            status: Status.Active
        });

        totalRegistered++;
        emit AgentRegistered(humanAddr, msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Status management
    // ──────────────────────────────────────────────

    /**
     * @notice Suspend an agent. Can be called by the developer or protocol.
     */
    function suspend(address _agent) external {
        Identity storage id = identities[_agent];
        require(id.createdAt != 0, "Not registered");
        require(id.status == Status.Active, "Not active");
        require(msg.sender == id.developer || msg.sender == owner(), "Not authorized");
        id.status = Status.Suspended;
        emit AgentSuspended(_agent);
    }

    /**
     * @notice Excommunicate an agent. Permanent. Called by authorized
     *         contracts (CreditPool on default) or the protocol owner.
     */
    function excommunicate(address _agent) external {
        Identity storage id = identities[_agent];
        require(id.createdAt != 0, "Not registered");
        require(id.status != Status.Excommunicated, "Already excommunicated");
        // CreditPool, owner, or developer can excommunicate
        require(
            msg.sender == creditPool || msg.sender == owner() || msg.sender == id.developer,
            "Not authorized"
        );
        id.status = Status.Excommunicated;
        emit AgentExcommunicated(_agent);
    }

    /**
     * @notice Reactivate a suspended agent. Developer only.
     */
    function reactivate(address _agent) external {
        Identity storage id = identities[_agent];
        require(id.createdAt != 0, "Not registered");
        require(id.status == Status.Suspended, "Not suspended");
        require(msg.sender == id.developer, "Not developer");
        id.status = Status.Active;
    }

    function updateMetadata(address _agent, string calldata _uri) external {
        Identity storage id = identities[_agent];
        require(id.createdAt != 0, "Not registered");
        require(msg.sender == id.developer || msg.sender == owner(), "Not authorized");
        id.metadataURI = _uri;
        emit MetadataUpdated(_agent, _uri);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    function isActive(address _agent) external view returns (bool) {
        return identities[_agent].status == Status.Active;
    }

    function getDeveloperAgents(address _developer)
        external
        view
        returns (address[] memory)
    {
        return developerAgents[_developer];
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /// @notice One-way lock. Once locked, no admin setters can be called.
    bool public locked;

    function setFiborScore(address _fiborScore) external onlyOwner {
        require(!locked, "Contract locked");
        fiborScore = IFiborScoreInit(_fiborScore);
    }

    function setAccountFactory(address _factory) external onlyOwner {
        require(!locked, "Contract locked");
        accountFactory = IFiborAccountFactory(_factory);
    }

    function setCreditPool(address _creditPool) external onlyOwner {
        require(!locked, "Contract locked");
        creditPool = _creditPool;
    }

    /// @notice Permanently lock all admin setters. One-way gate.
    function lock() external onlyOwner {
        require(!locked, "Already locked");
        locked = true;
    }
}
