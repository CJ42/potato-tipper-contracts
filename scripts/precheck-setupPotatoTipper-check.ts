import "dotenv/config";
import { createPublicClient, http, getAddress, type Hex } from "viem";
import { lukso } from "viem/chains";
import { privateKeyToAddress } from "viem/accounts";
import { PERMISSIONS } from "@lukso/lsp6-contracts/constants";
import { ERC725 } from "@erc725/erc725.js";
import { lsp0Erc725AccountAbi } from "@lukso/lsp0-contracts/abi";

async function main() {
    const { UP_ADDRESS, PRIVATE_KEY } = process.env;

    if (!UP_ADDRESS) {
        console.error("❌ Missing env var: UP_ADDRESS");
        process.exit(1);
    }
    if (!PRIVATE_KEY) {
        console.error("❌ Missing env var: PRIVATE_KEY");
        process.exit(1);
    }

    const upAddress = getAddress(UP_ADDRESS);
    const controllerAddress = privateKeyToAddress(PRIVATE_KEY as Hex);

    console.log("=== Pre-Setup Check: PotatoTipper ===");
    console.log(`🆙 UP Address:  ${upAddress}`);
    console.log(`🔑 Controller:  ${controllerAddress}`);
    console.log("");

    const publicClient = createPublicClient({
        chain: lukso,
        transport: http(),
    });

    const permissionsKey = ERC725.encodeKeyName(
        "AddressPermissions:Permissions:<address>",
        [controllerAddress]
    ) as `0x${string}`;

    let rawPermissions: Hex;
    try {
        rawPermissions = (await publicClient.readContract({
            address: upAddress,
            abi: lsp0Erc725AccountAbi,
            functionName: "getData",
            args: [permissionsKey],
        })) as Hex;
    } catch (error) {
        console.error("❌ Failed to read permissions from UP:", error);
        process.exit(1);
    }

    if (!rawPermissions || rawPermissions === "0x" || rawPermissions.length === 0) {
        console.log("❌ No permissions found for this controller on the UP.");
        console.log("   The controller has no permissions at all.");
        console.log("");
        console.log("To fix: grant ADDUNIVERSALRECEIVERDELEGATE permission via the UP Browser Extension.");
        process.exit(1);
    }

    const permissionsBigInt = BigInt(rawPermissions);
    const requiredBit = BigInt(PERMISSIONS.ADDUNIVERSALRECEIVERDELEGATE);
    const hasPermission = (permissionsBigInt & requiredBit) !== 0n;

    if (hasPermission) {
        console.log("✅ Controller has ADDUNIVERSALRECEIVERDELEGATE permission — ready to run setup!");
    } else {
        console.log("❌ Controller is MISSING the ADDUNIVERSALRECEIVERDELEGATE permission on this UP.");
        console.log("");
        console.log("To fix:");
        console.log("  1. Open the UP Browser Extension");
        console.log("  2. Navigate to Controllers");
        console.log(`  3. Find your controller address: ${controllerAddress}`);
        console.log("  4. Enable 'Add Universal Receiver Delegate' permission");
        console.log("  5. Save and re-run this check");
        process.exit(1);
    }
}

main().catch((error) => {
    console.error("Unexpected error:", error);
    process.exit(1);
});
