import "dotenv/config";
import {
    createPublicClient,
    http,
    getAddress,
    decodeAbiParameters,
    parseAbiParameters,
    type Hex,
    type Address,
} from "viem";

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

const GET_DATA_BATCH_ABI = [
    {
        name: "getDataBatch",
        type: "function",
        stateMutability: "view",
        inputs: [{ name: "keys", type: "bytes32[]" }],
        outputs: [{ name: "", type: "bytes[]" }],
    },
] as const;

const AUTHORIZED_AMOUNT_FOR_ABI = [
    {
        name: "authorizedAmountFor",
        type: "function",
        stateMutability: "view",
        inputs: [
            { name: "operator", type: "address" },
            { name: "tokenOwner", type: "address" },
        ],
        outputs: [{ name: "", type: "uint256" }],
    },
] as const;

async function main() {
    const upAddressRaw = process.env.UP_ADDRESS;
    const potatoTipperAddressRaw = process.env.POTATO_TIPPER_ADDRESS;
    const potatoTokenAddressRaw = process.env.POTATO_TOKEN_ADDRESS;
    const expectedTipAmount = process.env.TIP_AMOUNT ? BigInt(process.env.TIP_AMOUNT) : undefined;
    const expectedMinFollowers = process.env.MIN_FOLLOWERS ? BigInt(process.env.MIN_FOLLOWERS) : undefined;
    const expectedMinPotatoBalance = process.env.MIN_POTATO_BALANCE ? BigInt(process.env.MIN_POTATO_BALANCE) : undefined;
    const expectedTippingBudget = process.env.TIPPING_BUDGET ? BigInt(process.env.TIPPING_BUDGET) : undefined;

    if (!upAddressRaw || !potatoTipperAddressRaw || !potatoTokenAddressRaw) {
        console.error("❌ Missing required env vars: UP_ADDRESS, POTATO_TIPPER_ADDRESS, POTATO_TOKEN_ADDRESS");
        process.exit(1);
    }

    const upAddress = getAddress(upAddressRaw) as Address;
    const potatoTipperAddress = getAddress(potatoTipperAddressRaw) as Address;
    const potatoTokenAddress = getAddress(potatoTokenAddressRaw) as Address;

    console.log("=== Post-Check: PotatoTipper Setup Verification ===");
    console.log(`UP Address:           ${upAddress}`);
    console.log(`PotatoTipper Address: ${potatoTipperAddress}`);
    console.log(`POTATO Token Address: ${potatoTokenAddress}`);
    console.log("");

    const publicClient = createPublicClient({
        chain: luksoMainnet,
        transport: http(),
    });

    // Read all 3 data keys in one call
    const rawValues = (await publicClient.readContract({
        address: upAddress,
        abi: GET_DATA_BATCH_ABI,
        functionName: "getDataBatch",
        args: [[POTATO_TIPPER_SETTINGS_KEY, LSP1DELEGATE_ON_FOLLOW_DATA_KEY, LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY]],
    })) as Hex[];

    // --- Check 1: Settings ---
    console.log("--- Check 1: Tip Settings ---");
    const rawSettings = rawValues[0];
    if (!rawSettings || rawSettings === "0x") {
        console.log("❌ POTATO_TIPPER_SETTINGS_KEY is empty — settings were not written.");
    } else {
        const [tipAmount, minFollowers, minPotatoBalance] = decodeAbiParameters(
            parseAbiParameters("uint256 tipAmount, uint256 minFollowers, uint256 minPotatoBalance"),
            rawSettings
        );

        console.log(`  Tip Amount (wei):         ${tipAmount}`);
        console.log(`  Min Followers:            ${minFollowers}`);
        console.log(`  Min POTATO Balance (wei): ${minPotatoBalance}`);

        const settingsMatch =
            (!expectedTipAmount || tipAmount === expectedTipAmount) &&
            (!expectedMinFollowers || minFollowers === expectedMinFollowers) &&
            (!expectedMinPotatoBalance || minPotatoBalance === expectedMinPotatoBalance);

        if (settingsMatch) {
            console.log("  ✅ Settings match expected values.");
        } else {
            console.log("  ❌ Settings do NOT match expected values.");
            if (expectedTipAmount) console.log(`     Expected Tip Amount:         ${expectedTipAmount}`);
            if (expectedMinFollowers) console.log(`     Expected Min Followers:      ${expectedMinFollowers}`);
            if (expectedMinPotatoBalance)
                console.log(`     Expected Min POTATO Balance: ${expectedMinPotatoBalance}`);
        }
    }

    console.log("");

    // --- Check 2: LSP1 delegate for follow ---
    console.log("--- Check 2: LSP1 Delegate (on follow) ---");
    const rawFollowDelegate = rawValues[1];
    if (!rawFollowDelegate || rawFollowDelegate === "0x") {
        console.log("❌ LSP1DELEGATE_ON_FOLLOW_DATA_KEY is empty — delegate not set.");
    } else {
        // The value is stored as a 20-byte address (packed, not ABI-encoded)
        const followDelegate = getAddress(`0x${rawFollowDelegate.slice(-40)}`);
        if (followDelegate.toLowerCase() === potatoTipperAddress.toLowerCase()) {
            console.log(`  ✅ Follow delegate correctly set to PotatoTipper: ${followDelegate}`);
        } else {
            console.log("  ❌ Follow delegate mismatch.");
            console.log(`     Expected: ${potatoTipperAddress}`);
            console.log(`     Got:      ${followDelegate}`);
        }
    }

    console.log("");

    // --- Check 3: LSP1 delegate for unfollow ---
    console.log("--- Check 3: LSP1 Delegate (on unfollow) ---");
    const rawUnfollowDelegate = rawValues[2];
    if (!rawUnfollowDelegate || rawUnfollowDelegate === "0x") {
        console.log("❌ LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY is empty — delegate not set.");
    } else {
        const unfollowDelegate = getAddress(`0x${rawUnfollowDelegate.slice(-40)}`);
        if (unfollowDelegate.toLowerCase() === potatoTipperAddress.toLowerCase()) {
            console.log(`  ✅ Unfollow delegate correctly set to PotatoTipper: ${unfollowDelegate}`);
        } else {
            console.log("  ❌ Unfollow delegate mismatch.");
            console.log(`     Expected: ${potatoTipperAddress}`);
            console.log(`     Got:      ${unfollowDelegate}`);
        }
    }

    console.log("");

    // --- Check 4: $POTATO token allowance ---
    console.log("--- Check 4: $POTATO Token Allowance ---");
    const allowance = (await publicClient.readContract({
        address: potatoTokenAddress,
        abi: AUTHORIZED_AMOUNT_FOR_ABI,
        functionName: "authorizedAmountFor",
        args: [potatoTipperAddress, upAddress],
    })) as bigint;

    console.log(`  Authorized amount (wei): ${allowance}`);

    if (expectedTippingBudget !== undefined) {
        if (allowance >= expectedTippingBudget) {
            console.log("  ✅ Tipping budget authorized — PotatoTipper can spend POTATO tokens.");
        } else if (allowance > 0n) {
            console.log(`  ⚠️  Partial budget authorized. Expected: ${expectedTippingBudget}, Got: ${allowance}`);
        } else {
            console.log("  ❌ No tipping budget authorized — authorizeOperator was not called.");
        }
    } else {
        if (allowance > 0n) {
            console.log("  ✅ Tipping budget authorized.");
        } else {
            console.log("  ❌ No tipping budget authorized — authorizeOperator was not called.");
        }
    }

    console.log("");
    console.log("=== Verification Complete ===");
}

main().catch((error) => {
    console.error("Unexpected error:", error);
    process.exit(1);
});
