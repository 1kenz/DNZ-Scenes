# ADR-0001: Own virtual workspaces via Accessibility API, no native Spaces automation

- **Tarih:** 2026-10-28
- **Durum:** Önerildi
- **Karar verenler:** Ken Z

## Bağlam
Personal tool to switch named contexts across 3 screens (2 monitors + MacBook) with one hotkey. As far as we found, macOS has no public API to switch Spaces or move windows between them. Hammerspoon documents its Space module as experimental, using private APIs Apple may change at any time. yabai needs SIP partially disabled for Space operations. Target OS: macOS 27 (not verified against this ADR yet).

## Değerlendirilen Seçenekler
1. **Automate native Spaces (key simulation / private CGS APIs)** — native look, but fragile across OS updates and hard to sync 3 displays.
2. **Own virtual workspaces (Accessibility API + NSWorkspace)** — no SIP change, public APIs, full control; window-level handling of Electron/Chrome is harder.
3. **GUI on top of AeroSpace/Hammerspoon** — fastest prototype, but ties identity and permission model to another project.

## Karar
Option 2. Swift + AppKit menu bar app; decision logic in a pure `ScenesCore` library. Displays identified by UUID. Local JSON config, schema-versioned. No network, no telemetry, zero third-party dependencies. Security: Accessibility permission is powerful, so the app stays local-only and the context launcher may only open apps/URLs (no shell execution).

## Sonuçlar
- Olumlu: Survives OS updates better than private APIs; no SIP changes; testable logic.
- Olumsuz / kabul edilen trade-off: Window-level assignment (e.g. two browser profiles) deferred to v1; native full-screen apps live in their own Space and need separate handling.
- Geri dönüş maliyeti: düşük

## Decision Registry Özeti

| Alan | Değer |
|---|---|
| ID | ADR-0001 |
| Başlık | Own virtual workspaces via Accessibility API, no native Spaces automation |
| Tarih | 2026-10-28 |
| Durum | Önerildi |
| Kategori | Mimari |
| Etki | Yüksek |
| Özet | DNZ-Scenes manages its own workspaces with public APIs (Accessibility, NSWorkspace) instead of automating native Spaces, avoiding private API breakage and SIP changes. |
| İlgili ADR'ler | — |
