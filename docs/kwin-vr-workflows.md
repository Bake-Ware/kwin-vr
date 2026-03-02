# kwin-vr Workflows

Flow charts for every known activation, deactivation, and error path in the kwin-vr
system. Both the custodian daemon and the KWin plugin are shown side-by-side where
they interact.

---

## 1. System Startup (Custodian)

The custodian starts automatically as a user systemd unit. It performs a synchronous
hardware scan before entering event-loop mode.

```mermaid
flowchart TD
    A([kwin-vr-custodian starts]) --> B[Load profiles from /etc/vr-profiles.d/]
    B --> C[Setup profile directory inotify watcher]
    C --> D[Start udev monitor\n drm + usb_device + hidraw]
    D --> E[Register D-Bus service\norg.kde.kwinvr.Custodian]
    E --> F[Setup plugin D-Bus watcher\norg.kde.kwinvr]
    F --> G[Setup runtime D-Bus watchers\nWiVRn etc.]
    G --> H[scanConnectors]
    H --> I{Any connector\nin SBS mode?}
    I -- yes --> J[activateProfile\nsee Flow 3]
    I -- no --> K[scanUsbDevices]
    K --> L{USB VR device\nfound?}
    L -- yes --> M[Send HID 2D init\nput device in desktop mode]
    M --> N([Enter event loop])
    L -- no --> N
    J --> N
```

---

## 2. Custodian Event Loop — Incoming Events

Once started, the custodian is entirely event-driven. Nothing polls.

```mermaid
flowchart TD
    EL([Event loop running])

    EL --> U1[udev: DRM change event]
    U1 --> U2{Has CONNECTOR_STATUS\nproperty?}
    U2 -- yes --> U3[drmConnectorChanged\nsee Flow 4]
    U2 -- no --> U4[drmRescanNeeded →\nscanConnectors\nsee Flow 4]

    EL --> U5[udev: USB device added]
    U5 --> U6[onUsbDeviceAdded\nsee Flow 6]

    EL --> U7[udev: USB device removed]
    U7 --> U8[onUsbDeviceRemoved\nlog only — DRM event\nwill deactivate VR]

    EL --> D1[D-Bus: plugin appeared]
    D1 --> D2[m_pluginAvailable = true\nRe-notify if already active]

    EL --> D3[D-Bus: plugin vanished]
    D3 --> D4[m_pluginAvailable = false\nIf m_pendingRuntimeStop:\nexecutePendingRuntimeStop]

    EL --> D5[D-Bus: WiVRn service appeared]
    D5 --> D6[onRuntimeServiceRegistered\nsee Flow 3]

    EL --> D7[D-Bus: WiVRn service vanished]
    D7 --> D8[onRuntimeServiceUnregistered\nIf active service profile:\ndeactivate]

    EL --> D9[D-Bus: vrStopped from plugin]
    D9 --> D10[executePendingRuntimeStop\nsee Flow 5]

    EL --> D11[D-Bus: manualActivate from plugin]
    D11 --> D12[Find Always-trigger profile\nactivateProfile]

    EL --> F1[inotify: profile dir changed]
    F1 --> F2[reloadProfiles\nsetupRuntimeWatcher]

    EL --> S1[FS watcher: Monado socket appeared]
    S1 --> S2[onMonadoSocketAppeared\nsee Flow 3]

    EL --> S3[systemd PropertiesChanged:\nunit ActiveState changed]
    S3 --> S4[onStartingUnitPropertiesChanged\nIf state == failed: abort activation]
```

---

## 3. VR Activation Flow (Custodian + Plugin)

Triggered by: SBS mode detected, WiVRn service appeared, or manual activate.

