namespace WinMint.Provisioning;

/// <summary>Windows NCSI-style probe for FirstLogon network gate (issue 71).</summary>
internal sealed class WindowsConnectivityProbe : IConnectivityProbe
{
    private static readonly Uri ProbeUri = new("http://www.msftconnecttest.com/connecttest.txt");

    public async Task<bool> HasOutboundNetworkAsync(CancellationToken ct = default)
    {
        try
        {
            using HttpClient client = new() { Timeout = TimeSpan.FromSeconds(5) };
            using HttpResponseMessage response = await client.GetAsync(ProbeUri, ct).ConfigureAwait(false);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
