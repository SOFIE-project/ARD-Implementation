'use strict';

module.exports.info  = 'Template callback';

const contractID = 'vulnerability-private-data-collections';
const version = '0.0.2';

let bc, ctx, clientArgs, clientIdx;
module.exports.init = async function(blockchain, context, args) {
    bc = blockchain;
    ctx = context;
    clientArgs = args;
    clientIdx = context.clientIdx.toString();
    for (let i=0; i<clientArgs.assets; i++) {
        try {
            const assetID = `${clientIdx}_${i}`;
            console.log(`Client ${clientIdx}: Creating vulnerability ${assetID}`);
            const myArgs = {
                chaincodeFunction: 'createVulnerability',
                invokerIdentity: 'admin',
                chaincodeArguments: [assetID],
                transientMap: {vendorID:'1247',vendorName:'Intel',productName:'Aeon UP Gateway',vulnerabilityType:'Device Crash',vulnerabilitySeverity:'Low',gracePeriod:'90 days',bountyAmount:'$1500'}
            };
            await bc.bcObj.invokeSmartContract(ctx, contractID, version, myArgs);
        } catch (error) {
            console.log(`Client ${clientIdx}: Smart Contract threw with error: ${error}` );
        }
    }
};
module.exports.run = function() {
    const randomId = Math.floor(Math.random()*clientArgs.assets);
    const myArgs = {
        chaincodeFunction: 'readVulnerability',
        invokerIdentity: 'admin',
        chaincodeArguments: [`${clientIdx}_${randomId}`]
    };
    return bc.bcObj.querySmartContract(ctx, contractID, version, myArgs);
};
module.exports.end = async function() {
    for (let i=0; i<clientArgs.assets; i++) {
        try {
            const assetID = `${clientIdx}_${i}`;
            console.log(`Client ${clientIdx}: Deleting vulnerability ${assetID}`);
            const myArgs = {
                chaincodeFunction: 'deleteVulnerability',
                invokerIdentity: 'admin',
                chaincodeArguments: [assetID]
            };
            await bc.bcObj.invokeSmartContract(ctx, contractID, version, myArgs);
        } catch (error) {
            console.log(`Client ${clientIdx}: Smart Contract threw with error: ${error}` );
        }
    }
};