```mermaid
flowchart TD
    T([Trigger:\nSBS mode / WiVRn / manual]) --> P1[matchConnector / matchProfile]
    P1 --> P2{Profile matched?}
    P2 -- no --> END1([No action])
    P2 -- yes --> P3{Already active\nwith same or\nhigher priority?}
    P3 -- yes lower --> END1
    P3 -- yes higher --> P4[deactivateActive current\nsee Flow 5]
    P4 --> P5[activateProfile]
    P3 -- not active --> P5

    P5 --> H1[Send HID 3D init\nUSB command to glasses]
    H1 --> R1[startRuntime]

    R1 --> R2{Runtime is\nnone or empty?}
    R2 -- yes --> R3[notifyPluginActivate immediately]
    R2 -- no --> R4{Is Monado?}

    R4 -- yes --> M1{IPC socket\nexists?}
    M1 -- yes --> M2{isServiceActive\nAND isSocketLive?}
    M2 -- both true --> M3[Monado already running\nnotifyPluginActivate immediately]
    M2 -- either false --> M4[STALE SOCKET\nQFile::remove socket]
    M4 --> M5[Send StartUnit\nmonado.service\nasync with reply watcher]
    M1 -- no --> M5

    M5 --> M6[Watch XDG_RUNTIME_DIR\nfor socket to appear]
    M6 --> M7[LoadUnit → get unit path\nsubscribe PropertiesChanged\nfor failure detection]

    M7 --> W1{Event: socket\nappeared?}
    W1 -- yes --> W2{isSocketLive?}
    W2 -- no --> W1
    W2 -- yes --> W3[unsubscribeUnitStateChanges\ndestroy socket watcher]
    W3 --> R3

    W1 -- unit state\nbecomes failed --> W4[Abort activation\nclear m_active\nno runtime to stop]

    M5reply{StartUnit reply\nerror?} -- yes --> W4
    M5reply -- no --> W1

    R4 -- WiVRn --> V1[Wait for WiVRn\nD-Bus service\nonRuntimeServiceRegistered]
    V1 --> R3

    R3 --> K1[D-Bus async call:\nrequestActivateProfile\nprofileName + outputName]
```

### Plugin side of activation

```mermaid
flowchart TD
    K1([requestActivateProfile\nreceived]) --> K2[Look up profile by name]
    K2 --> K3[Look up output by name]
    K3 --> K4{Custodian\npresent?}
    K4 -- yes --> K5[Pre-set\nKWIN_FORCE_DESKTOP_OUTPUTS]
    K4 -- no --> K5
    K5 --> K6[activateForProfile\nprofile + output]
    K6 --> K7[Set m_activeProfile\nm_vrOutput]
    K7 --> K8[Set KWIN_FORCE_DESKTOP_OUTPUTS\nfor display-type profiles]
    K8 --> K9[Apply VR config dims\nwidth/height/refresh/scale]
    K9 --> K10{Runtime =\nmonado AND\nsocket missing?}
    K10 -- yes --> K11[systemctl start monado\nwait 3s QTimer\nsetVrActive only if still inactive]
    K10 -- no --> K12[setVrActive true]
    K11 --> K12
    K12 --> K13[Create QQmlApplicationEngine\nset graphicsApi Vulkan\nloadFromModule VR/Main]
    K13 --> K14{QML object\ncreated OK?}
    K14 -- no --> K15[stop — show error notification]
    K14 -- yes --> K16[Install windowAdded watcher\nsteer openxr window → vrOutput]
    K16 --> K17[workspace setVrMode true\nstart watchdog timer]
    K17 --> K18([VR Active])
```

---

## 4. SBS Button Press Detection

Specific to EDID-triggered profiles (e.g. Xreal Air). NVIDIA does not emit
`CONNECTOR_STATUS` on mode changes — the custodian handles this explicitly.

```mermaid
flowchart TD
    A([User presses SBS button\non Xreal Air]) --> B[Glasses switch\nfrom 1920x1080 → 3840x1080]
    B --> C[NVIDIA DRM driver emits\ncard-level change event\nno CONNECTOR_STATUS property]
    C --> D[udevmonitor: drmRescanNeeded signal]
    D --> E[scanConnectors]
    E --> F[For each connected DRM connector:\nread EDID → matchConnector]
    F --> G{EDID matches\nXreal Air profile?}
    G -- no --> H([No action])
    G -- yes --> I[readCurrentMode from sysfs]
    I --> J{Mode == 3840x1080\nisSbsMode?}
    J -- no --> H
    J -- yes --> K{m_active?}
    K -- yes --> H
    K -- no --> L[activateProfile\nsee Flow 3]

    B --> M[Plugin side: Output::currentModeChanged fires]
    M --> N[checkOutputMode]
    N --> O{Custodian on\nD-Bus?}
    O -- yes --> P[Defer to custodian\nreturn — no action]
    O -- no --> Q[activateForProfile\ndirect — no custodian]
```

---

## 5. VR Deactivation Flow (Custodian + Plugin)

**Critical NVIDIA constraint:** Monado must never receive `StopUnit` while the display
is still in SBS mode. The GPU deadlocks during Vulkan compositor cleanup in that state.
The deferred-stop pattern enforces this ordering.

