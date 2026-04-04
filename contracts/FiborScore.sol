// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IFiborIDLookup {
    function identities(address agent)
        external
        view
        returns (address developer, address account, string memory metadataURI, uint256 createdAt, uint8 status);
}

/**
 * @title FiborScore
 * @notice Multiplicative credit scoring for agents on FIBOR.
 *
 *   Score = totalVolumeRepaid × totalRepayments × monthsActive
 *
 *   No cap. No decay. No normalization. Big numbers = big history.
 *   A score of 60,000,000 immediately communicates "serious agent."
 *   A score of 2,000 says "just got here."
 *
 *   Credit limits are tied to proven volume, not score thresholds:
 *   Max credit line = 25% of totalVolumeRepaid (in USDC).
 *   This makes fraud structurally unprofitable — you spend more
 *   building reputation than you can steal with it.
 *
 *   New agents bootstrap via developer reputation: devs with proven
 *   track records get a micro credit seed ($100-$500) for new agents.
 *
 *   Developer reputation auto-updates: +5 on agent repayment,
 *   -100 on agent default. No manual override.
 */
contract FiborScore is Ownable {

    struct ScoreData {
        uint256 totalVolumeRepaid;  // cumulative USDC repaid (6 decimals)
        uint256 totalRepayments;    // count of successful repayments
        uint256 registeredAt;       // timestamp of registration
        uint256 totalDefaulted;
        bool excommunicated;
    }

    mapping(address => ScoreData) public scores;

    /// @notice Developer reputation. Auto-computed from agent performance.
    mapping(address => uint256) public developerReputation;

    mapping(address => bool) public authorized;
    IFiborIDLookup public fiborID;
    bool public locked;

    /// @notice Credit limit as percentage of proven volume (in BPS).
    uint256 public constant CREDIT_LIMIT_BPS = 2500; // 25%
    uint256 public constant BPS = 10_000;

    /// @notice Micro credit seed for new agents based on developer rep.
    uint256 public constant MICRO_SEED_BASE = 100 * 1e6;  // $100 USDC
    uint256 public constant MICRO_SEED_MAX = 500 * 1e6;   // $500 USDC

    event ScoreUpdated(address indexed agent, uint256 newScore);
    event AgentDefaulted(address indexed agent);
    event DeveloperReputationUpdated(address indexed developer, uint256 newRep);
    event AuthorizedUpdated(address indexed addr, bool status);
    event Locked();

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Not authorized");
        _;
    }

    modifier whenNotLocked() {
        require(!locked, "Contract locked");
        _;
    }

    constructor() Ownable(msg.sender) {}

    // ──────────────────────────────────────────────
    //  Admin (one-time setup, locked after deployment)
    // ──────────────────────────────────────────────

    function setAuthorized(address _addr, bool _status) external onlyOwner whenNotLocked {
        authorized[_addr] = _status;
        emit AuthorizedUpdated(_addr, _status);
    }

    function setFiborID(address _fiborID) external onlyOwner whenNotLocked {
        fiborID = IFiborIDLookup(_fiborID);
    }

    function lock() external onlyOwner {
        require(!locked, "Already locked");
        locked = true;
        emit Locked();
    }

    // ──────────────────────────────────────────────
    //  Score initialization
    // ──────────────────────────────────────────────

    /**
     * @notice Initialize score for a new agent. Called by FiborID on registration.
     */
    function initializeScore(address _agent, address _developer) external onlyAuthorized {
        require(scores[_agent].registeredAt == 0, "Already initialized");

        scores[_agent] = ScoreData({
            totalVolumeRepaid: 0,
            totalRepayments: 0,
            registeredAt: block.timestamp,
            totalDefaulted: 0,
            excommunicated: false
        });

        emit ScoreUpdated(_agent, 0);
    }

    // ──────────────────────────────────────────────
    //  Score updates (authorized contracts only)
    // ──────────────────────────────────────────────

    /**
     * @notice Record a successful repayment. Updates score components.
     *         Called by CreditPool on full repayment.
     */
    function recordRepayment(address _agent, uint256 _amount) external onlyAuthorized {
        ScoreData storage data = scores[_agent];
        require(!data.excommunicated, "Excommunicated");

        data.totalRepayments++;
        data.totalVolumeRepaid += _amount;

        _updateDevRep(_agent, true);

        emit ScoreUpdated(_agent, getScore(_agent));
    }

    /**
     * @notice Record a default. Permanent excommunication.
     */
    function recordDefault(address _agent) external onlyAuthorized {
        ScoreData storage data = scores[_agent];
        data.totalDefaulted++;
        data.excommunicated = true;

        _updateDevRep(_agent, false);

        emit AgentDefaulted(_agent);
        emit ScoreUpdated(_agent, 0);
    }

    // ──────────────────────────────────────────────
    //  Views
    // ──────────────────────────────────────────────

    /**
     * @notice Composite score = totalVolumeRepaid × totalRepayments × monthsActive.
     *         Returns 0 if excommunicated. No cap, no normalization.
     *         USDC volume is in 6-decimal units, so divide by 1e6 for dollar value.
     */
    function getScore(address _agent) public view returns (uint256) {
        ScoreData storage data = scores[_agent];
        if (data.excommunicated) return 0;
        if (data.registeredAt == 0) return 0;

        uint256 monthsActive = ((block.timestamp - data.registeredAt) / 30 days) + 1;

        // Volume in whole dollars (divide out 6 decimals)
        uint256 volumeDollars = data.totalVolumeRepaid / 1e6;

        return volumeDollars * data.totalRepayments * monthsActive;
    }

    /**
     * @notice Maximum credit line for this agent.
     *         25% of totalVolumeRepaid, or micro seed for new agents.
     *         This ensures fraud is always unprofitable.
     */
    function getMaxCreditLine(address _agent) external view returns (uint256) {
        ScoreData storage data = scores[_agent];
        if (data.excommunicated) return 0;

        // If agent has repayment history, credit = 25% of proven volume
        if (data.totalVolumeRepaid > 0) {
            return (data.totalVolumeRepaid * CREDIT_LIMIT_BPS) / BPS;
        }

        // New agent: micro seed based on developer reputation
        if (address(fiborID) == address(0)) return MICRO_SEED_BASE;

        (address developer,,,, ) = fiborID.identities(_agent);
        uint256 devRep = developerReputation[developer];

        if (devRep >= 800) return MICRO_SEED_MAX;       // $500
        if (devRep >= 500) return 300 * 1e6;            // $300
        if (devRep >= 200) return 200 * 1e6;            // $200
        return MICRO_SEED_BASE;                          // $100
    }

    function getFullScore(address _agent) external view returns (ScoreData memory) {
        return scores[_agent];
    }

    function isExcommunicated(address _agent) external view returns (bool) {
        return scores[_agent].excommunicated;
    }

    // ──────────────────────────────────────────────
    //  Internals
    // ──────────────────────────────────────────────

    /**
     * @notice Auto-update developer reputation.
     *         +5 on repayment, -100 on default. No manual override.
     */
    function _updateDevRep(address _agent, bool _positive) internal {
        if (address(fiborID) == address(0)) return;

        (address developer,,,, ) = fiborID.identities(_agent);
        if (developer == address(0)) return;

        uint256 oldRep = developerReputation[developer];
        uint256 newRep;

        if (_positive) {
            newRep = oldRep + 5; // no cap on dev rep
        } else {
            newRep = oldRep >= 100 ? oldRep - 100 : 0;
        }

        developerReputation[developer] = newRep;
        emit DeveloperReputationUpdated(developer, newRep);
    }
}
