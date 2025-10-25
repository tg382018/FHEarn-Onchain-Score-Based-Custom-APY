// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, euint64, ebool, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title FHEarnStake
 * @dev Confidential staking contract with score-based APY
 *      Uses FHEVM for encrypted stake amounts and reward calculations
 */
contract FHEarnStake is SepoliaConfig {
    
    // Events
    event StakeDeposited(address indexed user, uint256 amount, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 rewardAmount);
    event FullWithdrawal(address indexed user, uint256 totalAmount);
    event DecryptionRequested(address indexed user, uint256 requestID, string operation);
    
    // Debug events
    event DebugStep1(string message);
    event DebugStep2(string message);
    event DebugStep3(string message);
    event DebugStep4(string message);
    event DebugStep5(string message);
    
    // Structs
    struct StakeInfo {
        euint64 amount;           // Encrypted stake amount
        euint64 timestamp;        // Encrypted stake timestamp
        euint64 lastClaimTime;    // Encrypted last claim timestamp
        euint64 apyRate;          // Encrypted APY rate (based on score)
        bool isActive;            // Clear boolean for active status
    }
    
    struct PendingOperation {
        address user;
        string operation; // "stake", "claim", "withdraw"
        uint256 timestamp;
        bool isPending;
    }
    
    struct PendingDecryptionStruct {
        uint256 currentRequestID;
        bool isPendingDecryption;
        uint256 decryptionTimestamp;
    }
    
    // State variables
    mapping(address => StakeInfo) private stakes;
    mapping(uint256 => PendingOperation) private pendingOperations;
    uint256 private requestCounter;
    PendingDecryptionStruct private pendingDecryption;
    
    // Constants
    uint256 private constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    uint256 private constant MAX_DECRYPTION_TIME = 5 minutes;
    
    // Modifiers
    modifier onlyActiveStake(address user) {
        require(stakes[user].isActive, "No active stake");
        _;
    }
    
    modifier decryptionAvailable() {
        // Here we make sure there are no pending decryption.
        // In some cases the decryption request is sent but is never fulfilled.
        // In such cases we make sure the last decryption request was more than 5 minutes ago, to not block indefinitly the pair.
        if (
            pendingDecryption.isPendingDecryption &&
            block.timestamp < pendingDecryption.decryptionTimestamp + MAX_DECRYPTION_TIME
        ) {
            revert("PendingDecryption");
        }
        _;
    }
    
    /**
     * @dev Stake ETH with confidential amount and APY
     * @param encryptedAmount Encrypted stake amount
     * @param encryptedAPY Encrypted APY rate based on user's onchain score
     * @param inputProof Proof for encrypted inputs
     */
    function stake(
        externalEuint64 encryptedAmount,
        externalEuint64 encryptedAPY,
        uint256 deadline,
        bytes calldata inputProof
    ) external payable {
        emit DebugStep1("Stake function called");
        
        require(msg.value > 0, "Must send ETH");
        emit DebugStep2("ETH requirement passed");
        
        require(block.timestamp < deadline, "Expired");
        emit DebugStep3("Deadline requirement passed");
        
        // For ETH-based staking, we don't need FHE.fromExternal
        // Just use the ETH amount directly
        euint64 amount = FHE.asEuint64(uint64(msg.value));
        emit DebugStep4("ETH amount encrypted");
        
        euint64 apyRate = FHE.asEuint64(uint64(20)); // Fixed APY for now
        emit DebugStep5("APY rate set");
        
        euint64 currentTime = FHE.asEuint64(uint64(block.timestamp));
        
        // Store stake information
        stakes[msg.sender] = StakeInfo({
            amount: amount,
            timestamp: currentTime,
            lastClaimTime: currentTime,
            apyRate: apyRate,
            isActive: true
        });
        
        emit StakeDeposited(msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Calculate encrypted reward amount
     * @param user User address
     * @return Encrypted reward amount
     */
    function calculateEncryptedReward(address user) 
        external 
        onlyActiveStake(user) 
        returns (euint64) 
    {
        StakeInfo memory stakeInfo = stakes[user];
        
        // Calculate time elapsed since last claim
        euint64 currentTime = FHE.asEuint64(uint64(block.timestamp));
        euint64 timeElapsed = FHE.sub(currentTime, stakeInfo.lastClaimTime);
        
        // Convert time to years (encrypted division)
        euint64 timeInYears = FHE.div(timeElapsed, uint64(SECONDS_PER_YEAR));
        
        // Calculate APY as decimal (encrypted division)
        euint64 apyDecimal = FHE.div(stakeInfo.apyRate, uint64(100));
        
        // Calculate reward: amount * timeInYears * apyDecimal
        euint64 reward = FHE.mul(
            FHE.mul(stakeInfo.amount, timeInYears),
            apyDecimal
        );
        
        return reward;
    }
    
    /**
     * @dev Claim rewards (encrypted operation with decryption)
     */
    function claimReward() external onlyActiveStake(msg.sender) decryptionAvailable {
        // Calculate encrypted reward
        euint64 encryptedReward = this.calculateEncryptedReward(msg.sender);
        
        // Request decryption for reward amount
        uint256 requestID = _requestDecryption(encryptedReward, "claim");
        
        // Store pending operation
        pendingOperations[requestID] = PendingOperation({
            user: msg.sender,
            operation: "claim",
            timestamp: block.timestamp,
            isPending: true
        });
        
        emit DecryptionRequested(msg.sender, requestID, "claim");
    }
    
    /**
     * @dev Withdraw all (stake + rewards)
     */
    function withdrawAll() external onlyActiveStake(msg.sender) decryptionAvailable {
        // Calculate encrypted total (stake + rewards)
        euint64 encryptedReward = this.calculateEncryptedReward(msg.sender);
        euint64 encryptedTotal = FHE.add(stakes[msg.sender].amount, encryptedReward);
        
        // Request decryption for total amount
        uint256 requestID = _requestDecryption(encryptedTotal, "withdraw");
        
        // Store pending operation
        pendingOperations[requestID] = PendingOperation({
            user: msg.sender,
            operation: "withdraw",
            timestamp: block.timestamp,
            isPending: true
        });
        
        emit DecryptionRequested(msg.sender, requestID, "withdraw");
    }
    
    /**
     * @dev Callback for decrypted amounts
     * @param requestID Request ID from decryption
     * @param decryptedAmount Decrypted amount
     * @param signatures Decryption signatures
     */
    function decryptionCallback(
        uint256 requestID,
        uint64 decryptedAmount,
        bytes[] memory signatures
    ) external {
        require(pendingOperations[requestID].isPending, "No pending operation");
        require(block.timestamp <= pendingOperations[requestID].timestamp + MAX_DECRYPTION_TIME, "Decryption timeout");
        
        // FHE.checkSignatures(requestID, signatures); // Commented for now
        
        address user = pendingOperations[requestID].user;
        string memory operation = pendingOperations[requestID].operation;
        
        if (keccak256(bytes(operation)) == keccak256(bytes("claim"))) {
            _processClaim(user, decryptedAmount);
        } else if (keccak256(bytes(operation)) == keccak256(bytes("withdraw"))) {
            _processWithdrawal(user, decryptedAmount);
        }
        
        // Clear pending operation
        delete pendingOperations[requestID];
    }
    
    /**
     * @dev Process reward claim
     */
    function _processClaim(address user, uint64 rewardAmount) internal {
        // Update last claim time
        stakes[user].lastClaimTime = FHE.asEuint64(uint64(block.timestamp));
        
        // Transfer reward
        payable(user).transfer(rewardAmount);
        
        emit RewardClaimed(user, rewardAmount);
    }
    
    /**
     * @dev Process full withdrawal
     */
    function _processWithdrawal(address user, uint64 totalAmount) internal {
        // Deactivate stake
        stakes[user].isActive = false;
        
        // Transfer total amount
        payable(user).transfer(totalAmount);
        
        emit FullWithdrawal(user, totalAmount);
    }
    
    /**
     * @dev Request decryption for encrypted amount
     */
    function _requestDecryption(euint64 encryptedAmount, string memory operation) 
        internal 
        returns (uint256) 
    {
        uint256 requestID = requestCounter++;
        
        // Allow decryption for this specific amount
        FHE.allow(encryptedAmount, address(this));
        
        return requestID;
    }
    
    /**
     * @dev Get stake information (encrypted)
     * @param user User address
     * @return Encrypted stake amount
     * @return Encrypted timestamp
     * @return Encrypted APY rate
     * @return Is active (clear boolean)
     */
    function getStakeInfo(address user) 
        external 
        view 
        returns (euint64, euint64, euint64, bool) 
    {
        StakeInfo memory stakeInfo = stakes[user];
        return (
            stakeInfo.amount,
            stakeInfo.timestamp,
            stakeInfo.apyRate,
            stakeInfo.isActive
        );
    }
    
    /**
     * @dev Get current reward estimate (for UI display)
     * Note: This is approximate due to encrypted nature
     */
    function getRewardEstimate(address user) external view returns (uint256) {
        if (!stakes[user].isActive) return 0;
        
        // This would need to be calculated off-chain or through a different mechanism
        // For now, return 0 - actual calculation happens in calculateEncryptedReward
        return 0;
    }
    
    /**
     * @dev Emergency refund for failed operations
     */
    function requestRefund(uint256 requestID) external {
        require(pendingOperations[requestID].isPending, "No pending operation");
        require(block.timestamp > pendingOperations[requestID].timestamp + MAX_DECRYPTION_TIME, "Operation not timed out");
        require(pendingOperations[requestID].user == msg.sender, "Not your operation");
        
        // Refund logic would go here
        // For now, just clear the pending operation
        delete pendingOperations[requestID];
    }
}
