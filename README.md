# SSH Tunnel Config Editor (`SSH_Tunnel_Config_Editor.ps1`)

## 1. Purpose and scope

This PowerShell script provides a graphical **SSH tunnel configuration editor** for a Windows service or application whose settings are stored in an XML/`.config` file (typically a .NET `app.config`/`web.config`).

The script:

- Loads the XML configuration file.
- Automatically creates a timestamped backup of the original file.
- Reads and edits a specific set of **`appSettings` keys**:
  - `SshHost`
  - `SshPort`
  - `SshUser`
  - `MaxTunnels`
  - `HeartbeatIntervalMs`
  - `Tunnels`
- Offers a WPF-based GUI (dark themed) to view and modify:
  - **Basic SSH parameters** (host, port, user, etc.).
  - **A list of TCP tunnels**, each defined as:
    - `RemoteHost`
    - `RemotePort`
    - `LocalHost`
    - `LocalPort`
- Validates user input and saves the updated configuration back to the same file.

The overall goal is to allow non-technical or semi-technical users to safely modify SSH tunnel settings without manually editing XML.

---

## 2. Runtime requirements

### 2.1 PowerShell and .NET

The script is designed for **Windows PowerShell** (not PowerShell Core) and uses WPF:

- PowerShell 5.1 (or equivalent on Windows).
- .NET assemblies:
  - `PresentationFramework`
  - `PresentationCore`
  - `System.Xml`
  - `System.Windows.Forms` (for the OpenFileDialog)

These assemblies are loaded at startup using:

```powershell
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Xml
Add-Type -AssemblyName System.Windows.Forms
```

### 2.2 Configuration file structure

The script expects an XML configuration file with at least an `appSettings` section, e.g.:

```xml
<configuration>
  <appSettings>
    <add key="SshHost" value="ssh.example.com" />
    <add key="SshPort" value="22" />
    <add key="SshUser" value="myuser" />
    <add key="MaxTunnels" value="5" />
    <add key="HeartbeatIntervalMs" value="30000" />
    <add key="Tunnels" value="10.0.0.1:3389:127.0.0.1:3389,10.0.0.2:22:127.0.0.1:2222" />
  </appSettings>
</configuration>
```

The `Tunnels` key is a **comma-separated list** of tunnels; each tunnel is encoded as:

```text
RemoteHost:RemotePort:LocalHost:LocalPort
```

---

## 3. Launching the script

### 3.1 With an explicit configuration path

```powershell
.\BACKUP_GUI_CONFIGURATOR.ps1 -ConfigPath "C:\Path\To\MyService.config"
```

### 3.2 Without parameters (file chooser)

If `-ConfigPath` is not provided or the file does not exist, the script opens a standard **Open File** dialog:

- Filter: `Config XML (*.config;*.xml)|*.config;*.xml|All files (*.*)|*.*`
- Title: **"Select configuration file"**

If the user cancels the dialog, the script writes a message to the console and exits gracefully.

If the final file still does not exist, a **MessageBox** is shown:

- Title: *Error*
- Icon: *Error*
- Text: “Configuration file not found: \<path\>”

Then the script terminates.

---

## 4. Detailed execution flow

### 4.1 Parameter handling and safety checks

1. **Read `ConfigPath` parameter**.
2. If missing or invalid:
   - Show `OpenFileDialog` to let the user select a config file.
3. If, after this, the file still does **not** exist:
   - Show an error `MessageBox` and exit.

This ensures there is always a valid, existing file before any edit or backup occurs.

### 4.2 Automatic backup

Before modifying the configuration, the script creates a **timestamped backup**:

```powershell
$backupPath = "$ConfigPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $ConfigPath $backupPath -Force
```

This ensures:

- Non-destructive behavior by default.
- The previous configuration can always be restored manually.

### 4.3 Loading and accessor helpers

The configuration is loaded into a global XML object:

```powershell
[xml]$global:ConfigXml = Get-Content $ConfigPath
```

Helper functions encapsulate access to `appSettings`:

