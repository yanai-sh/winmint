namespace WinMint.Provisioning;

/// <summary>Windows NCSI-style probe for FirstLogon network gate (issue 71).</summary>
internal sealed class WindowsConnectivityProbe : IConnectivityProbe
{
    private static readonly Uri ProbeUri = new("http://www.msftconnecttest.com/connecttest.txt");

    public bool HasOutboundNetwork()
    {
        try
        {
            using HttpClient client = new() { Timeout = TimeSpan.FromSeconds(5) };
            using HttpResponseMessage response = client.GetAsync(ProbeUri).GetAwaiter().GetResult();
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}
