// Scaffold: Machine setup (--machine-setup) and Shell tenure land in Smoke tickets 03+.
// Deep module: ProvisioningSession (one phase machine; modes are entrypoints only).
if (args is ["--machine-setup", ..])
{
    Console.WriteLine("WinMint Provisioning scaffold (--machine-setup)");
    return;
}

Console.WriteLine("WinMint Provisioning scaffold (Shell)");
