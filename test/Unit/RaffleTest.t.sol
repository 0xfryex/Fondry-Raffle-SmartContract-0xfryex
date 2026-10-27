//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../../script/Interactions.s.sol";
import {CodeConstant} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstant {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("Player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event PickedWinner(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subId = config.subId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializedIsOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //arrange
    //act
    //assert

    //////////////////////////////////////// ENTER RAFFLE ////////////////////////////////////////
    function testErrorWhenEthIsNotEnough() public {
        //arrange
        vm.prank(PLAYER);
        //act / assert
        vm.expectRevert(Raffle.Raffle__SendMoreEthToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testPlayerRecordedWhenTheyEnter() public {
        //arrange
        vm.prank(PLAYER);
        //act
        raffle.enterRaffle{value: entranceFee}();
        //assert
        address Player_Recorded = raffle.getPlayer(0);
        assert(Player_Recorded == PLAYER);
    }

    function testEnterRaffleEventEmit() public {
        //arrange
        vm.prank(PLAYER);
        //act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        //assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayerEnterWhileCalculating() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //act / assert
        vm.expectRevert(Raffle.Raffle__RaffleIsNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////////////////////////// CHECK UPKEEP ////////////////////////////////////////
    function testCheckUpKeepRevertFalseWhenHasNoBalance() public {
        //arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepRevertFalseWhenRaffleIsCalculating() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNoPassed() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        //act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(upKeepNeeded);
    }

    //////////////////////////////////////// PERFORM UPKEEP ////////////////////////////////////////
    function testPerformUpkeepWhenParameterIsGood() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act / assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepReturnFalseWhenIfCheckUpkeepNotPass() public {
        //arrange
        uint256 currentBalance = 0;
        uint256 numPlayer = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayer = 1;

        // act / assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayer,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmittedEvent()
        public
        raffleEntered
    {
        //act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        //assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    //////////////////////////////////////// FULLFILLRANDOMWORDS    ////////////////////////////////////////
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFullFillRandomWordsCanBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        //arrange / act / assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPickAWinnerAndSendMoneyAndReset()
        public
        skipFork
        raffleEntered
    {
        //arrange
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1;
        address expectWinner = address(1);

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrances;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingWinnerBalance = expectWinner.balance;
        uint256 startingTimeStamp = raffle.getLastTimeStamp();

        //act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console2.logBytes32(entries[1].topics[1]);
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerBalance = recentWinner.balance;
        uint256 prize = entranceFee * (additionalEntrances + 1);

        assert(expectWinner == recentWinner);
        assert(uint256(raffleState) == 0);
        assert(endingTimeStamp > startingTimeStamp);
        assert(winnerBalance == startingWinnerBalance + prize);
    }
}