- `Get-AppSettingNode([string]$Key)`  
  Returns the `<add>` element for the specified key, or `$null` if not found.

- `Get-AppSettingValue([string]$Key)`  
  Returns the `value` attribute of the `<add>` element.

- `Set-AppSettingValue([string]$Key, [string]$Value)`  
  - If the `<add>` node does not exist, it creates one and appends it to `configuration/appSettings`.
  - If it exists, it updates the `value` attribute.

This abstraction keeps XML manipulation consistent and reduces duplication.

---

## 5. Tunnels parsing and serialization

### 5.1 Parsing the `Tunnels` string

The function `Parse-Tunnels`:

1. Reads the `Tunnels` string from `appSettings`.
2. Splits it by comma (`","`) to get individual tunnel segments.
3. For each segment:
   - Splits on colon (`":"`).
   - Expects **exactly 4 parts**:
     - `RemoteHost`
     - `RemotePort`
     - `LocalHost`
     - `LocalPort`
   - Builds a `[PSCustomObject]` with those fields (ports cast to `[int]`).
4. Adds the object to a `System.Collections.ObjectModel.ObservableCollection`-like list.
5. Returns the list.

This list is stored globally as:

```powershell
$global:TunnelsList = Parse-Tunnels
```

### 5.2 Serializing tunnels back to a string

The function `Serialize-Tunnels` performs the inverse:

1. Iterates over a collection of tunnel objects.
2. For each tunnel, formats it as:

   ```powershell
   "{0}:{1}:{2}:{3}" -f $t.RemoteHost, $t.RemotePort, $t.LocalHost, $t.LocalPort
   ```

3. Joins all segments with commas:

   ```powershell
   $segments -join ","
   ```

4. Returns the string so it can be written into the `Tunnels` appSetting.

---

## 6. Graphical user interface (WPF)

### 6.1 XAML-based layout

The script defines a full WPF window in an embedded XAML string, then loads it via:

```powershell
$window = [System.Windows.Markup.XamlReader]::Load(
    (New-Object System.Xml.XmlNodeReader $xamlXml)
)
```

Key properties:

- Title: **"SSH Config Editor"**
- Size: 840×600
- Startup location: centered on screen.
- Dark theme:
  - Background: `#1E1E1E`
  - Foreground: `#F2F2F2`
  - Controls: dark backgrounds with accent border for focus (`#3399FF`)
- Font: `Segoe UI`, size 12.

The main grid is divided vertically into:

1. **Header** (row 0)
2. **Basic parameters** (row 1)
3. **Tunnels panel** (row 2, expandable)
4. **Footer commands** (row 3)

### 6.2 Header

- A bold title: **"SSH Tunnel Configurator"**
- A small text block `txtConfigPath` that shows the path of the configuration file currently loaded.

This gives immediate context about which file the user is editing.

### 6.3 Basic parameters (SSH)

Contained in a rounded `Border` with a grid of labels and text boxes:

Fields:

1. `SshHost`  
   - Label: "SSH Host"  
   - TextBox: `txtSshHost`  
   - Tooltip explaining typical values (e.g. host or IP of the SSH server).

2. `SshPort`  
   - Label: "SSH Port"  
   - TextBox: `txtSshPort`  
   - Expected to be numeric; validated on save.

3. `SshUser`  
   - Label: "SSH User"  
   - TextBox: `txtSshUser`  

4. `MaxTunnels`  
   - Label: "Max Tunnels"  
   - TextBox: `txtMaxTunnels`  
   - Validated as numeric.

5. `HeartbeatIntervalMs`  
   - Label: "Heartbeat Interval (ms)"  
   - TextBox: `txtHeartbeat`  
   - Validated as numeric.

Each TextBox has:

- Keyboard `TabIndex` set (for logical navigation order).
- A descriptive `ToolTip` explaining the purpose of the field.

### 6.4 Tunnels list and editor

The tunnels section is visually separated in another bordered panel and split into two main areas:

