using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SlintDemo.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();

    private void OnSlintLoaded(object sender, RoutedEventArgs e)
    {
        // SlintPanel creates its host in its own Loaded handler, which runs first.
        if (Slint.Host is { } host)
            host.Submitted += name => Submissions.Items.Add(name);
    }

    private void OnNameChanged(object sender, TextChangedEventArgs e) => Slint.Host?.SetName(NameBox.Text);
}
