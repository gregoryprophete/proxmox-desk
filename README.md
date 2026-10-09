# Proxmox Desk

A Flutter client for one Proxmox VE server. Runs on Windows today; the same code builds for iPad.

- **Web interface tab** – the full Proxmox web UI in its own window, signed in once and kept open.
- **Guests tab** – native list of VMs and containers with CPU, RAM, uptime, start, shut down, reboot, force stop, and a console button. Consoles have a full screen mode (the button in the title bar, or F11) that covers the whole display like a remote desktop session.
- **Settings tab** – server, token and accepted certificate.

The source was written without a Flutter toolchain to compile against, so expect to fix a small error or two on the first build. Send me the output of `flutter run` if anything fails.

## 1. Prerequisites (Windows 10)

1. Flutter SDK 3.24 or newer: https://docs.flutter.dev/get-started/install/windows
2. Visual Studio 2022 with the **Desktop development with C++** workload. In the installer's Individual components, also tick **C++ ATL for latest build tools** (the secure storage plugin needs it).
3. NuGet CLI on your PATH (the webview plugin needs it): `winget install Microsoft.NuGet`
4. Microsoft Edge WebView2 Runtime. Usually already present on Windows 10; if the app says it is missing, install the Evergreen runtime from Microsoft.

Run `flutter doctor` and clear anything it flags for Windows.

## 2. Build and run

This folder holds the app code only. Flutter generates the platform folders:

```
cd proxmox_desk
flutter create . --platforms=windows,ios --project-name proxmox_desk
flutter pub get
flutter run -d windows
```

`flutter create .` keeps the existing `lib/` and `pubspec.yaml`. For a standalone build: `flutter build windows`, then run `build\windows\x64\runner\Release\proxmox_desk.exe`.

## 3. Create an API token in Proxmox (for the Guests tab)

1. Datacenter > Permissions > API Tokens > Add. Pick your user, give the token a name such as `desk`, leave **Privilege Separation** ticked. Copy the secret; it is shown once.
2. Datacenter > Permissions > Add > API Token Permission. Path `/`, your new token, role `PVEVMAdmin`.

The token ID you enter in the app looks like `root@pam!desk`.

The token is optional. Without it the app is a plain wrapper around the web interface.

## 4. First launch

Enter the server address (the ZeroTier address works from anywhere, with ZeroTier running on the PC) and port 8006. The app shows the server's certificate fingerprint; compare it with the one in Proxmox under your node > System > Certificates, then choose Trust.

The console button opens Proxmox's own noVNC or terminal page. That page uses the web interface login, not the API token, so sign in once on the Web interface tab first. Proxmox ends that login after two hours.

## Security notes

- The token secret is kept in Windows Credential Manager (Keychain on iPad), not in a plain file.
- API calls only accept the exact certificate you approved. If the certificate changes, the app refuses to connect until you reconnect in Settings and approve the new one.
- The embedded web interface accepts a self-signed certificate for your configured server and port only.

## iPad later

Add to `ios/Runner/Info.plist` so iOS lets the app reach devices on your network:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Connects to your Proxmox server.</string>
```

Then build through Codemagic as with your other Flutter work. The layout switches to a bottom bar on narrow screens.

## Files

| File | Purpose |
| --- | --- |
| `lib/main.dart` | App start, navigation, settings tab |
| `lib/config.dart` | Saved server details and token storage |
| `lib/proxmox_api.dart` | Proxmox REST calls and certificate pinning |
| `lib/setup_screen.dart` | Connect screen |
| `lib/guests_screen.dart` | VM and container list with power controls |
| `lib/console_page.dart` | Guest console page with full screen mode |
| `lib/web_pane.dart` | Embedded web interface and consoles |
