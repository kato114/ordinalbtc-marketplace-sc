// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable2Step.sol";
import "./Pausable.sol";

contract OrdinalBTCMarket is Ownable2Step, Pausable {
    enum OSTATE {
        NOT_STARTED,
        CREATED,
        ALLOWED,
        CANCELED,
        COMPLETED,
        OTHER
    }

    struct OfferInfo {
        address buyer;
        string inscriptionID;
        uint256 btcNFTId;
        string nft_owner;
        string nft_receiver;
        address token;
        uint256 amount;
        address seller;
        OSTATE state;
    }

    address public constant ETH = address(0xeee);
    // 10000: 100%, 100: 1%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 3000;
    uint256 public BUY_FEE = 100;
    uint256 public SELL_FEE = 100;

    mapping(address => bool) public acceptedTokenList;
    mapping(address => bool) public adminList;

    mapping(address => mapping(address => uint256)) public buyerHistory; // buyer -> token -> amount
    mapping(address => mapping(address => uint256)) public sellerHistory; // seller -> token -> amount

    mapping(uint256 => OfferInfo) public offerInfo; // offerNumber => offerInfo
    mapping(uint256 => OSTATE) public offerState; // btcNFTId => offerState

    uint256 public orderNumber = 0; // next order number, current total numbers of order

    event LogSetBuyFee(uint256 indexed BUY_FEE);
    event LogSetSellFee(uint256 indexed SELL_FEE);
    event LogUpdateAcceptedTokenList(address indexed token, bool indexed state);
    event LogUpdateAdminList(address indexed admin, bool indexed state);
    event LogWithdrawFee(
        address indexed to,
        IERC20 indexed token,
        uint256 amount,
        uint256 ethAmount
    );
    event LogBuyBTCNFT(
        address indexed buyer,
        string indexed inscriptionID,
        uint256 indexed btcNFTId,
        string nft_owner,
        string nft_receiver,
        address token,
        uint256 amount,
        address seller
    );
    event LogOfferCheck(uint256 indexed orderNumber, OSTATE indexed state);
    event LogWithdraw(address indexed seller, uint256 indexed orderNumber);

    constructor(
        address _USDT,
        address _oBTC,
        address _admin
    ) {
        acceptedTokenList[ETH] = true;
        acceptedTokenList[_USDT] = true;
        acceptedTokenList[_oBTC] = true;
        adminList[msg.sender] = true;
        adminList[_admin] = true;
    }

    modifier onlyAdmins() {
        require(adminList[msg.sender] == true, "NOT_ADMIN");
        _;
    }

    function updateAcceptedTokenList(address token, bool state)
        external
        onlyOwner
    {
        require(acceptedTokenList[token] != state, "SAME_STATE");
        acceptedTokenList[token] = state;
        emit LogUpdateAcceptedTokenList(token, state);
    }

    function updateAdminList(address admin, bool state) external onlyOwner {
        require(adminList[admin] != state, "SAME_STATE");
        adminList[admin] = state;
        emit LogUpdateAdminList(admin, state);
    }

    function setPause() external onlyOwner {
        _pause();
    }

    function setUnpause() external onlyOwner {
        _unpause();
    }

    function setBuyFee(uint256 _buyFee) external onlyOwner {
        require(_buyFee < MAX_FEE, "OVER_MAX_FEE");

        BUY_FEE = _buyFee;
        emit LogSetBuyFee(BUY_FEE);
    }

    function setSellFee(uint256 _sellFee) external onlyOwner {
        require(_sellFee < MAX_FEE, "OVER_MAX_FEE");

        SELL_FEE = _sellFee;
        emit LogSetSellFee(SELL_FEE);
    }

    function enableCreateOffer(uint256 btcNFTId) private view returns (bool) {
        if (
            offerState[btcNFTId] == OSTATE.NOT_STARTED ||
            offerState[btcNFTId] == OSTATE.CANCELED ||
            offerState[btcNFTId] == OSTATE.COMPLETED
        ) return true;
        return false;
    }

    function buyBTCNFTwithETH(
        string calldata inscriptionID,
        uint256 btcNFTId,
        string calldata nft_owner,
        string calldata nft_receiver,
        uint256 ethAmount,
        address seller,
        uint256 deadline
    ) external payable whenNotPaused {
        require(block.timestamp <= deadline, "OVER_TIME");
        require(acceptedTokenList[ETH], "NON_ACCEPTABLE_TOKEN");
        require(enableCreateOffer(btcNFTId), "DISABLE_CREATE_OFFER");
        uint256 buyFeeAmount = (ethAmount * BUY_FEE) / FEE_DENOMINATOR;
        require(
            msg.value >= (ethAmount + buyFeeAmount),
            "INSUFFICIENT_ETH_AMOUNT"
        );

        buyerHistory[msg.sender][ETH] += ethAmount;
        offerInfo[orderNumber] = OfferInfo({
            buyer: msg.sender,
            inscriptionID: inscriptionID,
            btcNFTId: btcNFTId,
            nft_owner: nft_owner,
            nft_receiver: nft_receiver,
            token: ETH,
            amount: ethAmount,
            seller: seller,
            state: OSTATE.CREATED
        });
        offerState[btcNFTId] = OSTATE.CREATED;

        orderNumber += 1;

        emit LogBuyBTCNFT(
            msg.sender,
            inscriptionID,
            btcNFTId,
            nft_owner,
            nft_receiver,
            ETH,
            ethAmount,
            seller
        );
    }

    function buyBTCNFT(
        string calldata inscriptionID,
        uint256 btcNFTId,
        string calldata nft_owner,
        string calldata nft_receiver,
        IERC20 token,
        uint256 amount,
        address seller,
        uint256 deadline
    ) external whenNotPaused {
        require(block.timestamp <= deadline, "OVER_TIME");
        require(acceptedTokenList[address(token)], "NON_ACCEPTABLE_TOKEN");
        require(enableCreateOffer(btcNFTId), "DISABLE_CREATE_OFFER");
        uint256 buyFeeAmount = (amount * BUY_FEE) / FEE_DENOMINATOR;
        require(
            token.transferFrom(
                msg.sender,
                address(this),
                amount + buyFeeAmount
            ),
            "INSUFFICIENT_TOKEN_AMOUNT"
        );

        buyerHistory[msg.sender][address(token)] += amount;
        offerInfo[orderNumber] = OfferInfo({
            buyer: msg.sender,
            inscriptionID: inscriptionID,
            btcNFTId: btcNFTId,
            nft_owner: nft_owner,
            nft_receiver: nft_receiver,
            token: address(token),
            amount: amount,
            seller: seller,
            state: OSTATE.CREATED
        });
        offerState[btcNFTId] = OSTATE.CREATED;

        orderNumber += 1;

        emit LogBuyBTCNFT(
            msg.sender,
            inscriptionID,
            btcNFTId,
            nft_owner,
            nft_receiver,
            address(token),
            amount,
            seller
        );
    }

    function offerCheck(uint256 _orderNumber, OSTATE _state)
        external
        whenNotPaused
        onlyAdmins
    {
        require(
            (_state == OSTATE.ALLOWED) || (_state == OSTATE.CANCELED),
            "UNKNOWN_STATE"
        );

        uint256 btcNFTId = offerInfo[_orderNumber].btcNFTId;

        require(
            (offerState[btcNFTId] == OSTATE.CREATED) &&
                (offerInfo[_orderNumber].state == OSTATE.CREATED),
            "CANNOT_OFFER_CHECk"
        );

        offerInfo[_orderNumber].state = _state;
        offerState[btcNFTId] = _state;

        emit LogOfferCheck(_orderNumber, _state);
    }

    function withdraw(uint256 _orderNumber) external whenNotPaused {
        require(offerInfo[_orderNumber].seller == msg.sender, "NOT_SELLER");
        uint256 btcNFTId = offerInfo[_orderNumber].btcNFTId;
        require(
            (offerState[btcNFTId] == OSTATE.ALLOWED) &&
                (offerInfo[_orderNumber].state == OSTATE.ALLOWED),
            "NOT_ALLOWED"
        );

        address token = offerInfo[_orderNumber].token;
        uint256 amount = offerInfo[_orderNumber].amount;
        uint256 sellFeeAmount = (amount * SELL_FEE) / FEE_DENOMINATOR;

        if (token == ETH) {
            payable(msg.sender).transfer(amount - sellFeeAmount);
        } else {
            require(
                IERC20(token).transfer(msg.sender, amount - sellFeeAmount),
                "TRANSFER_FAILED"
            );
        }

        sellerHistory[msg.sender][token] += amount;

        offerInfo[_orderNumber].state = OSTATE.COMPLETED;
        offerState[btcNFTId] = OSTATE.COMPLETED;

        emit LogWithdraw(msg.sender, _orderNumber);
    }

    function withdrawFee(
        IERC20 token,
        uint256 amount,
        uint256 ethAmount
    ) external onlyOwner {
        uint256 tokenBalance = token.balanceOf(address(this));
        if (amount <= tokenBalance) {
            token.transfer(msg.sender, amount);
        }

        if (ethAmount <= address(this).balance) {
            payable(msg.sender).transfer(ethAmount);
        }

        emit LogWithdrawFee(msg.sender, token, amount, ethAmount);
    }
}