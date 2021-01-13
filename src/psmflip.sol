pragma solidity ^0.6.7;

import { CatAbstract } from "dss-interfaces/dss/CatAbstract.sol";
import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";
import { GemJoinAbstract } from "dss-interfaces/dss/GemJoinAbstract.sol";
import { GemAbstract } from "dss-interfaces/ERC/GemAbstract.sol";

interface PsmLike {
    function vat() external view returns (address);
    function gemJoin() external view returns (address);
    function ilk() external view returns (bytes32);
}

interface AuthGemJoinLike {
    function join(address urn, uint256 wad, address _msgSender) external;
}

// PSM Flipper
// Liquidate a collateral of the same type into the PSM

contract PsmFlipper {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth { require(wards[msg.sender] == 1); _; }

    VatAbstract immutable public vat;
    CatAbstract immutable public cat;

    GemJoinAbstract public gemJoin;
    bytes32 immutable public ilk;

    address immutable public psm;
    AuthGemJoinLike immutable psmGemJoin;
    bytes32 immutable public psmIlk;

    uint256 public kicks = 0;
    uint256 immutable internal to18ConversionFactor;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kick(
        uint256 id,
        uint256 lot,
        uint256 bid,
        uint256 tab,
        address indexed usr,
        address indexed gal
    );

    // --- Init ---
    constructor(address cat_, GemJoinAbstract gemJoin_, PsmLike psm_) public {
        require(gemJoin_.gem() == GemJoinAbstract(psm_.gemJoin()).gem(), "PsmFlipper/gems-dont-match");
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        psm = address(psm_);
        vat = VatAbstract(psm_.vat());
        cat = CatAbstract(cat_);
        gemJoin = gemJoin_;
        ilk = gemJoin_.ilk();
        psmGemJoin = AuthGemJoinLike(psm_.gemJoin());
        psmIlk = psm_.ilk();
        to18ConversionFactor = 10 ** (18 - gemJoin_.dec());
        GemAbstract(gemJoin_.gem()).approve(psm_.gemJoin(), uint256(-1));
    }

    // --- Kick ---
    function kick(address usr, address gal, uint256 tab, uint256 lot, uint256 bid)
        external auth returns (uint256 id)
    {
        require(kicks < uint256(-1), "PsmFlipper/overflow");
        id = ++kicks;

        // TODO - deal with the dust?
        uint256 gems = lot / to18ConversionFactor;
        vat.flux(ilk, msg.sender, address(this), lot);
        gemJoin.exit(address(this), gems);
        psmGemJoin.join(psm, gems, address(this));
        vat.frob(psmIlk, psm, psm, address(gal), int256(lot), int256(lot));
        cat.claw(tab);

        emit Kick(id, lot, bid, tab, usr, gal);
    }

}