1. **Left side – List of tunnels**
   - `ListBox` named `lstTunnels`.
   - Each entry is a formatted string:

     ```text
     [index] RemoteHost:RemotePort  ->  LocalHost:LocalPort
     ```

   - This gives a quick, readable summary of existing tunnels.

2. **Right side – Editor for a single tunnel**
   - Four labeled fields:
     - `Remote Host` (`txtRemoteHost`)
     - `Remote Port` (`txtRemotePort`)
     - `Local Host` (`txtLocalHost`)
     - `Local Port` (`txtLocalPort`)
   - Each field has margin, label, and tooltip text (e.g., “Remote host the tunnel connects to (e.g. 192.168.1.10)”).
   - Underneath, three buttons:
     - `Add` (`btnAddTunnel`)
     - `Update` (`btnEditTunnel`)
     - `Remove` (`btnRemoveTunnel`)

The layout makes it obvious how to:

- Select an existing tunnel.
- Edit its parameters.
- Add a new tunnel or remove an existing one.

### 6.5 Footer (Save/Close)

In the bottom area of the window:

- `Save` button (`btnSave`) aligned to the right.
- `Close` button (`btnClose`) next to it.

This follows common Windows UI conventions (primary action on the right, alternate on the left).

---

## 7. Event handlers and behavior

After loading the XAML, the script retrieves references to all named controls using:

```powershell
$txtSshHost     = $window.FindName("txtSshHost")
$txtSshPort     = $window.FindName("txtSshPort")
...
$btnSave        = $window.FindName("btnSave")
$btnClose       = $window.FindName("btnClose")
```

### 7.1 Initialization

- The SSH fields (`txtSshHost`, `txtSshPort`, `txtSshUser`, `txtMaxTunnels`, `txtHeartbeat`) are initialized from `Get-AppSettingValue`.
- `$global:TunnelsList` is set using `Parse-Tunnels`.
- `Refresh-TunnelsListBox` populates `lstTunnels` based on `$global:TunnelsList`.

### 7.2 Tunnels list refresh

`Refresh-TunnelsListBox`:

1. Clears the items in `lstTunnels`.
2. Iterates over `$global:TunnelsList` with an index counter.
3. For each tunnel, builds the display string and adds it to the list.

This function is called:

- Once at startup.
- After every add, update, or remove operation.

### 7.3 Selecting a tunnel

When `lstTunnels.SelectionChanged` fires:

- The script reads `SelectedIndex`.
- If a valid index is selected:
  - Reads the corresponding object from `$global:TunnelsList`.
  - Fills `txtRemoteHost`, `txtRemotePort`, `txtLocalHost`, and `txtLocalPort` with that tunnel’s data.

This gives the user immediate editable access to the selected tunnel.

### 7.4 Tunnel fields validation

`Validate-TunnelFields` enforces basic correctness:

- Checks that none of the four tunnel fields are null/empty/whitespace.
  - If any are, shows an **Error** `MessageBox` with text like:
    - “Fill in all tunnel fields.”
- Checks that `RemotePort` and `LocalPort` can be parsed as integers.
  - If not, shows an **Error** `MessageBox`:
    - “RemotePort and LocalPort must be numeric.”

If validation fails, it returns `$false` and the calling button handler aborts.

### 7.5 Adding a tunnel

`$btnAddTunnel.Add_Click` handler:

1. Calls `Validate-TunnelFields`. If it returns `$false`, exits.
2. Creates a new `[PSCustomObject]` with the four properties.
3. Adds it to `$global:TunnelsList`.
4. Calls `Refresh-TunnelsListBox`.

No destructive changes occur to existing tunnels.

### 7.6 Updating a tunnel

`$btnEditTunnel.Add_Click` handler:

1. Reads the current `SelectedIndex` from `lstTunnels`.
2. If no item is selected:
   - Shows an **Information** `MessageBox`:
     - “Select a tunnel to update.”
   - Returns.
