const truffleAssert = require('truffle-assertions');
const Authority = artifacts.require("AuthorityContract");
const Vendor = artifacts.require("VendorContractTest");
const Factory = artifacts.require("VendorFactory");

contract("AuthorityContract", function(accounts) {

    const researcherAddress = accounts[0];
    const vendorAddress = accounts[1];
    const authorityAddress = accounts[2];
    const interledgerAddress = accounts[3];
    
    const STATUS = {
        Pending: 0,
        Invalid: 1,
        Valid: 2,
        Acknowledged: 3,
        Patched: 4,
        Disclosable: 5,
        Disclosed: 6
    }

    const REWARDSTATE = {
        NULL: 0,
        SET: 1,
        CANCELED: 2,
        SENT: 3
    }

    const secret = 123;
    const hashlock = web3.utils.soliditySha3({type: 'uint', value: secret});
    const metadata = web3.utils.fromAscii(new String(13245678910)); // Random metadata in bytes32
    const bounty = web3.utils.toWei('1', 'ether');
    const vendorName = web3.utils.fromAscii("Test vendor");
    const productName = web3.utils.fromAscii("Test product");
    const productVersion = web3.utils.fromAscii("Test version");
    const vulnerabilityData = "Vulnerability detailed description in text format";
    const vulnerabilityHash = web3.utils.soliditySha3({type: 'string', value: vulnerabilityData});
    const vulnerabilityLocation = "https://organization.org/report_1_test";

    describe("Constructor()", function() {

        it("Should execute the constructor with the correct params", async function() {

            // console.log(await Authority.new.estimateGas(interledgerAddress, accounts[8]));
            let authority = await Authority.new(interledgerAddress, accounts[8], {from: authorityAddress});

            const il = await authority.interledger();

            assert.equal(interledgerAddress, il, "The address of interledger should be " + interledgerAddress);
        });
    });


});