```mermaid
flowchart TD
    T([Trigger:\nDesktop mode detected /\nUSB removed / manual stop]) --> D1[deactivateActive]

    D1 --> D2[notifyPluginDeactivate\nasync D-Bus: requestDeactivate]
    D2 --> D3[Send HID 2D init\nUSB command to glasses\nstart hardware mode switch]
    D3 --> D4[m_active = false\nclear m_activeProfile / m_activeOutput]
    D4 --> D5[Destroy m_monadoSocketWatcher\nunsubscribeUnitStateChanges]
    D5 --> D6[m_pendingRuntimeStop = true\nm_stoppingProfile = profile]
    D6 --> D7{m_pluginAvailable?}
    D7 -- no --> D8[executePendingRuntimeStop\nimmediately — no plugin to wait for]
    D7 -- yes --> D9([Wait for vrStopped or\nplugin vanish])

    D9 --> E1{vrStopped\nreceived?}
    E1 -- yes → normal path --> E2[executePendingRuntimeStop]
    E1 -- no, plugin\nvanished --> E3[onPluginVanished:\nm_pluginAvailable = false\nexecutePendingRuntimeStop]
    E3 --> E2

    E2 --> E4{m_pendingRuntimeStop?}
    E4 -- no, already done --> E5([No-op])
    E4 -- yes --> E6[m_pendingRuntimeStop = false\nclear m_stoppingProfile]
    E6 --> E7[stopRuntime\nStopUnit monado.service\nasync with reply watcher]
```

### Plugin side of deactivation

```mermaid
flowchart TD
    R([requestDeactivate\nreceived]) --> R1[setVrActive false]
    R1 --> R2[m_retryOutput = null\nstop]
    R2 --> R3[disconnect monadoWindowConnection\ndisconnect monadoFsConnection\nxrTest.stop]
    R3 --> R4{m_cursorHidden?}
    R4 -- yes --> R5[showCursor\nm_cursorHidden = false]
    R5 --> R6[setDmabufFormatFilterForQt false\nwatchdogTimer.stop]
    R4 -- no --> R6
    R6 --> R7[m_engine.deleteLater\nm_engine = null]
    R7 --> R8([engine destroyed signal fires])
    R8 --> R9[workspace setVrMode false\nclear VR window refs\npointer forcedFocusWindow = null]
    R9 --> R10[m_vrOutput = null\nm_activeProfile = nullopt\nm_active = false\nQ_EMIT vrActiveChanged]
    R10 --> R11[notifyCustodianVrStopped\nasync D-Bus: vrStopped]
    R11 --> R12{m_retryOutput set?}
    R12 -- yes --> R13[Schedule retry in 3s\nactivateForProfile on retryOutput]
    R12 -- no --> R14[maybeRestoreServiceVr]
```

---

## 6. USB Hotplug Flow

Handles USB device connect/disconnect, avoiding accidental 2D HID resets during VR.

```mermaid
flowchart TD
    A([udev: USB device added]) --> B[Find matching profile\nby hidVendorId:hidProductId]
    B --> C{Profile\nmatched?}
    C -- no --> END([No action])
    C -- yes --> D{VR active for\nthis USB device?}
    D -- yes --> E[Log: USB reconnect during\nactive session — skip HID init\nPrevents 2D reset during\nSBS mode switch]
    D -- no --> F[Send HID 2D init\nput device in desktop mode]
    E --> END
    F --> END

    G([udev: USB device removed]) --> H{VR active for\nthis device?}
    H -- yes --> I[Log removal\nDRM connector event will\nhandle VR deactivation]
    H -- no --> END
    I --> END
```

---

## 7. Monado Socket Lifecycle

Detailed view of the startup monitoring introduced to fix stale-socket freezes.

```mermaid
flowchart TD
    S([startRuntime called\nfor monado profile])

    S --> C1{Socket file\nexists?}

    C1 -- yes --> C2{isServiceActive\nmonado.service?}
    C2 -- no --> C4
    C2 -- yes --> C3{isSocketLive\nnon-blocking connect?}
    C3 -- no ECONNREFUSED --> C4[STALE SOCKET\nQFile::remove socket\nlog warning]
    C3 -- yes EINPROGRESS/OK --> C5[Monado genuinely running\nnotifyPluginActivate immediately]

    C1 -- no --> C6
    C4 --> C6[Send StartUnit async\nwatch reply with\nQDBusPendingCallWatcher]

    C6 --> C7[Watch XDG_RUNTIME_DIR\nwith QFileSystemWatcher]
    C6 --> C8[LoadUnit → get unit path\nconnect PropertiesChanged\nfor failure detection]

    C7 --> W{Directory\nchange fired?}
    W --> W2{Socket file\nexists now?}
    W2 -- no --> W
    W2 -- yes --> W3{isSocketLive?}
    W3 -- no --> W
    W3 -- yes --> W4[Disconnect socket watcher\nunsubscribeUnitStateChanges\nnotifyPluginActivate]

    C8 --> F{PropertiesChanged:\nActiveState == failed?}
    F -- yes --> F2[Abort activation\nclear m_active etc.\nno stopRuntime needed\nunit already failed]
    F -- no or other state --> F3([Continue watching])

    C6reply{StartUnit reply\nerror?}
    C6reply -- yes --> F2
    C6reply -- no --> W
```

