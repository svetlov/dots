# Windows Configuration Notes

ASUS ROG with AMD Ryzen AI 9 HX 370 + RTX 5080 Laptop GPU, Windows 11 Home.

## Windows Hello Face — Login Disabled, In-Session Only

Face recognition is disabled on the lock/login screen but kept active for in-session authentication (1Password, UAC prompts, etc.).

**How:** Disable the Face credential provider in the login UI via registry. Apps like 1Password call the biometric framework directly (WinRT `UserConsentVerifier` / WebAuthn), bypassing credential providers.

```
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{8AF662BF-65A0-4D0A-A540-A338A999D36F}" /v Disabled /t REG_DWORD /d 1 /f
```

To re-enable face login:
```
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{8AF662BF-65A0-4D0A-A540-A338A999D36F}" /v Disabled /t REG_DWORD /d 0 /f
```

**GUID:** `{8AF662BF-65A0-4D0A-A540-A338A999D36F}` = Windows Hello Face credential provider.

## Other Configs

- [power-settings.md](power-settings.md) — Modern Standby, background services, fan noise fixes, USB selective suspend, standby battery drain
- [wslconfig](wslconfig) — WSL2 configuration
- [wezterm.lua](wezterm.lua) — WezTerm terminal config
- [spacedesk/](spacedesk/) — Spacedesk display driver config
- [scripts/](scripts/) — Power management scripts (deployed to `C:\ProgramData\PowerScripts\`)
