namespace WinMint.Orchestrator.Tests
{
    public class ScaffoldTests
    {
        [Fact]
        public void OrchestratorMarker_IsPublicType()
        {
            Assert.NotNull(typeof(WinMint.Orchestrator.OrchestratorMarker));
        }
    }
}
