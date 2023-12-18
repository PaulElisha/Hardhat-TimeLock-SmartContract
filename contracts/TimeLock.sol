// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract TimeLock {

    error NotOwner();
    error AlreadyQueued(bytes32 txId);
    error TimestampNotInRange(uint blocktimestamp, uint timestamp);
    error NotQueued(bytes32 txId);
    error TimeStampReferenceError(uint blocktimestamp, uint _timestamp);
    error TimestampExpired(uint blocktimestamp, uint expiresAt);
    error TxFailed();

    event Queue (
        bytes32 indexed txId,
        address indexed target, 
        uint value,  
        string func, 
        bytes data,
        uint timestamp
    );

    event Execute (
        bytes32 indexed txId,
        address indexed target, 
        uint value,  
        string func, 
        bytes data,
        uint timestamp 
    );

    event Cancel(
        bytes32 indexed txId
    );

    uint private constant MIN_DELAY = 10;
    uint private constant MAX_DELAY = 1000;
    uint private constant GRACE_PERIOD = 1000;

    address owner; 
    mapping (bytes32 => bool) private queued;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if(owner != msg.sender) revert NotOwner();
        _;
    }

    function getTxId(
        address _target, 
        uint _value,  
        string calldata _func, 
        bytes calldata _data,
        uint _timestamp
    ) public pure returns(bytes32 txId) {
        return keccak256(abi.encode(_target, _value, _func, _data, _timestamp));
    }

    function queue (
        address _target, 
        uint _value,  
        string calldata _func, 
        bytes calldata _data,
        uint _timestamp
        ) external {
        bytes32 txId = getTxId(_target, _value, _func, _data, _timestamp);
        if(queued[txId]) revert AlreadyQueued(txId);
        if(
            _timestamp < block.timestamp + MIN_DELAY ||
            _timestamp > block.timestamp + MAX_DELAY
        ) revert TimestampNotInRange(block.timestamp, _timestamp);

        queued[txId] = true;

        emit Queue (
            txId,
            _target,
            _value,
            _func,
            _data,
            _timestamp
        );
    }

    function execute(
        address _target, 
        uint _value,  
        string calldata _func, 
        bytes calldata _data,
        uint _timestamp
    ) external payable onlyOwner returns(bytes memory) {
        bytes32 txId = getTxId(_target, _value, _func, _data, _timestamp);
        if(!queued[txId]) revert NotQueued(txId);
        if(block.timestamp < _timestamp) revert TimeStampReferenceError(block.timestamp, _timestamp);
        // Check rhe expiry of the timestamp by giving grace period

        if(block.timestamp > _timestamp + GRACE_PERIOD) 
        revert TimestampExpired(block.timestamp, _timestamp + GRACE_PERIOD);
        
        queued[txId] = false;

        bytes memory data;
        if(bytes(_func).length > 0) {
            data = abi.encodePacked(bytes4(keccak256(bytes(_func))), _data);
        } else {
            data = _data;
        }

        (bool success, bytes memory response) = _target.call{value: _value}(data);

        if(!success) revert TxFailed();

        emit Execute (txId, _target, _value, _func, _data, _timestamp);
        return response;
    }

    function cancel(bytes32 _txId) external onlyOwner {
        if(!queued[_txId]) revert NotQueued(_txId);

        queued[_txId] = false;

        emit Cancel (
            _txId
        );
    }

    receive() external payable {}
    fallback() external payable {}
}

contract TestTimeLock {
    address public timeLock;

    constructor(address _timeLock) {
        timeLock = _timeLock;
    }

    function test() external view {
        require(msg.sender == timeLock, "Not timeLock");
    }

    function getTimeStamp() external view returns(uint) {
        return block.timestamp + 100;
    }
}