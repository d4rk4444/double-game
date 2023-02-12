// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DoubleGame is VRFConsumerBaseV2, Ownable {
    VRFCoordinatorV2Interface COORDINATOR;
    address vrfCoordinator = 0xAE975071Be8F8eE67addBC1A82488F1C24858067;
    bytes32 keyHash = 0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd;
    uint32 callbackGasLimit = 200000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;
    uint64 subscriptionId = 616;

    constructor() VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    }

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
        uint32 numberGame;
    }

    struct GameStatus {
        address payable[2] players;
        uint256 amountBet;
        bool isLive;
        uint256 requestId;
    }

    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => GameStatus) public s_games; /* numberGame --> gameStatus */

    uint32 public gameNumber = 1;
    uint public minAmountBet = 1 ether;
    uint32 public feeGame = 2;
    uint private amountFee;

    event logGame(uint256 numberGame, uint256 requestId);

    function changeKeyHash(bytes32 _keyHash) external onlyOwner {
        keyHash = _keyHash;
    }

    function changeCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
        callbackGasLimit = _callbackGasLimit;
    }

    function changeSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    function getLiveGames() public view returns (uint256[] memory) {
        uint liveCount = 0;
        for (uint i = 1; i < gameNumber; i++) {
            if (s_games[i].isLive == true) {
                liveCount++;
            }
        }
        
        uint256[] memory liveGames = new uint256[](liveCount);
        uint liveIndex = 0;
        for (uint i = 0; i < gameNumber; i++) {
            if (s_games[i].isLive == true) {
                liveGames[liveIndex] = i;
                liveIndex++;
            }
        }
        
        return liveGames;
    }

    function createDouble(uint256 amountBet) external payable {
        require(msg.value >= minAmountBet, "Amount bet < Mininal Bet");
        require(msg.value == amountBet, "Value != amountBet");

        s_games[gameNumber] = GameStatus({
            players: [payable(msg.sender), payable(0)],
            amountBet: msg.value,
            isLive: true,
            requestId: 0
        });

        gameNumber++;
    }

    function loginDouble(uint32 numberGame) external payable {
        require(s_games[numberGame].isLive, "Game don't live");
        require(msg.value == s_games[numberGame].amountBet, "Amount != amountGame");
        require(msg.sender != s_games[numberGame].players[0], "It's your game");
        s_games[numberGame].players[1] = payable(msg.sender);
        s_games[numberGame].isLive = false;

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            numberGame: numberGame
        });

        emit logGame(numberGame, requestId);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        s_games[s_requests[_requestId].numberGame].requestId = _requestId;

        uint fee = s_games[s_requests[_requestId].numberGame].amountBet * 2 / 100 * feeGame;
        s_games[s_requests[_requestId].numberGame].players[_randomWords[0] % 2].transfer(s_games[s_requests[_requestId].numberGame].amountBet * 2 - fee);
        amountFee += fee;
    }

    function getRequestStatus(uint256 _requestId) public view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function getGameStatus(uint256 _gameNumber) public view returns (address payable[2] memory players, uint256 amountBet, bool isLive, uint256 requestId) {
        require(_gameNumber < gameNumber, "number game not found");
        GameStatus memory gameStatus = s_games[_gameNumber];
        return (gameStatus.players, gameStatus.amountBet, gameStatus.isLive, gameStatus.requestId);
    }

    function getWinnerNumber(uint256 _gameNumber) public view returns (uint256 winnerNumber) {
        require(_gameNumber < gameNumber, "number game not found");
        require(!s_games[_gameNumber].isLive, "game is not end");
        GameStatus memory gameStatus = s_games[_gameNumber];
        winnerNumber = s_requests[gameStatus.requestId].randomWords[0];
        return (winnerNumber);
    }

    function withdraw() external onlyOwner {
        address owner = owner();
        payable(owner).transfer(amountFee);
    }
}