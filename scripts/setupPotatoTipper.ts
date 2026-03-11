import "dotenv/config";
import {
    createPublicClient,
    createWalletClient,
    http,
    getAddress,
    encodeFunctionData,
    encodeAbiParameters,
    parseAbiParameters,
    type Hex,
    type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

// LUKSO Mainnet
const luksoMainnet = {
    id: 42,
    name: "LUKSO Mainnet",
    network: "lukso",
    nativeCurrency: { name: "LYX", symbol: "LYX", decimals: 18 },
    rpcUrls: {
        default: { http: ["https://rpc.mainnet.lukso.network"] },
        public: { http: ["https://rpc.mainnet.lukso.network"] },
    },
} as const;

// Data keys
const LSP1DELEGATE_ON_FOLLOW_DATA_KEY: Hex =
    "0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537";
const LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY: Hex =
    "0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4";
const POTATO_TIPPER_SETTINGS_KEY: Hex =
    "0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a";

// ABIs
const SET_DATA_BATCH_ABI = [
    {
        name: "setDataBatch",
        type: "function",
        stateMutability: "nonpayable",
        inputs: [
            { name: "keys", type: "bytes32[]" },
            { name: "values", type: "bytes[]" },
        ],
        outputs: [],
    },
] as const;

const EXECUTE_ABI = [
    {
        name: "execute",
        type: "function",
        stateMutability: "payable",
        inputs: [
            { name: "operationType", type: "uint256" },
            { name: "target", type: "address" },
            { name: "value", type: "uint256" },
            { name: "data", type: "bytes" },
        ],
        outputs: [{ name: "", type: "bytes" }],
    },
] as const;

const AUTHORIZE_OPERATOR_ABI = [
    {
        name: "authorizeOperator",
        type: "function",
        stateMutability: "nonpayable",
        inputs: [
            { name: "operator", type: "address" },
            { name: "amount", type: "uint256" },
            { name: "data", type: "bytes" },
        ],
        outputs: [],
    },
] as const;

const BATCH_CALLS_ABI = [
    {
        name: "batchCalls",
        type: "function",
        stateMutability: "nonpayable",
        inputs: [
            { name: "values", type: "uint256[]" },
            { name: "payloads", type: "bytes[]" },
        ],
        outputs: [{ name: "", type: "bytes[]" }],
    },
] as const;

async function main() {
    // Load env vars
    const privateKeyRaw = process.env.PRIVATE_KEY as Hex | undefined;
    const upAddressRaw = process.env.UP_ADDRESS;
    const potatoTipperAddressRaw = process.env.POTATO_TIPPER_ADDRESS;
    const potatoTokenAddressRaw = process.env.POTATO_TOKEN_ADDRESS;
    const tipAmountRaw = process.env.TIP_AMOUNT;
    const minFollowersRaw = process.env.MIN_FOLLOWERS;
    const minPotatoBalanceRaw = process.env.MIN_POTATO_BALANCE;
    const tippingBudgetRaw = process.env.TIPPING_BUDGET;

    const missing = [
        !privateKeyRaw && "PRIVATE_KEY",
        !upAddressRaw && "UP_ADDRESS",
        !potatoTipperAddressRaw && "POTATO_TIPPER_ADDRESS",
        !potatoTokenAddressRaw && "POTATO_TOKEN_ADDRESS",
        !tipAmountRaw && "TIP_AMOUNT",
        !minFollowersRaw && "MIN_FOLLOWERS",
        !minPotatoBalanceRaw && "MIN_POTATO_BALANCE",
        !tippingBudgetRaw && "TIPPING_BUDGET",
    ].filter(Boolean);

    if (missing.length > 0) {
        console.error(`❌ Missing env vars: ${missing.join(", ")}`);
        process.exit(1);
    }

    const upAddress = getAddress(upAddressRaw!) as Address;
    const potatoTipperAddress = getAddress(potatoTipperAddressRaw!) as Address;
    const potatoTokenAddress = getAddress(potatoTokenAddressRaw!) as Address;
    const tipAmount = BigInt(tipAmountRaw!);
    const minFollowers = BigInt(minFollowersRaw!);
    const minPotatoBalance = BigInt(minPotatoBalanceRaw!);
    const tippingBudget = BigInt(tippingBudgetRaw!);

    const account = privateKeyToAccount(privateKeyRaw!);

    console.log("=== PotatoTipper Setup ===");
    console.log(`Controller:          ${account.address}`);
    console.log(`UP Address:          ${upAddress}`);
    console.log(`PotatoTipper:        ${potatoTipperAddress}`);
    console.log(`POTATO Token:        ${potatoTokenAddress}`);
    console.log(`Tip Amount (wei):    ${tipAmount}`);
    console.log(`Min Followers:       ${minFollowers}`);
    console.log(`Min POTATO Balance:  ${minPotatoBalance} wei`);
    console.log(`Tipping Budget:      ${tippingBudget} wei`);
    console.log("");

    const publicClient = createPublicClient({
        chain: luksoMainnet,
        transport: http(),
    });

    const walletClient = createWalletClient({
        account,
        chain: luksoMainnet,
        transport: http(),
    });

    // --- Build payload 1: setDataBatch with 3 keys ---
    const settingsValue = encodeAbiParameters(
        parseAbiParameters("uint256 tipAmount, uint256 minFollowers, uint256 minPotatoBalance"),
        [tipAmount, minFollowers, minPotatoBalance]
    );

    // Pad address to 20 bytes (as bytes)
    const potatoTipperBytes = `0x${potatoTipperAddress.toLowerCase().replace("0x", "")}` as Hex;

    const setDataBatchCalldata = encodeFunctionData({
        abi: SET_DATA_BATCH_ABI,
        functionName: "setDataBatch",
        args: [
            [POTATO_TIPPER_SETTINGS_KEY, LSP1DELEGATE_ON_FOLLOW_DATA_KEY, LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY],
            [settingsValue, potatoTipperBytes, potatoTipperBytes],
        ],
    });

    // --- Build payload 2: execute -> authorizeOperator on POTATO token ---
    const authorizeOperatorCalldata = encodeFunctionData({
        abi: AUTHORIZE_OPERATOR_ABI,
        functionName: "authorizeOperator",
        args: [potatoTipperAddress, tippingBudget, "0x"],
    });

    const executeCalldata = encodeFunctionData({
        abi: EXECUTE_ABI,
        functionName: "execute",
        args: [0n, potatoTokenAddress, 0n, authorizeOperatorCalldata],
    });

    // --- Batch both payloads into a single batchCalls transaction ---
    console.log("Broadcasting batchCalls to UP...");

    const txHash = await walletClient.writeContract({
        address: upAddress,
        abi: BATCH_CALLS_ABI,
        functionName: "batchCalls",
        args: [[0n, 0n], [setDataBatchCalldata, executeCalldata]],
    });

    console.log(`Transaction sent: ${txHash}`);
    console.log("Waiting for confirmation...");

    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

    if (receipt.status === "success") {
        console.log("");
        console.log("=== Setup Complete ===");
        console.log("✅ PotatoTipper is now connected to the UP!");
        console.log("   Settings configured:");
        console.log(`     - Tip amount:           ${tipAmount} wei`);
        console.log(`     - Min followers:        ${minFollowers}`);
        console.log(`     - Min POTATO balance:   ${minPotatoBalance} wei`);
        console.log(`   Tipping budget authorized: ${tippingBudget} wei`);
        console.log(`   Block: ${receipt.blockNumber}`);
    } else {
        console.error("❌ Transaction reverted. Check your permissions and env vars.");
        process.exit(1);
    }
}

main().catch((error) => {
    console.error("Unexpected error:", error);
    process.exit(1);
});
