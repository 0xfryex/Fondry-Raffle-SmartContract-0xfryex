// Layout of Contract:
// license
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";

/**
 * @title A Sample Contract
 * @author 0xfryex
 * @notice this contract is for creating a sample raffle
 * @dev implement chainlink 2,5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /** ERROR  */
    error Raffle__SendMoreEthToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleIsNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 currentPlayers,
        uint256 raffleState
    );

    /** Type Declaration */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variabel */
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private immutable i_callBackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    bytes32 private immutable i_gasLane;
    address payable[] private s_player;
    address payable s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEntered(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_gasLane = gasLane;
        i_subscriptionId = subId;
        i_callBackGasLimit = callBackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreEthToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleIsNotOpen();
        }

        s_player.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. There are players registered.
     * 5. Implicitly, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_player.length > 0;

        upkeepNeeded = timeHasPassed && raffleIsOpen && hasBalance && hasPlayer;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_player.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATION,
                callbackGasLimit: i_callBackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        //checks

        //effect
        uint256 indexOfWinner = randomWords[0] % s_player.length;
        address payable recentWinner = s_player[indexOfWinner];

        s_recentWinner = recentWinner;
        s_player = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        emit PickedWinner(recentWinner);

        //interaction
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_player[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