3. Calls `Validate-TunnelFields`. If false, returns.
4. Updates the corresponding object in `$global:TunnelsList` with the values from the text boxes.
5. Calls `Refresh-TunnelsListBox`.

This approach guarantees that updates are intentional and well-validated.

### 7.7 Removing a tunnel

`$btnRemoveTunnel.Add_Click` handler:

1. Reads the current `SelectedIndex` from `lstTunnels`.
2. If no item is selected:
   - Shows an **Information** `MessageBox`:
     - “Select a tunnel to remove.”
   - Returns.
3. Shows a **confirmation** `MessageBox` with *Yes/No*:
   - “Remove the selected tunnel?”
4. Only if the user clicks **Yes**:
   - Removes the tunnel at that index from `$global:TunnelsList`.
   - Calls `Refresh-TunnelsListBox`.
   - Clears the tunnel editor text fields.

This avoids accidental removals and gives the user control.

### 7.8 Saving configuration

`$btnSave.Add_Click` handler:

1. Validates numeric fields:

   - `SshPort`
   - `MaxTunnels`
   - `HeartbeatIntervalMs`

   For each field:
   - Tries to cast its `.Text` to `[int]`.
   - If casting fails, shows an **Error** `MessageBox` explaining which field must be numeric, then returns.

2. If all checks pass:
   - Calls `Set-AppSettingValue` for each of the five basic keys.
   - Calls `Serialize-Tunnels` on `$global:TunnelsList` to build the tunnels string.
   - Stores it via `Set-AppSettingValue -Key "Tunnels" -Value $tunnelsValue`.
   - Saves the XML to disk:

     ```powershell
     $ConfigXml.Save($ConfigPath)
     ```

3. Shows a final **Information** `MessageBox`:

   - Title: `"Saved"`
   - Text: `"Configuration successfully saved to:\n<ConfigPath>"`

The user thus receives explicit confirmation that the new configuration has been persisted.

### 7.9 Closing the window

`$btnClose.Add_Click` simply closes the WPF window:

```powershell
$window.Close()
```

The script ends when the dialog is closed:

```powershell
$null = $window.ShowDialog()
```

---

## 8. Human–machine interaction (HMI / IUM) guidelines implemented

Although the script does not explicitly reference a formal HMI standard, its design follows several **good Human–Machine Interaction (HMI / IUM) practices**.

### 8.1 Visibility of system status

- The **current configuration file** path is always visible in the header (`txtConfigPath`).
- After saving, an **explicit message** confirms success and shows the target path.
- Errors (e.g., missing file, invalid numeric field) are presented via modal `MessageBox` dialogs, making them impossible to miss.

### 8.2 Safety and non-destructive operations

- An **automatic timestamped backup** is created before any change is applied.
- Tunnel removal is protected by a **Yes/No confirmation dialog**.
- Field validation prevents malformed numeric values from being saved.
- The application exits gracefully if no valid configuration file is selected, avoiding unexpected side effects.

### 8.3 Error prevention and clear feedback

- Validation (`Validate-TunnelFields`, numeric checks on Save) prevents common input mistakes instead of allowing them and failing later.
- Each error message:
  - Clearly indicates the problem (e.g., “SshPort must be numeric.”).
  - Uses an error icon to visually emphasize the severity.

This reduces the cognitive load required to understand what went wrong and how to fix it.

### 8.4 Consistency and standards

- Labels and fields follow a **consistent naming and layout**:
  - Label on the left, TextBox on the right.
  - Same visual style (dark background, light text, accent borders).
- Numeric fields are clearly labeled (e.g., “Heartbeat Interval (ms)”).
- The **Save / Close** button placement follows common Windows conventions, improving predictability for users.

### 8.5 Minimizing user memory load

- Existing tunnel definitions are always visible in a list with a **human-readable format**.
- Selecting a tunnel automatically fills the editor fields, so the user does not need to recall or retype parameters from memory.
- Tooltips remind users of each field’s purpose (e.g., what `Remote Host` represents).

This aligns with IUM principles that recommend keeping critical information in the interface rather than in the user’s memory.

