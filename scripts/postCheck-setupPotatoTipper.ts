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
import { lukso } from "viem/chains";
import { lsp7DigitalAssetAbi } from "@lukso/lsp7-contracts/abi";
import { lsp0Erc725AccountAbi } from "@lukso/lsp0-contracts/abi";

// ERC725Y data keys for LSP1 Delegate (LSP1UniversalReceiverDelegate:<typeId>)
// where typeId = LSP26_TYPE_IDS.LSP26FollowerSystem_FollowNotification / UnfollowNotification
const LSP1DELEGATE_ON_FOLLOW_DATA_KEY: Hex =
    "0x0cfc51aec37c55a4d0b1000071e02f9f05bcd5816ec4f3134aa2e5a916669537";
const LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY: Hex =
    "0x0cfc51aec37c55a4d0b100009d3c0b4012b69658977b099bdaa51eff0f0460f4";
const POTATO_TIPPER_SETTINGS_KEY: Hex =
    "0xd1d57abed02d4c2d7ce00000e8211998bb257be214c7b0997830cd295066cc6a";

async function main() {
    const {
        UP_ADDRESS,
        POTATO_TIPPER_ADDRESS,
        POTATO_TOKEN_ADDRESS,
        TIP_AMOUNT,
        MIN_FOLLOWERS,
        MIN_POTATO_BALANCE,
        TIPPING_BUDGET,
    } = process.env;

    if (!UP_ADDRESS) {
        console.error("❌ Missing env var: UP_ADDRESS");
        process.exit(1);
    }
    if (!POTATO_TIPPER_ADDRESS) {
        console.error("❌ Missing env var: POTATO_TIPPER_ADDRESS");
        process.exit(1);
    }
    if (!POTATO_TOKEN_ADDRESS) {
        console.error("❌ Missing env var: POTATO_TOKEN_ADDRESS");
        process.exit(1);
    }

    const upAddress = getAddress(UP_ADDRESS) as Address;
    const potatoTipperAddress = getAddress(POTATO_TIPPER_ADDRESS) as Address;
    const potatoTokenAddress = getAddress(POTATO_TOKEN_ADDRESS) as Address;

    const expectedTipAmount = TIP_AMOUNT ? BigInt(TIP_AMOUNT) : undefined;
    const expectedMinFollowers = MIN_FOLLOWERS ? BigInt(MIN_FOLLOWERS) : undefined;
    const expectedMinPotatoBalance = MIN_POTATO_BALANCE ? BigInt(MIN_POTATO_BALANCE) : undefined;
    const expectedTippingBudget = TIPPING_BUDGET ? BigInt(TIPPING_BUDGET) : undefined;

    console.log("=== Post-Check: PotatoTipper Setup Verification ===");
    console.log(`🆙 UP Address:           ${upAddress}`);
    console.log(`🤎 PotatoTipper Address: ${potatoTipperAddress}`);
    console.log(`🪙 POTATO Token Address: ${potatoTokenAddress}`);
    console.log("");

    const publicClient = createPublicClient({
        chain: lukso,
        transport: http(),
    });

    // Read LSP1 delegate keys first, then settings
    const rawValues = (await publicClient.readContract({
        address: upAddress,
        abi: lsp0Erc725AccountAbi,
        functionName: "getDataBatch",
        args: [[LSP1DELEGATE_ON_FOLLOW_DATA_KEY, LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY, POTATO_TIPPER_SETTINGS_KEY]],
    })) as Hex[];

    // --- Check 1: LSP1 Delegate on Follow ---
    console.log("--- Check 1: LSP1 Delegate (Follow) ---");
    const rawFollowDelegate = rawValues[0];
    if (!rawFollowDelegate || rawFollowDelegate === "0x") {
        console.log("❌ LSP1DELEGATE_ON_FOLLOW_DATA_KEY is empty — follow delegate not set.");
    } else {
        const storedFollowDelegate = ("0x" + rawFollowDelegate.slice(-40)) as Address;
        if (storedFollowDelegate.toLowerCase() === potatoTipperAddress.toLowerCase()) {
            console.log(`✅ Follow delegate set to PotatoTipper: ${storedFollowDelegate}`);
        } else {
            console.log(`❌ Follow delegate mismatch!`);
            console.log(`   Expected: ${potatoTipperAddress}`);
            console.log(`   Got:      ${storedFollowDelegate}`);
        }
    }
    console.log("");

    // --- Check 2: LSP1 Delegate on Unfollow ---
    console.log("--- Check 2: LSP1 Delegate (Unfollow) ---");
    const rawUnfollowDelegate = rawValues[1];
    if (!rawUnfollowDelegate || rawUnfollowDelegate === "0x") {
        console.log("❌ LSP1DELEGATE_ON_UNFOLLOW_DATA_KEY is empty — unfollow delegate not set.");
    } else {
        const storedUnfollowDelegate = ("0x" + rawUnfollowDelegate.slice(-40)) as Address;
        if (storedUnfollowDelegate.toLowerCase() === potatoTipperAddress.toLowerCase()) {
            console.log(`✅ Unfollow delegate set to PotatoTipper: ${storedUnfollowDelegate}`);
        } else {
            console.log(`❌ Unfollow delegate mismatch!`);
            console.log(`   Expected: ${potatoTipperAddress}`);
            console.log(`   Got:      ${storedUnfollowDelegate}`);
        }
    }
    console.log("");

    // --- Check 3: Tip Settings ---
    console.log("--- Check 3: Tip Settings ---");
    const rawSettings = rawValues[2];
    if (!rawSettings || rawSettings === "0x") {
        console.log("❌ POTATO_TIPPER_SETTINGS_KEY is empty — settings were not written.");
    } else {
        const [tipAmount, minFollowers, minPotatoBalance] = decodeAbiParameters(
            parseAbiParameters("uint256 tipAmount, uint256 minFollowers, uint256 minPotatoBalance"),
            rawSettings
        );
        console.log(`   Tip Amount:          ${tipAmount} wei`);
        console.log(`   Min Followers:       ${minFollowers}`);
        console.log(`   Min POTATO Balance:  ${minPotatoBalance} wei`);

        let settingsOk = true;
        if (expectedTipAmount !== undefined && tipAmount !== expectedTipAmount) {
            console.log(`   ❌ Tip amount mismatch! Expected: ${expectedTipAmount}, Got: ${tipAmount}`);
            settingsOk = false;
        }
        if (expectedMinFollowers !== undefined && minFollowers !== expectedMinFollowers) {
            console.log(`   ❌ Min followers mismatch! Expected: ${expectedMinFollowers}, Got: ${minFollowers}`);
            settingsOk = false;
        }
        if (expectedMinPotatoBalance !== undefined && minPotatoBalance !== expectedMinPotatoBalance) {
            console.log(`   ❌ Min balance mismatch! Expected: ${expectedMinPotatoBalance}, Got: ${minPotatoBalance}`);
            settingsOk = false;
        }
        if (settingsOk) {
            console.log("   ✅ All settings match expected values!");
        }
    }
    console.log("");

    // --- Check 4: Tipping Budget ---
    console.log("--- Check 4: Tipping Budget (Allowance) ---");
    const authorizedAmount = (await publicClient.readContract({
        address: potatoTokenAddress,
        abi: lsp7DigitalAssetAbi,
        functionName: "authorizedAmountFor",
        args: [potatoTipperAddress, upAddress],
    })) as bigint;
    console.log(`   Authorized amount: ${authorizedAmount} wei`);
    if (expectedTippingBudget !== undefined) {
        if (authorizedAmount >= expectedTippingBudget) {
            console.log(`   ✅ Budget authorized: ${authorizedAmount} >= ${expectedTippingBudget}`);
        } else {
            console.log(`   ❌ Budget too low! Expected: ${expectedTippingBudget}, Got: ${authorizedAmount}`);
        }
    } else if (authorizedAmount > 0n) {
        console.log(`   ✅ Budget authorized: ${authorizedAmount} wei`);
    } else {
        console.log("   ❌ No tipping budget authorized — run setup again.");
    }
    console.log("");
    console.log("=== Verification complete ===");
}

main().catch((error) => {
    console.error("Unexpected error:", error);
    process.exit(1);
});
