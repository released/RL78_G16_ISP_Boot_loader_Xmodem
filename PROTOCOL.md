# XMODEM-CRC128 device protocol - RL78/G16

This is the contract for the independent RL78_G16_ISP_Boot_loader_Xmodem, RL78_G16_ISP_Boot_loader_Xmodem_app and RL78_G16_Xmodem_Transfer projects. [Tool operation](https://released.github.io/slide_isp_tool_for_RL78/#uart-device-operation) owns wiring and UI steps. The device UART0 Log is a separate text connection.

## Transport and identity

| Item | Value |
| --- | --- |
| Update link | UART1 TX / RX P11 / P10, 115200 8-N-1 |
| Contract / protocol ID | 3 / 0x58 |
| Image magic | ISP plus NUL, bytes 49 53 50 00 |
| Metadata | App+0x100, 256 bytes; core128 and reserved128 FF |
| Metadata protocol word | 0x01010058 |
| Policy word at metadata0x64 | 0x04012003 (policy3,32 bytes,DEVICE_APP,UART) |
| Policy baud at0x70 | 115200 |
| Version policy at0x74 | 0=any version;1=same/newer from valid installed App |
| Link words0x30..0x3F | 0,0,0,0 |

Diagnostic availability comes from live INFO;Boot does not advertise bit6.
Snapshot fields are defined in the [serial diagnostic reference](https://released.github.io/slide_boot_loader_for_RL78/serial-device.html#serial-uart-diagnostics).
Protocol CLEAR_STATS does not reset the board's diagnostic counters.

## Framed control bytes

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 2 | 49 53 frame marker |
| 2 | 1 | Framing version1 |
| 3 | 1 | 0=request,1=response |
| 4 | 2 | Sequence LE16,1..65535 |
| 6 | 1 | Command |
| 7 | 1 | Status;request0 |
| 8 | 2 | Payload length LE16,0..96 |
| 10 | 0..96 | Payload |
| 10+length | 4 | CRC32 of header/payload,LE32 |

CRC32/ISO-HDLC uses reflected polynomial EDB88320, initial/final XOR FFFFFFFF; 123456789 gives CBF43926. Maximum frame110 bytes; partial framed input expires after200ms. Equal sequence replay requires identical payload. Conflicting duplicates are rejected.

## Commands and update boundaries

| Command | Payload / result |
| --- | --- |
| 01 INFO | 88-byte live MCU/profile/geometry/installed identity/capabilities |
| 02 ENTER | App replies completely before resetting into Boot;Boot ACK |
| 03 METADATA | LE16 offset plus4..64 bytes;ordered stage256 before START |
| 04 START /0E FORCE_START | LE32 full image size plusLE32 stored final CRC;validate before erase |
| 05 WRITE /06 END | Rejected in Xmodem Boot;raw blocks/EOT own data/finalization |
| 07 ABORT | Clear session/staging;does not restore erased contents |
| 08 READ_METADATA | Valid installed App;LE16 offset plusU8 count1..64 |
| 09 VERIFY | Boot read-only installed-image validation |
| 20 PING /21 ECHO | App/Transfer only;0..96-byte echo |
| 22 STATS /23 CLEAR_STATS | App/Transfer only;fourLE32 counters:requests,replays,errors,written |
| 24 STREAM_TEST | App/Transfer only;LE32 size1..65536 plusLE32 CRC32;RAM diagnostic sink,no Flash/reset |
| 25 DIAGNOSTICS | Optional App/Transfer INFO bit6;24-byte UART errors/drops/TX timeout/queue snapshot |

Framed ISP control stages metadata and checks START. XMODEM-CRC128 carries data (128-byte blocks, CRC16, final 0x1A padding). A complete-image CRC32 still gates EOT and launch; one EOT only.

Diagnostic command 24 starts a RAM CRC32 sink in App/Transfer, not Flash programming. The Tool checks 389 bytes (including a short final block), PING, 96-byte ECHO and counters. Receiver duplicate blocks are compared exactly; diagnostic data never erases/writes Flash or requests reset.

## XMODEM-CRC data bytes

| Bytes | Meaning |
| --- | --- |
| 0 | SOH01 |
| 1 /2 | Block number /ones complement;8-bit wraps |
| 3..130 | 128 data bytes;final unused positions1A |
| 131..132 | CRC16/XMODEM over128 data bytes,high byte first;poly1021,init0 |
| Single byte04 | EOT,one complete-image finalization |

Receiver prompts C (43),ACK06,NAK15,or CAN18 twice. The Tool retries at most three identical block attempts,never EOT. CRC16 protects each padded block;the declared size and CRC32 protect exactly the useful full image or diagnostic data. A partial block expires after200ms;idle receiver cancels after10s. Cancellation/error restores the framed parser. Diagnostic replay never accumulates the same bytes twice.

Boot checks metadata, MCU/partition/IRQ/minimum-Boot contract, valid-installed-App policy, range, stored trailer and full CRC before launch. FORCE skips ordering only for its transaction;no persistent unlock/floor. Boot idle30s returns to an already valid App only before an active update. App ISR authoring uses app_irq_handlers.h,AA/55 ownership and generated full tables.

Build/package/model results are offline evidence;board electrical/IRQ/Flash/reset/power acceptance is separate.
