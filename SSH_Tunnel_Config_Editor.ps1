param(
    [string]$ConfigPath
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Xml

# If no config path is provided, ask the user via OpenFileDialog
if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Config XML (*.config;*.xml)|*.config;*.xml|All files (*.*)|*.*"
    $ofd.Title  = "Select configuration file"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ConfigPath = $ofd.FileName
    } else {
        Write-Host "No file selected. Exiting."
        exit
    }
}

if (-not (Test-Path $ConfigPath)) {
    [System.Windows.MessageBox]::Show(
        "Configuration file not found:`n$ConfigPath",
        "Error",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit
}

# Automatic backup
$backupPath = "$ConfigPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $ConfigPath $backupPath -Force

# Load XML configuration
[xml]$global:ConfigXml = Get-Content $ConfigPath

function Get-AppSettingNode {
    param([string]$Key)
    return $ConfigXml.configuration.appSettings.add | Where-Object { $_.key -eq $Key }
}

function Get-AppSettingValue {
    param([string]$Key)
    $node = Get-AppSettingNode -Key $Key
    return $node.value
}

function Set-AppSettingValue {
    param([string]$Key,[string]$Value)
    $node = Get-AppSettingNode -Key $Key
    if ($null -eq $node) {
        $node = $ConfigXml.CreateElement("add")
        $node.SetAttribute("key",$Key)   | Out-Null
        $node.SetAttribute("value",$Value) | Out-Null
        $ConfigXml.configuration.appSettings.AppendChild($node) | Out-Null
    } else {
        $node.value = $Value
    }
}

function Parse-Tunnels {
    $value = Get-AppSettingValue -Key "Tunnels"
    $list  = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    if ([string]::IsNullOrWhiteSpace($value)) { return $list }

    $entries = $value.Split(",",[System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($e in $entries) {
        $parts = $e.Split(":")
        if ($parts.Count -eq 4) {
            $obj = [PSCustomObject]@{
                RemoteHost = $parts[0]
                RemotePort = [int]$parts[1]
                LocalHost  = $parts[2]
                LocalPort  = [int]$parts[3]
            }
            $list.Add($obj)
        }
    }
    return $list
}

function Serialize-Tunnels {
    param([System.Collections.IEnumerable]$Tunnels)
    $segments = @()
    foreach ($t in $Tunnels) {
        $segments += ("{0}:{1}:{2}:{3}" -f $t.RemoteHost,$t.RemotePort,$t.LocalHost,$t.LocalPort)
    }
    return ($segments -join ",")
}

# XAML UI
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SSH Config Editor" Height="600" Width="840"
        WindowStartupLocation="CenterScreen"
        Background="#1E1E1E" Foreground="#F2F2F2"
        FontFamily="Segoe UI" FontSize="12"
        KeyboardNavigation.TabNavigation="Cycle">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <StackPanel Grid.Row="0" Orientation="Vertical" Margin="0,0,0,10">
            <TextBlock Text="SSH Tunnel Configurator" FontSize="20" FontWeight="Bold" Margin="0,0,0,2"/>
            <TextBlock x:Name="txtConfigPath" Text="Config file:" FontSize="10" Foreground="#BBBBBB"/>
        </StackPanel>

        <!-- BASIC PARAMETERS -->
        <Border Grid.Row="1" CornerRadius="6" Padding="10" Background="#252526" Margin="0,0,0,10">
            <Grid Grid.IsSharedSizeScope="True">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" SharedSizeGroup="Label"/>
                    <ColumnDefinition Width="2*"/>
                    <ColumnDefinition Width="20"/>
                    <ColumnDefinition Width="Auto" SharedSizeGroup="Label"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Row 1: SSH Host / SSH Port -->
                <TextBlock Grid.Row="0" Grid.Column="0"
                           Text="SSH Host" Margin="0,0,6,6" VerticalAlignment="Center"/>
                <TextBox Grid.Row="0" Grid.Column="1" x:Name="txtSshHost"
                         Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                         TabIndex="0"
                         ToolTip="Host name or IP address of the SSH server."/>

                <TextBlock Grid.Row="0" Grid.Column="3"
                           Text="SSH Port" Margin="0,0,6,6" VerticalAlignment="Center"/>
                <TextBox Grid.Row="0" Grid.Column="4" x:Name="txtSshPort"
                         Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                         TabIndex="1"
                         ToolTip="TCP port of the SSH server (numeric)."/>

                <!-- Row 2: SSH User / Max Tunnels -->
                <TextBlock Grid.Row="1" Grid.Column="0"
                           Text="SSH User" Margin="0,0,6,6" VerticalAlignment="Center"/>
                <TextBox Grid.Row="1" Grid.Column="1" x:Name="txtSshUser"
                         Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                         TabIndex="2"
                         ToolTip="User name used to authenticate to the SSH server."/>

                <TextBlock Grid.Row="1" Grid.Column="3"
                           Text="Max Tunnels" Margin="0,0,6,6" VerticalAlignment="Center"/>
                <TextBox Grid.Row="1" Grid.Column="4" x:Name="txtMaxTunnels"
                         Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                         TabIndex="3"
                         ToolTip="Maximum number of tunnels the service can open (numeric)."/>

                <!-- Row 3: Heartbeat -->
                <TextBlock Grid.Row="2" Grid.Column="0"
                           Text="Heartbeat Interval (ms)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                <TextBox Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="4" x:Name="txtHeartbeat"
                         Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF"
                         TabIndex="4"
                         ToolTip="Heartbeat interval to the server in milliseconds (numeric)."/>
            </Grid>
        </Border>

        <!-- TUNNELS -->
        <Border Grid.Row="2" CornerRadius="6" Padding="10" Background="#252526" Margin="0,0,0,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="Tunnels" FontWeight="Bold" Margin="0,0,0,5" Foreground="#F2F2F2"/>

                <!-- Tunnels list -->
                <Border Grid.Row="1" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="4">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <ListBox x:Name="lstTunnels" Background="#252526" BorderThickness="0" Foreground="#E0E0E0"
                                 TabIndex="5"
                                 ToolTip="List of configured tunnels. Select one to edit.">
                            <ListBox.ItemContainerStyle>
                                <Style TargetType="ListBoxItem">
                                    <Setter Property="Margin" Value="2"/>
                                    <Setter Property="Padding" Value="4"/>
                                    <Setter Property="Background" Value="#2B2B3C"/>
                                    <Setter Property="Foreground" Value="#E0E0E0"/>
                                    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="ListBoxItem">
                                                <Border x:Name="Bd"
                                                        Background="{TemplateBinding Background}"
                                                        CornerRadius="3">
                                                    <ContentPresenter Margin="4"
                                                                      HorizontalAlignment="Stretch"
                                                                      VerticalAlignment="Center"
                                                                      RecognizesAccessKey="True"/>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsSelected" Value="True">
                                                        <Setter TargetName="Bd" Property="Background" Value="#0E639C"/>
                                                        <Setter Property="Foreground" Value="#FFFFFF"/>
                                                    </Trigger>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="Bd" Property="Background" Value="#3E4451"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </ListBox.ItemContainerStyle>
                        </ListBox>
                    </ScrollViewer>
                </Border>

                <!-- Tunnel editor -->
                <Grid Grid.Row="2" Margin="0,10,0,0" Grid.IsSharedSizeScope="True">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" SharedSizeGroup="TunnelLabel"/>
                        <ColumnDefinition Width="2*"/>
                        <ColumnDefinition Width="20"/>
                        <ColumnDefinition Width="Auto" SharedSizeGroup="TunnelLabel"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Row 1 (Remote) -->
                    <TextBlock Grid.Row="0" Grid.Column="0"
                               Text="Remote Host" Margin="0,0,6,6" VerticalAlignment="Center"/>
                    <TextBox Grid.Row="0" Grid.Column="1" x:Name="txtRemoteHost"
                             Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                             TabIndex="6"
                             ToolTip="Remote host the tunnel connects to (e.g. 192.168.1.10)."/>

                    <TextBlock Grid.Row="0" Grid.Column="3"
                               Text="Remote Port" Margin="0,0,6,6" VerticalAlignment="Center"/>
                    <TextBox Grid.Row="0" Grid.Column="4" x:Name="txtRemotePort"
                             Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF" Margin="0,0,0,6"
                             TabIndex="7"
                             ToolTip="Remote port to connect to (numeric)."/>

                    <!-- Row 2 (Local) -->
                    <TextBlock Grid.Row="1" Grid.Column="0"
                               Text="Local Host" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBox Grid.Row="1" Grid.Column="1" x:Name="txtLocalHost"
                             Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF"
                             TabIndex="8"
                             ToolTip="Local host where the tunnel is exposed (e.g. 127.0.0.1)."/>

                    <TextBlock Grid.Row="1" Grid.Column="3"
                               Text="Local Port" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBox Grid.Row="1" Grid.Column="4" x:Name="txtLocalPort"
                             Background="#2B2B3C" Foreground="#F2F2F2" BorderBrush="#3399FF"
                             TabIndex="9"
                             ToolTip="Local port for the tunnel (numeric)."/>
                </Grid>

                <!-- Tunnel buttons -->
                <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,6,0,0">
                    <Button x:Name="btnAddTunnel" Content="Add" Width="90" Margin="0,0,5,0"
                            Background="#007ACC" BorderBrush="#007ACC"
                            TabIndex="10"
                            ToolTip="Add a new tunnel with the specified parameters."/>
                    <Button x:Name="btnEditTunnel" Content="Update" Width="90" Margin="0,0,5,0"
                            Background="#007ACC" BorderBrush="#007ACC"
                            TabIndex="11"
                            ToolTip="Update the selected tunnel with the specified parameters."/>
                    <Button x:Name="btnRemoveTunnel" Content="Remove" Width="90"
                            Background="#CC3300" BorderBrush="#CC3300"
                            TabIndex="12"
                            ToolTip="Remove the selected tunnel from the list."/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Bottom: backup info on the left, buttons on the right -->
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock x:Name="txtBackupInfo"
                       Grid.Column="0"
                       Text="Backup created:"
                       VerticalAlignment="Center"
                       Foreground="#BBBBBB" FontSize="10"
                       Margin="0,0,10,0"/>

            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="btnSave" Content="_Save" Width="100" Margin="0,0,5,0"
                        Background="#0E7A0D" BorderBrush="#0E7A0D"
                        IsDefault="True"
                        TabIndex="13"
                        ToolTip="Save the configuration to the selected file. (Alt+S)"/>
                <Button x:Name="btnClose" Content="_Close" Width="80"
                        Background="#444444" BorderBrush="#444444"
                        IsCancel="True"
                        TabIndex="14"
                        ToolTip="Close the editor window. (Alt+C)"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

# Load XAML window
try {
    $xmlReader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window    = [Windows.Markup.XamlReader]::Load($xmlReader)
} catch {
    Write-Error "Error parsing XAML: $_"
    exit
}

if (-not $window) {
    Write-Error "Unable to create WPF window."
    exit
}

# Dynamic header/footer labels
$txtConfigPath = $window.FindName("txtConfigPath")
$txtBackupInfo = $window.FindName("txtBackupInfo")
if ($txtConfigPath) { $txtConfigPath.Text = "Config file: $ConfigPath" }
if ($txtBackupInfo) { $txtBackupInfo.Text = "Backup created: $backupPath" }

# Look up other controls
$txtSshHost      = $window.FindName("txtSshHost")
$txtSshPort      = $window.FindName("txtSshPort")
$txtSshUser      = $window.FindName("txtSshUser")
$txtMaxTunnels   = $window.FindName("txtMaxTunnels")
$txtHeartbeat    = $window.FindName("txtHeartbeat")
$lstTunnels      = $window.FindName("lstTunnels")
$txtRemoteHost   = $window.FindName("txtRemoteHost")

$txtRemoteHost.IsEnabled = $false
# or:
# $txtRemoteHost.IsReadOnly = $true

$txtRemotePort   = $window.FindName("txtRemotePort")
$txtLocalHost    = $window.FindName("txtLocalHost")
$txtLocalPort    = $window.FindName("txtLocalPort")
$btnAddTunnel    = $window.FindName("btnAddTunnel")
$btnEditTunnel   = $window.FindName("btnEditTunnel")
$btnRemoveTunnel = $window.FindName("btnRemoveTunnel")
$btnSave         = $window.FindName("btnSave")
$btnClose        = $window.FindName("btnClose")

# Initial values
$txtSshHost.Text    = Get-AppSettingValue -Key "SshHost"
$txtSshPort.Text    = Get-AppSettingValue -Key "SshPort"
$txtSshUser.Text    = Get-AppSettingValue -Key "SshUser"
$txtMaxTunnels.Text = Get-AppSettingValue -Key "MaxTunnels"
$txtHeartbeat.Text  = Get-AppSettingValue -Key "HeartbeatIntervalMs"

# Tunnels in memory
$global:TunnelsList = Parse-Tunnels

function Refresh-TunnelsListBox {
    $lstTunnels.Items.Clear()
    $index = 0
    foreach ($t in $global:TunnelsList) {
        $display = "[{0}] {1}:{2}  ->  {3}:{4}" -f $index,$t.RemoteHost,$t.RemotePort,$t.LocalHost,$t.LocalPort
        [void]$lstTunnels.Items.Add($display)
        $index++
    }
}
Refresh-TunnelsListBox

# When a tunnel is selected, populate the editor fields
$lstTunnels.Add_SelectionChanged({
    $idx = $lstTunnels.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $global:TunnelsList.Count) {
        $t = $global:TunnelsList[$idx]
        $txtRemoteHost.Text = $t.RemoteHost
        $txtRemotePort.Text = $t.RemotePort.ToString()
        $txtLocalHost.Text  = $t.LocalHost
        $txtLocalPort.Text  = $t.LocalPort.ToString()
    }
})

function Validate-TunnelFields {
    if ([string]::IsNullOrWhiteSpace($txtRemoteHost.Text) -or
        [string]::IsNullOrWhiteSpace($txtRemotePort.Text) -or
        [string]::IsNullOrWhiteSpace($txtLocalHost.Text)  -or
        [string]::IsNullOrWhiteSpace($txtLocalPort.Text)) {

        [System.Windows.MessageBox]::Show(
            "Fill in all tunnel fields.",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return $false
    }

    if (-not ($txtRemotePort.Text -as [int]) -or -not ($txtLocalPort.Text -as [int])) {
        [System.Windows.MessageBox]::Show(
            "RemotePort and LocalPort must be numeric.",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return $false
    }
    return $true
}

# Tunnel buttons
$btnAddTunnel.Add_Click({
    if (-not (Validate-TunnelFields)) { return }

    $new = [PSCustomObject]@{
        RemoteHost = $txtRemoteHost.Text
        RemotePort = [int]$txtRemotePort.Text
        LocalHost  = $txtLocalHost.Text
        LocalPort  = [int]$txtLocalPort.Text
    }

    $global:TunnelsList.Add($new)
    Refresh-TunnelsListBox
})

$btnEditTunnel.Add_Click({
    $idx = $lstTunnels.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $global:TunnelsList.Count) {
        [System.Windows.MessageBox]::Show(
            "Select a tunnel to update.",
            "Info",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
        return
    }

    if (-not (Validate-TunnelFields)) { return }

    $global:TunnelsList[$idx].RemoteHost = $txtRemoteHost.Text
    $global:TunnelsList[$idx].RemotePort = [int]$txtRemotePort.Text
    $global:TunnelsList[$idx].LocalHost  = $txtLocalHost.Text
    $global:TunnelsList[$idx].LocalPort  = [int]$txtLocalPort.Text

    Refresh-TunnelsListBox
})

$btnRemoveTunnel.Add_Click({
    $idx = $lstTunnels.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $global:TunnelsList.Count) {
        [System.Windows.MessageBox]::Show(
            "Select a tunnel to remove.",
            "Info",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
        return
    }
    $res = [System.Windows.MessageBox]::Show(
        "Remove the selected tunnel?",
        "Confirm",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
        $global:TunnelsList.RemoveAt($idx)
        Refresh-TunnelsListBox
        $txtRemoteHost.Clear()
        $txtRemotePort.Clear()
        $txtLocalHost.Clear()
        $txtLocalPort.Clear()
    }
})

# Save configuration
$btnSave.Add_Click({
    if (-not ($txtSshPort.Text -as [int])) {
        [System.Windows.MessageBox]::Show("SshPort must be numeric.","Error",
            [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }
    if (-not ($txtMaxTunnels.Text -as [int])) {
        [System.Windows.MessageBox]::Show("MaxTunnels must be numeric.","Error",
            [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }
    if (-not ($txtHeartbeat.Text -as [int])) {
        [System.Windows.MessageBox]::Show("HeartbeatIntervalMs must be numeric.","Error",
            [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    Set-AppSettingValue -Key "SshHost"             -Value $txtSshHost.Text
    Set-AppSettingValue -Key "SshPort"             -Value $txtSshPort.Text
    Set-AppSettingValue -Key "SshUser"             -Value $txtSshUser.Text
    Set-AppSettingValue -Key "MaxTunnels"          -Value $txtMaxTunnels.Text
    Set-AppSettingValue -Key "HeartbeatIntervalMs" -Value $txtHeartbeat.Text

    $tunnelsValue = Serialize-Tunnels -Tunnels $global:TunnelsList
    Set-AppSettingValue -Key "Tunnels" -Value $tunnelsValue

    $ConfigXml.Save($ConfigPath)

    [System.Windows.MessageBox]::Show(
        "Configuration successfully saved to:`n$ConfigPath",
        "Saved",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
})

$btnClose.Add_Click({
    $window.Close() | Out-Null
})

# Show window
$null = $window.ShowDialog()

