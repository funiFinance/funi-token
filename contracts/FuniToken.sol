// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*
  ______ _    _ _   _ _____ 
 |  ____| |  | | \ | |_   _|
 | |__  | |  | |  \| | | |  
 |  __| | |  | | . ` | | |  
 | |    | |__| | |\  |_| |_ 
 |_|     \____/|_| \_|_____|
                            
*/

import "./BEP20.sol";
import './math/SafeMath.sol';

// FuniToken with Governance.
contract FuniToken is BEP20('Funi Token', 'FUNI') {
    
    uint public maxSupply = 100_000_000 * 1e18; // scaled by 1e18. That means 100,000,000 FUNI
    
    uint public startBlock;
    
    uint public blockPerPeriod = 5256000; // About 3 seconds for a block on Binance Smart Chain. A period is about 6 months.
    
    uint public keepPercent = 80; // The amount of tokens distributed in the next period is 80% of the previous period
    
    uint public initialRewardPerBlock = 4052511416000000000; // scaled by 1e18. That means about 4.052511416 FUNI per block in the first period
    
    uint public maximumPeriodIndex = 9; // Only distribute FUNI tokens in 10 periods

    address public masterChef;
    address public incentive;
    address public guardian; // first token holder when token is initialized
    
    uint public incentiveWeight;
    uint public masterChefWeight;
    
    event MintForGuardian(address indexed from, address indexed to, uint256 value);
    
    /**
     * @dev Throws if called by any account other than the masterChef or incentive.
     */
    modifier onlyWhitelist() {
        require((masterChef == msg.sender) || (incentive == msg.sender), 'FUNI: caller is neither the masterChef nor incentive');
        _;
    }
    
    /**
     * @param _startBlock the block number of starting to calculate the reward
     * @param _guardian who holds the first minted tokens when initialized
     * @param _amount the minted token amount is sent to keeper
     * @param _incentiveWeight the percent of incentive distribution
     */
    constructor(uint _startBlock, address _guardian, uint _amount, uint _incentiveWeight) public {
        startBlock = _startBlock < block.number ? block.number : _startBlock;
        guardian = _guardian;
        incentiveWeight = _incentiveWeight;
        masterChefWeight = 100 - _incentiveWeight;
        _mintForGuardian(_amount);
    }
    
    function getKeepPercent() public view returns(uint){
        return keepPercent;
    }

    function getInitialRewardPerBlock() public view returns(uint){
        return initialRewardPerBlock;
    }

    function getMaximumPeriodIndex() public view returns(uint){
        return maximumPeriodIndex;
    }

    function getBlockPerPeriod() public view returns(uint){
        return blockPerPeriod;
    }
    
    function getMasterChefWeight() external view returns(uint) {
        return masterChefWeight;
    }

    function getIncentiveWeight() external view returns(uint) {
        return incentiveWeight;
    }

    function setMasterChef(address _masterchef) public onlyOwner{
        require(_masterchef != address(0));
        masterChef = _masterchef;
    }

    function setIncentive(address _incentive) public onlyOwner{
        require(_incentive != address(0));
        incentive = _incentive;
    }
    
    // @dev Creates `_amount` token to `_to`. Must only be called by the Whitelist (MasterChef or Incentive).
    function mint(address _to, uint256 _amount) public onlyWhitelist {
        uint mintAmount = _computedMint(_amount);
        if(mintAmount > 0) {
          _mint(_to, mintAmount);    
          _moveDelegates(address(0), _delegates[_to], mintAmount);
        }
    }

    function _mintForGuardian(uint256 _amount) private {
        require(guardian != address(0), 'FUNI::_mintForGuardian: guardian to the zero address');
        uint mintAmount = _computedMint(_amount);
        _mint(guardian, mintAmount);
        emit MintForGuardian(address(0), guardian, mintAmount);
        _moveDelegates(address(0), _delegates[guardian], mintAmount);
    }
    
    function _computedMint(uint256 _amount) private view returns (uint256) {
        return _amount.add(totalSupply()) > maxSupply ? maxSupply.sub(totalSupply()) : _amount;
    }
    
    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    // @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    // @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    // @dev A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    // @dev The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    // @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    // @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // @dev A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    // @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    // @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
    external
    view
    returns (address)
    {
        return _delegates[delegator];
    }

    /**
    * @dev Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "FUNI::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "FUNI::delegateBySig: invalid nonce");
        require(now <= expiry, "FUNI::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
    external
    view
    returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @dev Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
    external
    view
    returns (uint256)
    {
        require(blockNumber < block.number, "FUNI::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
    internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying FUNIs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
    internal
    {
        uint32 blockNumber = safe32(block.number, "FUNI::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function setInitialRewardPerBlock(uint _initialRewardPerBlock) public onlyOwner {
        initialRewardPerBlock = _initialRewardPerBlock;
    }

    function setKeepPercent(uint _keepPercent) public onlyOwner {
        require(_keepPercent > 0 , "FUNI::setKeepPercent: _keepPercent must be greater 0");
        require(_keepPercent <= 100 , "FUNI::setKeepPercent: _keepPercent must be less or equal 100");
        keepPercent = _keepPercent;
    }

    function setBlockPerPeriod(uint _blockPerPeriod) public onlyOwner {
        require(blockPerPeriod > 0 , "FUNI::setBlockPerPeriod: _blockPerPeriod must be greater 0");
        blockPerPeriod = _blockPerPeriod;
    }
    
}