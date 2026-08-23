namespace WinMint.Provisioning;

public static class HypervisorGuest
{
    public static bool IsGuest(string? manufacturer, string? model, bool hyperVGuestKeyExists)
    {
        if (hyperVGuestKeyExists)
        {
            return true;
        }

        if (Contains(manufacturer, "Microsoft") && Contains(model, "Virtual Machine"))
        {
            return true;
        }

        return IsVendorGuest(manufacturer) || IsVendorGuest(model);
    }

    private static bool IsVendorGuest(string? value) =>
        Contains(value, "VMware")
        || Contains(value, "VirtualBox")
        || Contains(value, "QEMU")
        || Contains(value, "KVM")
        || Contains(value, "Xen");

    private static bool Contains(string? haystack, string needle) =>
        haystack is not null && haystack.Contains(needle, StringComparison.OrdinalIgnoreCase);
}
