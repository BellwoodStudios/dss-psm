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
        require(gemJoin_.dec() <= 18, "PsmFlipper/dec-too-high");

        // Give admin rights to contract creator
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        // Add contract refs and cache as much into immutable variables as possible to save gas
        vat = VatAbstract(psm_.vat());
        cat = CatAbstract(cat_);

        gemJoin = gemJoin_;
        ilk = gemJoin_.ilk();

        psm = address(psm_);
        psmGemJoin = AuthGemJoinLike(psm_.gemJoin());
        psmIlk = psm_.ilk();

        to18ConversionFactor = 10 ** (18 - gemJoin_.dec());

        // Infinite approval to save gas in kick
        GemAbstract(gemJoin_.gem()).approve(psm_.gemJoin(), uint256(-1));
    }

    // --- Kick ---
    function kick(address usr, address gal, uint256 tab, uint256 lot, uint256 bid)
        external auth returns (uint256 id)
    {
        require(kicks < uint256(-1), "PsmFlipper/overflow");
        id = ++kicks;

        vat.flux(ilk, msg.sender, address(this), lot);
        // Use the gems available (instead of lot) to move over dust as it accumulates
        uint256 amt = vat.gem(ilk, address(this)) / to18ConversionFactor;
        int256 gems = int256(amt * to18ConversionFactor);
        gemJoin.exit(address(this), amt);
        psmGemJoin.join(psm, amt, address(this));
        vat.frob(psmIlk, psm, psm, address(gal), gems, gems);
        cat.claw(tab);

        emit Kick(id, lot, bid, tab, usr, gal);
    }

}
