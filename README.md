# RL78_G16_ISP_Boot_loader_Xmodem

XMODEM-CRC128 Boot for R5F121BCAFP. This device Boot supports only this update interface/protocol.

## Board and interface

| Item | Configuration |
| --- | --- |
| Clock | HOCO / CPU 16 MHz |
| Update link | UART1 TX / RX P11 / P10, 115200 8-N-1 |
| Diagnostic Log | UART0 TX / RX P03 / P04, 115200 8-N-1 |
| Update interrupt | UART1 RX vector 0x20 |
| Timer vector | 0x1C |
| Flash implementation | RFSP Type01; CPU stalls during Code Flash programming |

Vector values are physical byte addresses, not channel numbers. UART0 carries text only. Cross UART TX/RX, or connect matching SCL/SDA with voltage-compatible pull-ups; share ground and verify logic levels.

## Image and interrupt ownership

Boot is 0x0000..0x1FFF (8 KiB), with at least 512 bytes spare. App vectors are 0x2000..0x20FF, metadata is 0x2100..0x21FF (256 bytes), and App code starts at 0x2200.
Maximum complete App BIN is 23 KiB; 0x07C00..0x07FFF is protected. Size includes vectors, metadata, padding and the four-byte CRC32.
Boot owns physical vectors: AA selects Boot handlers; 55 forwards through the App table. Normal handlers use RETI; BRK retains RETB.

## Configuration and application editing

- `image_metadata_config.h`: neutral MCU/Flash/format/Boot identity.
- `isp_transport_config.h`: selected ISP bus/protocol settings; metadata readers use the same values.
- `boot_app_handoff.h`: reserved RAM and AA/55 owner.
- `isp/`: protocol/update engine and board transport/Flash adapters.
- `image_metadata.c/.h`, `image_metadata_profile.c`: independent parser and expected profile.

App release/IRQ edits belong to the paired [App project](../RL78_G16_ISP_Boot_loader_Xmodem_app/README.md).

## Smart Configurator

Open this project's same-name `.scfg` from the CS+ Smart Configurator node.
After editing, use **Generate Code**, then **Rebuild** or the PowerShell command
below. Xmodem uses UART peripherals; UART0 remains the independent text Log.

Pre-build checks the MCU, pins, clocks, serial contract and actual generated
registers, then creates this project's `sc_peripheral_config.generated.h` for
runtime initialization. This header is an output, not an authoring input.
Update-link changes also need the paired Boot's `isp_transport_config.h` and
matching Boot/App/Transfer SC settings.

The existing runtime retains ISR, queue, mailbox, protocol and vector handling.
Configuration steps and the seven-bit I2C / SVA conversion are in the
[SC workflow](https://released.github.io/slide_boot_loader_for_RL78/serial-device.html#serial-scfg-workflow).

## Build and files

Run in this project root using installed CS+/CC-RL and Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .uild.ps1
```

Use `-Compiler <CubeSuite+.exe>` for a different installed CS+ path. Firmware authoring/build requires no Python or JSON editor. Generated INC/identity files are outputs, not inputs. App/Transfer wrappers build only themselves.

| File under DefaultBuild | Use |
| --- | --- |
| `boot0000_1FFF.hex` | Programmer installation of only the 8-KiB Boot region |

The full project HEX/MOT/ABS may contain IDE/device-file regions; it is not the Boot-only installation file.

## Tool operation and protocol

App/Transfer can advertise optional command0x25 UART diagnostics. Device RX
errors/drops,TX timeouts and queue snapshots are separate from bridge counters.
See [diagnostic fields](https://released.github.io/slide_boot_loader_for_RL78/serial-device.html#serial-uart-diagnostics).

Install Boot with a programmer, then select **UART / Xmodem > XMODEM-CRC** in the Tool. Load the paired App update BIN and **Discover Target**. If App is running, use **Enter Boot**, then **Start Device Update** before the 30-second valid-App inactivity window expires. Discovery of Boot can proceed directly to update.

Framed ISP control stages metadata and checks START. XMODEM-CRC128 carries data (128-byte blocks, CRC16, final 0x1A padding). A complete-image CRC32 still gates EOT and launch; one EOT only.

Diagnostic command 24 starts a RAM CRC32 sink in App/Transfer, not Flash programming. The Tool checks 389 bytes (including a short final block), PING, 96-byte ECHO and counters. Receiver duplicate blocks are compared exactly; diagnostic data never erases/writes Flash or requests reset.

Only a valid installed App supplies the version floor. Enabled policy permits same/newer versions. The explicit force operation skips version ordering for one transaction only; identity, layout, minimum Boot, metadata, vector and CRC checks remain active.

See [PROTOCOL.md](PROTOCOL.md) for byte layouts and transport behavior.
[Tool operation and wiring](https://released.github.io/slide_simple_renesas_isp_tool/#uart-device-operation) provides the common operation flow and report links.
Offline build/model results do not establish electrical, physical IRQ/Flash, dynamic-stack, restart or power-interruption acceptance.

## User code entry

`custom_func.c` provides `hardware_init()` for initialization and `loop()` for
foreground service. Add application initialization and foreground work through
these callbacks, retaining the existing communication service calls.
The selected main/startup adapter owns entry and handoff. Generated peripheral
files remain under `src/`; retain the project's MTPJ source selection when using
Code Generator or Smart Configurator, then rebuild to validate the image and vectors.

## Project layout and standalone build

This project includes its own source files, configuration headers and build tools.
A sibling Boot, App or Transfer checkout is not required to compile it.
Keep the project directory name aligned with its `.mtpj` filename; remove a ZIP download suffix when necessary.
Build with CS+ Rebuild, or run the local PowerShell entry:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

| Location | Responsibility |
| --- | --- |
| `custom_func.c` | Project initialization in `hardware_init()` and recurring work in `loop()`; runtime orchestration stays here |
| `hal/can` | CAN service, controller driver and CAN adapter, when used by this project |
| `hal/device` | Device, clock, peripheral and CPU handoff APIs |
| `hal/image` | Metadata parser/profile, image validation and software CRC |
| `hal/flash` | Flash access/geometry APIs, when required by the selected image |
| `hal/isp` | Update/Transfer protocol and transport processing APIs |
| Root configuration headers | Local MCU/Flash, handoff and communication contract |
| `tools` and root PowerShell helpers | Local metadata/IRQ generation and linked-image checks |
| `src` | Code Generator or Smart Configurator peripheral sources |

Only the sources registered in this project's CS+ configuration are linked.
Generated main/vector implementations must not become a second active entry.
Retain the `custom_func.c` callbacks and the selected startup adapter after code generation.

Boot and App each carry a local contract. Keep their MCU, Flash layout, image format,
IRQ ABI, handoff and communication settings compatible when installing a pair.
App releases are edited in `app_image_config.h` and `app_irq_handlers.h` in the App project.
Rebuild the selected App to regenerate its metadata, vector table, update BIN and timing BINs.
The App build does not read or rewrite a Boot checkout.

## Guides and programming identity

- [Tool operation](https://released.github.io/slide_simple_renesas_isp_tool/xmodem.html)
- [G16 configuration and experiment index](https://released.github.io/slide_boot_loader_for_RL78/xmodem-device.html#upgrade-g16-xmodem)
- On-chip-debug Security ID is ten bytes at0xC4..0xCD. Linker and CS+ debugger
  both use00000000000000000000;local build checks verify the linked/programmer HEX.
  C3 remains85. The serial-programming security ID is a separate setting.
- Boot retains compiled diagnostics but starts muted before App validation.
  No UART0 ASCII0/1 log-control or z/Z reset entry is exposed by Boot.