---

## 8. Profile Priority and Preemption

When two profiles could match simultaneously (e.g. WiVRn running while SBS button pressed).

```mermaid
flowchart TD
    A([activateProfile called]) --> B{m_active?}
    B -- no --> C[Set m_active = true\nm_activeProfile = new profile\nstartRuntime]
    B -- yes --> D[Compare priorities\nnewPrio vs activePrio]
    D --> E{newPrio >\nactivePrio?}
    E -- no --> F([Ignore — lower or equal priority\nlog and return])
    E -- yes --> G[deactivateActive current\nsee Flow 5]
    G --> C

    subgraph Priority Values
        P1[Edid trigger = 2\ne.g. Xreal Air SBS]
        P2[Service trigger = 1\ne.g. WiVRn]
        P3[Always trigger = 0\nflat_monitor fallback]
    end
```

---

## 9. Plugin Output Mode Monitoring

The plugin independently watches outputs for mode changes. When the custodian is
present, the plugin defers all SBS-triggered activation to the custodian.

```mermaid
flowchart TD
    A([Output::currentModeChanged]) --> B[checkOutputMode]
    B --> C[matchDisplayProfile\ncurrent output]
    C --> D{Profile\nmatched?}
    D -- no --> END([No action])
    D -- yes --> E[Read current mode\nwidth x height]
    E --> F{isSbsMode?}

    F -- yes, VR not active --> G{Custodian on\nD-Bus?}
    G -- yes --> H([Defer to custodian\nreturn — custodian owns\nactivation sequence])
    G -- no --> I[activateForProfile\ndirect fallback]

    F -- yes, VR active,\nno vrOutput,\nservice profile --> J[Preempt service VR\nsetVrActive false\nschedule display VR in 500ms]

    F -- no, VR active,\nvrOutput == this output --> K[SBS ended\nsetVrActive false]

    F -- no, VR not active --> END
```

---

## 10. Custodian–Plugin D-Bus Interface Summary

All inter-process communication between the custodian and plugin.

```mermaid
flowchart LR
    subgraph Custodian ["kwin-vr-custodian\norg.kde.kwinvr.Custodian\n/Custodian"]
        CS1[vrReady slot]
        CS2[vrStopped slot]
        CS3[manualActivate slot]
        CS4[profileActivated signal]
        CS5[profileDeactivated signal]
    end

    subgraph Plugin ["kwin-vr plugin\norg.kde.kwinvr\n/KwinVr"]
        PS1[requestActivateProfile slot]
        PS2[requestDeactivate slot]
        PS3[notifyLinkDegraded slot]
        PS4[vrActive property]
    end

    CS4 -->|async call:\nrequestActivateProfile\nprofileName, outputName| PS1
    CS5 -->|async call:\nrequestDeactivate| PS2
    PS1 -->|after VR layout ready\nasync call: vrReady| CS1
    PS2 -->|after VR teardown\nasync call: vrStopped| CS2
    PS4 -->|polled by vr-link-monitor\nsystem service| MONITOR[vr-link-monitor\nsystem service]
    MONITOR -->|async call:\nnotifyLinkDegraded| PS3
```

---

## Invariants — Never Violate These

| # | Invariant | Why |
|---|-----------|-----|
| 1 | `stopRuntime()` is called **only** from `executePendingRuntimeStop()` | Ensures Monado is never stopped before plugin confirms VR teardown |
| 2 | `executePendingRuntimeStop()` is guarded by `m_pendingRuntimeStop` | Prevents double-stop if both vrStopped() and onPluginVanished() fire |
| 3 | `isSocketLive()` is called before trusting any existing `monado_comp_ipc` | Stale socket from SIGKILL'd Monado must not trigger premature plugin notification |
| 4 | `scanConnectors()` runs before `scanUsbDevices()` at startup | If already in SBS mode, m_active = true before USB scan so 2D HID init is skipped |
| 5 | `onUsbDeviceAdded()` skips HID init if `m_active && VID:PID matches active profile` | Prevents 2D reset during SBS mode USB reconnect (glasses mid-switch) |
| 6 | `monado.service` has no `[Install]` section | Must not be enabled; custodian owns its lifecycle |
| 7 | `XRT_COMPOSITOR_FORCE_WAYLAND=1` must never be in monado.service | Forces Vulkan Wayland compositor path that is invalidated by KWin output changes on NVIDIA |
| 8 | Headset output repositioning block stays removed from `kwinvrhelpers.cpp` | Atomic modeset position change on physical connectors fails with SIGSEGV on RTX 2070 |