### 8.6 User control and freedom

- Users can:
  - Add, update, or remove tunnels in any order.
  - Cancel changes at any time by simply closing the window without saving.
- Destructive actions (tunnel removal) require confirmation.
- The automatic backup supports manual rollback outside the application if necessary, reinforcing user control.

### 8.7 Learnability and clarity

- The UI uses **plain, domain-relevant language** (“SSH Host”, “SSH User”, “Remote Host”, etc.).
- The window is divided into logical sections:
  - Basic SSH settings.
  - Tunnel list and tunnel editor.
  - Global commands (Save / Close).
- This structure supports progressive discovery: users can first adjust high-level SSH settings, then move on to individual tunnels.

### 8.8 Accessibility and keyboard navigation

- `TabIndex` and `KeyboardNavigation.TabNavigation="Cycle"` are configured to let users move logically through fields with the keyboard.
- High-contrast colors (light text on dark background) improve readability in dim environments, often typical of operations/control rooms.

---

## 9. Extensibility notes

Developers can extend or adapt the script by:

- Adding new `appSettings` keys and mapping them to additional GUI controls.
- Modifying the `Tunnels` encoding scheme if more fields are needed.
- Hooking the editor into deployment or service restart scripts (after save).

Any such extensions should preserve the same HMI/IUM principles:

- Keep automatic backups.
- Validate user input.
- Provide clear, explicit feedback for errors and successful operations.
- Use confirmation dialogs for destructive or risky operations.

---

## 10. Summary

`BACKUP_GUI_CONFIGURATOR.ps1` is a self-contained **SSH tunnel configuration editor** built on PowerShell and WPF. It provides:

- Safe, user-friendly editing of SSH connection and tunnel settings stored in an XML/`.config` file.
- Automatic backup and validation to prevent configuration loss and malformed data.
- A GUI that follows key Human–Machine Interaction (IUM) guidelines: visibility of system status, error prevention, clear feedback, consistency, and user control.

This makes it suitable as an operator-facing tool in environments where SSH-based tunneling is managed centrally but needs occasional, controlled adjustments by human users.


---

# 11. Authoritative Academic and International Sources for HMI / IUM Guidelines

The design principles applied in this script are based on internationally recognized standards and academic references in Human–Machine Interaction (HMI), Human–Computer Interaction (HCI), and usability engineering.

## 11.1 Nielsen’s Usability Heuristics
- Nielsen, J. (1994, updated 2020). *10 Usability Heuristics for User Interface Design*. Nielsen Norman Group.

## 11.2 ISO 9241 – Ergonomics of Human–System Interaction
- ISO 9241-110:2020 – Interaction Principles  
- ISO 9241-112:2017 – Information Presentation  
- ISO 9241-171:2008 – Guidance on Software Accessibility

## 11.3 Shneiderman’s Eight Golden Rules
- Shneiderman, B., Plaisant, C. (2010). *Designing the User Interface: Strategies for Effective Human–Computer Interaction*. MIT Press / Addison‑Wesley.

## 11.4 Norman’s Design Principles
- Norman, D. (2013). *The Design of Everyday Things*. MIT Press.

## 11.5 HFES (Human Factors and Ergonomics Society) Standards
- ANSI/HFES 100‑2007 – *Human Factors Engineering of Computer Workstations*.

## 11.6 IEC 62366 — Risk‑based Usability Engineering
- IEC 62366‑1:2015 – *Application of usability engineering to medical devices*.  
  (Referenced for safety‑critical design patterns such as confirmations, safe defaults, and error prevention.)

## 11.7 ISO/IEC 25010 — Software Quality Model
- ISO/IEC 25010:2011 – *System and Software Quality Requirements and Evaluation (SQuaRE)*.

## 11.8 W3C WCAG 2.1 Accessibility Standards
- W3C (2018). *Web Content Accessibility Guidelines (WCAG) 2.1*.  
  (Relevant for contrast ratios, keyboard navigation, and accessible UI components.)

---
