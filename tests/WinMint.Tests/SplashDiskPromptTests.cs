using WinMint.WinPeApply;

namespace WinMint.Tests;

public class SplashDiskPromptTests
{
    private const string ListSample = """
        Microsoft DiskPart version 10.0.26100.1

          Disk ###  Status         Size     Free     Dyn  Gpt
          --------  -------------  -------  -------  ---  ---
          Disk 0    Online          953 GB      0 B        *
          Disk 1    No Media           0 B      0 B
          Disk 2    Online           29 GB    28 GB
        """;

    [Fact]
    public void Splash_argument_does_not_start_LaunchApply()
    {
        bool ran = false;
        int code = WinPeApplyHost.Dispatch(
            ["--splash"],
            () =>
            {
                ran = true;
                return 3;
            },
            () => { });

        Assert.Equal(0, code);
        Assert.False(ran);
    }

    [Fact]
    public void Any_other_argument_still_runs_LaunchApply()
    {
        bool ran = false;
        int code = WinPeApplyHost.Dispatch([], () =>
        {
            ran = true;
            return 4;
        }, () => { });

        Assert.Equal(4, code);
        Assert.True(ran);
    }

    [Fact]
    public void Diskpart_scripts_list_and_detail_only()
    {
        Assert.True(SplashDiskList.IsListOnly(SplashDiskList.ListScript));
        Assert.True(SplashDiskList.IsListOnly(SplashDiskList.DetailScript(2)));
        Assert.False(SplashDiskList.IsListOnly("select disk 1\r\nclean\r\nexit\r\n"));
        Assert.False(SplashDiskList.IsListOnly("format quick fs=ntfs\r\n"));
        Assert.False(SplashDiskList.IsListOnly("create partition primary\r\n"));
    }

    [Fact]
    public void Parse_reads_number_and_size_and_leaves_the_model_for_detail()
    {
        IReadOnlyList<SplashDisk> rows = SplashDiskList.ParseList(ListSample);

        Assert.Equal(3, rows.Count);
        Assert.Equal(new SplashDisk(0, "953 GB", ""), rows[0]);
        Assert.Equal(new SplashDisk(1, "0 B", ""), rows[1]);
        Assert.Equal(new SplashDisk(2, "29 GB", ""), rows[2]);
        Assert.Equal("WD_BLACK SN850X 1000GB", SplashDiskList.ParseModel("""
            WD_BLACK SN850X 1000GB
            Disk ID: {ABC}
            Type   : NVMe
            """));
    }

    [Fact]
    public void Prompt_copy_names_the_disk_and_says_it_was_not_erased()
    {
        Assert.Equal("Target disk", SplashDiskPrompt.Heading);
        Assert.Equal("Nothing is selected. Press the arrow keys, or click a disk.", SplashDiskPrompt.Lead);
        Assert.Equal("*", SplashDiskPrompt.Asterisk);
        Assert.Equal(0, SplashDiskPrompt.InitialFocus(1));
        Assert.Equal(0, SplashDiskPrompt.InitialFocus(3));
        Assert.Equal(-1, SplashDiskPrompt.InitialFocus(0));
        Assert.Equal(
            "Press Enter to mark (Disk 1). The disk is not erased.",
            SplashDiskPrompt.Cue(new SplashDisk(1, "953 GB", "WD_BLACK SN850X")));
        Assert.Equal("Disk 2  29 GB", SplashDiskPrompt.RowLabel(new SplashDisk(2, "29 GB", "")));
        Assert.Equal("2 disks listed.", SplashDiskPrompt.Fact(2));
        Assert.Equal("No disk was listed.", SplashDiskPrompt.Fact(0));
        Assert.Equal(
            "(Disk 1) is marked. The disk was not erased.",
            SplashDiskPrompt.Marked(new SplashDisk(1, "953 GB", "WD_BLACK SN850X")));
    }

    [Fact]
    public void Hero_frame_stays_the_large_lockup()
    {
        Assert.True(BrandLockup.TryFrame(1440, 900, out int x, out int y, out int width, out int height));
        Assert.Equal(892, width);
        Assert.Equal(223, height);
        Assert.Equal(274, x);
        Assert.Equal(288, y);
    }

    [Theory]
    [InlineData(1440, 900)]
    [InlineData(1024, 768)]
    [InlineData(768, 1024)]
    [InlineData(390, 844)]
    [InlineData(320, 844)]
    public void Layout_keeps_the_hero_and_the_prompt_on_one_screen(int width, int height)
    {
        Assert.True(BrandLockup.TryFrame(width, height, out _, out int heroY, out _, out int heroH));
        int minY = SplashDiskPrompt.PromptTop(heroY + heroH, 96);
        SplashDiskPrompt.PromptLayout layout = SplashDiskPrompt.Measure(width, 96, 3, minY);
        int rightGap = width - layout.Status.Right;
        int bottom = layout.List.H == 0 ? layout.Status.Bottom : layout.List.Bottom;

        Assert.Equal(0, layout.Mark.H);
        Assert.Equal(24, layout.Status.H);
        Assert.True(layout.Status.Y >= minY);
        Assert.InRange(Math.Abs(layout.Margin - rightGap), 0, 1);
        Assert.True(layout.Status.Bottom <= layout.List.Y);
        Assert.True(bottom <= height - 24);
        Assert.Equal(layout.Status.X, layout.List.X);
        Assert.Equal(layout.Status.Right, layout.List.Right);
        Assert.Equal(0, SplashDiskPrompt.RowAt(layout, 3, layout.List.X + 4, layout.List.Y + 2));
        Assert.Equal(1, SplashDiskPrompt.RowAt(layout, 3, layout.List.Right - 2, layout.List.Y + layout.RowHeight + layout.RowGap + 2));
        Assert.Equal(-1, SplashDiskPrompt.RowAt(layout, 3, layout.List.X - 1, layout.List.Y + 2));
        Assert.Equal(-1, SplashDiskPrompt.RowAt(layout, 3, layout.List.X + 4, layout.List.Y + layout.RowHeight));
    }
}
