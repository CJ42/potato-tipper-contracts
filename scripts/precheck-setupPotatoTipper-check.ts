import "dotenv/config";
import { createPublicClient, http, getAddress, pad, keccak256, toBytes, toHex, type Hex } from "viem";

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

// LSP6 permission bit for ADDUNIVERSALRECEIVERDELEGATE
const PERMISSION_ADDUNIVERSALRECEIVERDELEGATE: Hex =
    "0x0000000000000000000000000000000000000000000000000000000000000020";

// Build AddressPermissions:Permissions:<address> data key
// prefix = keccak256("AddressPermissions:Permissions") first 10 bytes (0x4b80742de2bf82acb3630000)
function buildPermissionsKey(controllerAddress: string): Hex {
    const prefix = "0x4b80742de2bf82acb3630000";
    const paddedAddress = controllerAddress.toLowerCase().replace("0x", "").padStart(40, "0");
    return `${prefix}${paddedAddress}` as Hex;
}

const ERC725Y_ABI = [
    {
        name: "getData",
        type: "function",
        stateMutability: "view",
        inputs: [{ name: "key", type: "bytes32" }],
        outputs: [{ name: "", type: "bytes" }],
    },
] as const;

async function main() {
    const upAddressRaw = process.env.UP_ADDRESS;
    const privateKeyRaw = process.env.PRIVATE_KEY;

    if (!upAddressRaw) {
        console.error("❌ Missing env var: UP_ADDRESS");
        process.exit(1);
    }
    if (!privateKeyRaw) {
        console.error("❌ Missing env var: PRIVATE_KEY");
        process.exit(1);
    }

    const upAddress = getAddress(upAddressRaw);

    // Derive controller address from private key
    const { privateKeyToAddress } = await import("viem/accounts");
    const controllerAddress = privateKeyToAddress(privateKeyRaw as Hex);

    console.log("=== Pre-Check: PotatoTipper Setup ===");
    console.log(`UP Address:   ${upAddress}`);
    console.log(`Controller:   ${controllerAddress}`);
    console.log("");

    const publicClient = createPublicClient({
        chain: luksoMainnet,
        transport: http(),
    });

    const permissionsKey = buildPermissionsKey(controllerAddress);

    let rawPermissions: Hex;
    try {
        rawPermissions = (await publicClient.readContract({
            address: upAddress,
            abi: ERC725Y_ABI,
            functionName: "getData",
            args: [permissionsKey as `0x${string}`],
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

    // rawPermissions is a 32-byte hex value
    const permissionsBigInt = BigInt(rawPermissions);
    const requiredBit = BigInt(PERMISSION_ADDUNIVERSALRECEIVERDELEGATE);
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
